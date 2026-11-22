"""Sorting and paging options (build_order_clause.sql): select_options and build_order_by."""

import pytest
from psycopg.types.json import Json

from helpers import column, scalar

# The shop root table and its embedded tier table, aliased the way build_order_by expects.
SHOP_FROM = "from norm_shop.customer top join norm_shop.tier t on t.tier_id = top.tier_id"


def order_by(db, options, *alias):
    """build_order_by's clause for `options`, with whitespace squashed."""
    args = ", %s" * len(alias)
    sql = scalar(db, f"select norm_gen.build_order_by(%s{args})", (Json(options), *alias))
    return " ".join(sql.split())


def customer_names(db, options):
    """Customer names, selected with the clause build_order_by builds for `options`."""
    clause = scalar(db, "select norm_gen.build_order_by(%s)", (Json(options),))
    return column(db, f"select top.name {SHOP_FROM} {clause}")


@pytest.mark.parametrize(
    "keyword, sql",
    [
        ("$Limit", "LIMIT "),
        ("$Offset", "OFFSET "),
        ("$limit", "UNKNOWN "),
        ("$OrderBy", "UNKNOWN "),
        (None, "UNKNOWN "),
    ],
)
def test_select_options(db, keyword, sql):
    assert scalar(db, "select norm_gen.select_options(%s)", (keyword,)) == sql


@pytest.mark.parametrize(
    "order, expected",
    [
        (["name"], "ORDER BY top.name"),
        (["name", "joined"], "ORDER BY top.name, top.joined"),
        ([{"name": "DESC"}], "ORDER BY top.name DESC"),
        ([{"joined": "DESC NULLS LAST"}, "name"], "ORDER BY top.joined DESC NULLS LAST, top.name"),
        (["tier"], "ORDER BY t.tier_name"),
        ([{"$Expression": "length(top.name) desc"}], "ORDER BY length(top.name) desc"),
        ([{"$Expression": "top.joined"}, {"name": "ASC"}], "ORDER BY top.joined, top.name ASC"),
        (["nosuchkey"], "ORDER BY top.INVALID KEYnosuchkey"),
        ([], ""),
    ],
    ids=[
        "key",
        "keys-in-order",
        "direction",
        "direction-and-nulls",
        "embedded-alias",
        "expression",
        "expression-then-key",
        "unknown-key",
        "empty",
    ],
)
def test_build_order_by(db, shop, order, expected):
    assert order_by(db, {"shop": {}, "$OrderBy": order}) == expected


def test_build_order_by_custom_alias(db, shop):
    options = {"shop": {}, "$OrderBy": ["name", "tier"]}
    assert order_by(db, options, "c") == "ORDER BY c.name, t.tier_name"


@pytest.mark.parametrize(
    "options, expected",
    [
        ({"shop": {}, "$Limit": 5}, "LIMIT 5"),
        ({"shop": {}, "$Offset": 10}, "OFFSET 10"),
        ({"shop": {}, "$Limit": 5, "$Offset": 10}, "LIMIT 5 OFFSET 10"),
        ({"shop": {}, "$Offset": 10, "$Limit": 5}, "OFFSET 10 LIMIT 5"),
        (
            {"shop": {"name": "Ann"}, "$OrderBy": [{"name": "DESC"}], "$Limit": 5, "$Offset": 10},
            "ORDER BY top.name DESC LIMIT 5 OFFSET 10",
        ),
        ({"shop": {"name": "Ann"}}, ""),
    ],
    ids=["limit", "offset", "limit-offset", "offset-limit", "everything", "nothing"],
)
def test_build_order_by_limit_offset(db, shop, options, expected):
    assert order_by(db, options) == expected


ACCOUNT_FILTER = {
    "username": "bobacct2",
    "last_name": "Smith",
    "email_address": "js@somewhere",
    "phone_type": "mobile",
}


