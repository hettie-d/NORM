"""Search conditions and *_from_db (build_conditions_pkg.sql, generate_from_db.sql)."""

import psycopg
import pytest
from psycopg.types.json import Json

from helpers import column, compile_schema, scalar


def squash(text):
    return " ".join(text.split())


def search(db, function, schema, condition, field):
    """`field` of each record that `function` finds, sorted."""
    return column(
        db,
        f"select r.{field} from unnest({function}(%s)) r order by 1",
        (Json({schema: condition}),),
    )


@pytest.mark.parametrize(
    "op, sql",
    [
        ("$eq", " = "),
        ("$lt", " < "),
        ("$le", "<= "),
        ("$ne", "<> "),
        ("$ge", ">= "),
        ("$gt", " > "),
        ("$like", " LIKE "),
        ("$in", "UNKNOWN "),
    ],
)
def test_cond_ops(db, op, sql):
    assert scalar(db, "select norm_gen.cond_ops(%s)", (op,)) == sql


@pytest.mark.parametrize(
    "args, expected",
    [
        ("'username', 'bob', 'username', 'text'", "username = ('bob'::text)"),
        ("""'qty', '{"$gt": "5"}', 'qty', 'int4'""", "qty > ('5'::int4)"),
        ("'name', 'x', null, null", """"J_name" = ('x'::text)"""),
    ],
    ids=["value", "operator", "defaults"],
)
def test_build_simple_term(db, args, expected):
    assert squash(scalar(db, f"select norm_gen.build_simple_term({args})")) == expected


@pytest.mark.parametrize(
    "args, expected",
    [
        (
            "'account', 'phones', ' kind = 1 ', 'phone', 'account_id', 'owner_id', 'app', 'id'",
            "id IN ( select owner_id from app.phone where kind = 1 )",
        ),
        (
            "'parent', 'child', ' x = 1 ', null, null, null, null, null",
            '"PK_parent" IN ( select "FK_child_parent" from SCHEMA_.TABLE_child where x = 1 )',
        ),
    ],
    ids=["mapped", "placeholders"],
)
def test_build_object_term(db, args, expected):
    assert squash(scalar(db, f"select norm_gen.build_object_term({args})")) == expected


def test_build_conditions_nests_child_conditions(db, shop):
    condition = {"shop": {"orders": {"lines": {"product": {"product_name": "plum"}}}}}
    sql = scalar(db, "select norm_gen.build_conditions(%s)", (Json(condition),))
    assert squash(sql) == (
        "customer_id IN ( select customer_id from norm_shop.orders where"
        " order_id IN ( select order_id from norm_shop.order_line where"
        " product_id IN ( select product_id from norm_shop.product where"
        " product_name = ('plum'::text) ) ) )"
    )


def test_build_conditions_joins_terms_with_and(db, shop):
    condition = {"shop": {"tier": "gold", "name": {"$like": "A%"}}}
    sql = scalar(db, "select norm_gen.build_conditions(%s)", (Json(condition),))
    assert sorted(squash(term) for term in sql.split("\nAND ")) == [
        "name LIKE ('A%'::text)",
        "tier_id IN ( select tier_id from norm_shop.tier where tier_name = ('gold'::text) )",
    ]


@pytest.mark.parametrize(
    "condition, expected",
    [
        ({"username": "bobacct2"}, ["bobacct2"]),
        ({"username": "nobody"}, []),
        ({"first_name": "alice", "last_name": "smith"}, ["smithalice"]),
        ({"dob": {"$eq": "1996-04-01"}}, ["aliceacct1"]),
        ({"dob": {"$gt": "1996-04-01"}}, ["smithalice"]),
        ({"dob": {"$ge": "1996-04-01"}}, ["aliceacct1", "smithalice"]),
        ({"dob": {"$lt": "1996-04-01"}}, ["bobacct2"]),
        ({"dob": {"$le": "1996-04-01"}}, ["aliceacct1", "bobacct2"]),
        ({"dob": {"$ne": "1996-04-01"}}, ["bobacct2", "smithalice"]),
        ({"username": {"$like": "%alice%"}}, ["aliceacct1", "smithalice"]),
        ({"phones": {"phone_number": "3121233344"}}, ["aliceacct1"]),
        ({"phones": {"phone_type": "cell"}}, ["aliceacct1"]),
        ({"emails": {"email_priority": "primary"}}, ["aliceacct1", "bobacct2"]),
        ({"first_name": "alice", "emails": {"email_address": "alicejons@gmail.com"}}, ["aliceacct1"]),
    ],
)
def test_from_db(db, user_account, condition, expected):
    assert search(db, "norm_small.acct_from_db", "user_account", condition, "username") == expected


@pytest.mark.parametrize(
    "condition, expected",
    [
        pytest.param(
            {"tier": "gold"},
            ["Ann"],
            marks=pytest.mark.xfail(
                raises=psycopg.errors.AmbiguousColumn,
                strict=True,
                reason="root-level conditions use unqualified column names, which are "
                "ambiguous when an embedded table has a column with the same name",
            ),
        ),
        ({"name": "Bob", "orders": {"order_name": "B1"}}, ["Bob"]),
        ({"orders": {"lines": {"qty": {"$ge": 5}}}}, ["Ann"]),
        ({"orders": {"lines": {"product": {"product_name": "apple"}}}}, ["Ann", "Bob"]),
        ({"orders": {"lines": {"product": {"product_name": "plum"}}}}, ["Ann"]),
    ],
)
def test_from_db_three_levels_and_objects(db, shop, condition, expected):
    assert search(db, "norm_shop.shop_from_db", "shop", condition, "name") == expected


def test_from_db_on_a_single_object_schema(db):
    schema = scalar(db, "select norm_gen.table_to_transfer_schema('norm_shop', 'product', 'product_only')")
    compile_schema(db, schema)
    db.execute("select norm_gen.create_generated_types('product_only')")
    assert scalar(db, "select norm_gen.generate_from_db('product_only')") == "norm_shop.product_from_db"
    found = search(db, "norm_shop.product_from_db", "product_only", {"product_name": "pear"}, "product_name")
    assert found == ["pear"]


def test_from_db_rejects_another_schema_name(db, user_account):
    with pytest.raises(psycopg.errors.RaiseException, match="should be user_account"):
        db.execute("select norm_small.acct_from_db(%s)", (Json({"shop": {"name": "Ann"}}),))


def test_generate_from_db_reports_an_unknown_schema(db):
    result = scalar(db, "select norm_gen.generate_from_db('no_such_schema')")
    assert result == "ERROR:Invalid schema name: no_such_schema"
