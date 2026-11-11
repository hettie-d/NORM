"""Generating and running *_to_db (build_to_db.sql, generate_to_db_function.sql)."""

import pytest
from psycopg.types.json import Json

from helpers import USER_ACCOUNT_JSON, column, compile_schema, scalar, to_json


def acct_to_db(db, payload):
    return scalar(db, "select norm_small.acct_to_db(%s)", (Json(payload),))


def shop_to_db(db, payload):
    return scalar(db, "select norm_shop.shop_to_db(%s)", (Json(payload),))


def account(db, account_id):
    return db.execute(
        "select username, first_name, last_name, dob::text from norm_small.account where account_id = %s",
        (account_id,),
    ).fetchone()


def phones(db, account_id):
    return column(db, "select phone from norm_small.phone where account_id = %s order by 1", (account_id,))


def test_build_to_db_reports_an_unknown_schema(db):
    result = scalar(db, "select norm_gen.build_to_db('no_such_schema')")
    assert result == "INVALID PARAMETER no_such_schema: schema does not exist"


def test_generate_to_db_function_reports_errors(db):
    result = scalar(db, "select norm_gen.generate_to_db_function('no_such_schema')")
    assert result == "ERROR:INVALID PARAMETER no_such_schema: schema does not exist"


def test_build_to_db_script_is_complete(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    script = scalar(db, "select norm_gen.build_to_db('user_account')")
    assert script.startswith("/* Generating to_db for user_account*/")
    assert script.endswith("/* The end */")
    assert "/* Missing" not in script


def test_generate_to_db_function_creates_the_function_family(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    db.execute("select norm_gen.create_generated_types('user_account')")
    assert scalar(db, "select norm_gen.generate_to_db_function('user_account')") == "norm_small.acct_to_db"
    assert column(
        db,
        """select proname::text from pg_proc
            where pronamespace = 'norm_small'::regnamespace and proname like 'acct%%' order by 1""",
    ) == [
        "acct_account_delete",
        "acct_account_insert",
        "acct_account_update",
        "acct_emails_delete",
        "acct_emails_insert",
        "acct_emails_insert_param",
        "acct_emails_update",
        "acct_parse",
        "acct_phones_delete",
        "acct_phones_insert",
        "acct_phones_insert_param",
        "acct_phones_update",
        "acct_to_db",
    ]


def test_parse_reads_the_input_json(db, user_account):
    payload = [{"username": "x", "phones": [{"phone_number": "1", "phone_type_id": 2}]}]
    [parsed] = to_json(db, "select norm_small.acct_parse(%s)", (Json(payload),))
    assert (parsed["username"], parsed["account_id"], parsed["cmd"]) == ("x", None, None)
    assert parsed["phones"] == [{"phone_id": None, "phone_number": "1", "phone_type_id": 2, "cmd": None}]


def test_insert_a_new_parent(db, user_account):
    [new_id] = acct_to_db(db, [{"username": "new1", "first_name": "Nina", "dob": "2000-01-02"}])
    assert account(db, new_id) == ("new1", "Nina", None, "2000-01-02")


def test_insert_a_new_parent_with_a_child(db, user_account):
    [new_id] = acct_to_db(db, [{"username": "new2", "phones": [{"phone_number": "555", "phone_type_id": 1}]}])
    assert phones(db, new_id) == ["555"]

def test_insert_a_new_parent_with_a_child_inserts_the_child_once(db, user_account):
    acct_to_db(db, [{"username": "new3", "phones": [{"phone_number": "556", "phone_type_id": 1}]}])
    assert scalar(db, "select count(*) from norm_small.phone where phone = '556'") == 1


def test_insert_two_new_parents_with_children(db, user_account):
    acct_to_db(
        db,
        [
            {"username": "u1", "phones": [{"phone_number": "111", "phone_type_id": 1}]},
            {"username": "u2", "phones": [{"phone_number": "222", "phone_type_id": 1}]},
        ],
    )
    assert db.execute(
        """select a.username, p.phone from norm_small.account a
             left join norm_small.phone p using (account_id)
            where a.username in ('u1', 'u2') order by 1"""
    ).fetchall() == [("u1", "111"), ("u2", "222")]


def test_add_a_child_to_an_existing_parent(db, user_account):
    assert acct_to_db(
        db, [{"account_id": 2, "emails": [{"email_address": "b@x.com", "email_priority_id": 2}]}]
    ) == [2]
    assert column(db, "select email from norm_small.email where account_id = 2 order by 1") == [
        "b@x.com",
        "johnsonbs@hotmail.com",
    ]


def test_update_changes_only_the_given_fields(db, user_account):
    assert acct_to_db(db, [{"account_id": 3, "first_name": "Alicia"}]) == [3]
    assert account(db, 3) == ("smithalice", "Alicia", "smith", "1998-12-31")


def test_update_a_child(db, user_account):
    acct_to_db(db, [{"account_id": 1, "phones": [{"phone_id": 1, "phone_number": "999"}]}])
    assert phones(db, 1) == ["3121233344", "999"]


@pytest.mark.parametrize("cmd", ["delete", "DELETE"])
def test_delete_a_child(db, user_account, cmd):
    acct_to_db(db, [{"account_id": 1, "phones": [{"phone_id": 2, "cmd": cmd}]}])
    assert phones(db, 1) == ["2021234567"]


def test_delete_a_parent_deletes_its_children(db, user_account):
    assert acct_to_db(db, [{"account_id": 2, "cmd": "delete"}]) == [2]
    assert account(db, 2) is None
    assert scalar(db, "select count(*) from norm_small.email where account_id = 2") == 0


def test_one_call_can_update_and_insert(db, user_account):
    ids = acct_to_db(db, [{"account_id": 1, "last_name": "jones"}, {"username": "new4"}])
    new_id = scalar(db, "select account_id from norm_small.account where username = 'new4'")
    assert sorted(ids) == sorted([1, new_id])
    assert account(db, 1)[2] == "jones"


def test_insert_a_new_root_with_all_columns(db, shop):
    [new_id] = shop_to_db(db, [{"name": "Cy", "tier_id": 1, "joined": "2024-01-01"}])
    assert db.execute(
        "select name, tier_id, joined::text from norm_shop.customer where customer_id = %s", (new_id,)
    ).fetchone() == ("Cy", 1, "2024-01-01")


def test_insert_at_the_second_and_third_level(db, shop):
    lines = [{"product_id": 2, "qty": 7}, {"product_id": 3, "qty": 1}]
    assert shop_to_db(db, [{"customer_id": 1, "orders": [{"order_name": "A3", "lines": lines}]}]) == [1]
    assert db.execute(
        """select o.customer_id, l.product_id, l.qty from norm_shop.orders o
             join norm_shop.order_line l using (order_id)
            where o.order_name = 'A3' order by 2"""
    ).fetchall() == [(1, 2, 7), (1, 3, 1)]


def test_update_at_the_third_level(db, shop):
    shop_to_db(db, [{"customer_id": 2, "orders": [{"order_id": 3, "lines": [{"line_id": 4, "qty": 9}]}]}])
    assert scalar(db, "select qty from norm_shop.order_line where line_id = 4") == 9


def test_delete_at_the_second_level_deletes_grandchildren(db, shop):
    shop_to_db(db, [{"customer_id": 1, "orders": [{"order_id": 2, "cmd": "delete"}]}])
    assert column(db, "select order_id from norm_shop.orders order by 1") == [1, 3]
    assert column(db, "select line_id from norm_shop.order_line order by 1") == [1, 2, 4]