@pytest.mark.parametrize(
    "options, expected",
    [
        (
            {
                "user_account": ACCOUNT_FILTER,
                "$OrderBy": [
                    "phone_type",
                    "first_name",
                    "last_name",
                    {"username": "desc"},
                    {"$Expression": "upper(top.first_name)"},
                    {"$Expression": "anything"},
                ],
                "$Limit": "20",
                "$Offset": "100",
            },
            "ORDER BY pt.phone_type, top.first_name, top.last_name, top.username desc,"
            " upper(top.first_name), anything LIMIT 20 OFFSET 100",
        ),
        ({"user_account": ACCOUNT_FILTER, "$Limit": "20", "$Offset": "100"}, "LIMIT 20 OFFSET 100"),
        ({"user_account": ACCOUNT_FILTER, "$Offset": "100"}, "OFFSET 100"),
        ({"user_account": ACCOUNT_FILTER}, ""),
    ],
    ids=["order-limit-offset", "limit-offset", "offset", "filter-only"],
)
def test_build_order_by_user_account(db, user_account, options, expected):
    # phone_type is a key of the nested phone object; it is taken from its embedded alias pt.
    assert order_by(db, options) == expected


def test_build_order_by_without_a_compiled_schema(db):
    """Keys are looked up in the compiled schema; without one, every key is unknown."""
    options = {"shop": {}, "$OrderBy": ["name"], "$Limit": 3}
    assert order_by(db, options) == "ORDER BY top.INVALID KEYname LIMIT 3"


@pytest.mark.parametrize(
    "options, expected",
    [
        ({"shop": {}, "$OrderBy": ["name"]}, ["Ann", "Bob"]),
        ({"shop": {}, "$OrderBy": [{"name": "DESC"}]}, ["Bob", "Ann"]),
        ({"shop": {}, "$OrderBy": [{"joined": "DESC"}]}, ["Bob", "Ann"]),
        ({"shop": {}, "$OrderBy": [{"tier": "DESC"}]}, ["Bob", "Ann"]),  # standard > gold
        ({"shop": {}, "$OrderBy": [{"$Expression": "top.tier_id"}]}, ["Bob", "Ann"]),
        ({"shop": {}, "$OrderBy": ["name"], "$Limit": 1}, ["Ann"]),
        ({"shop": {}, "$OrderBy": ["name"], "$Limit": 1, "$Offset": 1}, ["Bob"]),
        ({"shop": {}, "$OrderBy": ["name"], "$Offset": 2}, []),
    ],
    ids=["asc", "desc", "date", "embedded", "expression", "limit", "limit-offset", "past-the-end"],
)
def test_build_order_by_sorts_and_pages_rows(db, shop, options, expected):
    assert customer_names(db, options) == expected


# Known bugs, kept as strict xfails so each one shows up as XPASS (and fails the run) once it is fixed.


@pytest.mark.xfail(
    strict=True,
    reason="a NULL alias makes coalesce(db_source_alias, p_top_alias) || '.' NULL, "
    "which drops every root-level key and with it the whole ORDER BY",
)
def test_build_order_by_null_alias(db, shop):
    assert order_by(db, {"shop": {}, "$OrderBy": ["name", "tier"]}, None) == "ORDER BY name, t.tier_name"


@pytest.mark.xfail(
    strict=True,
    reason="db_expression keys are prefixed like columns, giving top.upper(name)",
)
def test_build_order_by_expression_key(db, shop):
    assert order_by(db, {"shop": {}, "$OrderBy": ["name_upper"]}) == "ORDER BY upper(top.name)"


@pytest.mark.xfail(
    strict=True,
    reason="a key name used by two objects (line and product) matches twice, "
    "so the ORDER BY term is repeated",
)
def test_build_order_by_key_in_two_objects_appears_once(db, shop):
    clause = order_by(db, {"shop": {}, "$OrderBy": ["product_id"]})
    assert clause.count("product_id") == 1
