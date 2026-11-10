"""Building nested SELECTs and *_select_by_ids (build_select_pkg.sql, generate_select_by_ids.sql)."""

import pytest

from helpers import USER_ACCOUNT_JSON, compile_schema, scalar, schema_id, to_json


def squash(text):
    return " ".join(text.split())


ALICE = {
    "account_id": 1,
    "username": "aliceacct1",
    "last_name": "johns",
    "first_name": "alice",
    "dob": "1996-04-01",
    "emails": [
        {
            "email_address": "alicejons@gmail.com",
            "email_id": 1,
            "email_priority": "primary",
            "email_priority_id": 1,
        }
    ],
    "phones": [
        {"phone_id": 1, "phone_type": "cell", "phone_number": "2021234567", "phone_type_id": 2},
        {"phone_id": 2, "phone_type": "cell", "phone_number": "3121233344", "phone_type_id": 2},
    ],
}

BOB = {
    "customer_id": 2,
    "name": "Bob",
    "name_upper": "BOB",
    "tier_id": 1,
    "tier": "standard",
    "joined": "2021-06-30",
    "orders": [
        {
            "order_id": 3,
            "order_name": "B1",
            "placed": "2024-05-01T10:00:00+00:00",
            "totals": {"line_count": 1, "total_qty": 2},
            "lines": [
                {
                    "line_id": 4,
                    "product_id": 1,
                    "qty": 2,
                    "product": {"product_id": 1, "product_name": "apple", "unit_price": 0.5},
                }
            ],
        }
    ],
}


@pytest.mark.parametrize(
    "args, expected",
    [
        ("'app', 'orders', 'o', null", "from app.orders o"),
        ("'app', '(select 1 as x)', 'e', null, 'Y'", "from (select 1 as x) e"),
        (
            "'app', 'phone', 'p', array[('pt', 'lk', 'phone_type', 'N', 'phone_type_id', 'type_id')::norm_gen.t_d_link]",
            "from app.phone p join lk.phone_type pt on pt.phone_type_id = p.type_id",
        ),
    ],
    ids=["table", "expression", "embedded"],
)
def test_build_from_clause(db, args, expected):
    assert squash(scalar(db, f"select norm_gen.build_from_clause({args})")) == expected


def test_build_where_clause(db):
    sql = scalar(db, "select norm_gen.build_where_clause('parent', 'id', 'child', 'parent_id')")
    assert squash(sql) == "where parent.id = child.parent_id"


def test_build_nested_row(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    sql = scalar(
        db,
        """select norm_gen.build_nested_row(%s, transfer_schema_object_id, 'account_record', 'top', 'account_id')
             from norm_gen.transfer_schema_object where t_object = 'account'""",
        (schema_id(db, "user_account"),),
    )
    sql = squash(sql)
    assert sql.startswith("/* Entering account_record */ row(top.account_id , top.username ,")
    assert sql.endswith(")::norm_small.acct_account_record)")
    # An array key becomes a sub-select on the child table, joined to its lookups.
    assert "join norm_small.phone_type pt on pt.phone_type_id = phones.phone_type_id" in sql
    assert "where top.account_id = phones.account_id" in sql


def test_nested_root(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    sql = scalar(db, "select norm_gen.nested_root('user_account')")
    assert sql == scalar(db, "select norm_gen.build_nested_select_clause('user_account')")
    assert squash(sql).startswith("/* selecting user_account account */ select array_agg(")
    assert squash(sql).endswith("from norm_small.account top")


def test_select_by_ids_returns_the_whole_hierarchy(db, user_account):
    assert to_json(db, "select norm_small.acct_select_by_ids(array[1])") == [ALICE]


def test_select_by_ids_with_objects_expressions_and_lookups(db, shop):
    assert to_json(db, "select norm_shop.shop_select_by_ids(array[2])") == [BOB]


def test_select_by_ids_skips_unknown_ids(db, user_account):
    rows = to_json(db, "select norm_small.acct_select_by_ids(array[3, 999])")
    # Without child rows, the child arrays are null rather than empty.
    assert [(r["username"], r["emails"], r["phones"]) for r in rows] == [("smithalice", None, None)]
    assert to_json(db, "select norm_small.acct_select_by_ids(array[999])") is None


def test_generate_select_by_id_reports_an_unknown_schema(db):
    result = scalar(db, "select norm_gen.generate_select_by_id('no_such_schema')")
    assert result == "ERROR:Invalid schema name: no_such_schema"
