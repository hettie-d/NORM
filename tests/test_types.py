"""Generating the composite return types (build_return_type_pkg.sql, create_generated_types.sql)."""

from helpers import USER_ACCOUNT_JSON, compile_schema, scalar, schema_id


def attributes(db, type_name):
    """(name, type) of each attribute of a composite type."""
    return db.execute(
        """select attname::text, format_type(atttypid, atttypmod) from pg_attribute
            where attrelid = %s::regclass and attnum > 0 order by attnum""",
        (type_name,),
    ).fetchall()


def test_generate_types_creates_child_types_before_their_parent(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    ddl = scalar(db, "select norm_gen.generate_types('user_account')")
    account = ddl.index("create type norm_small.acct_account_record as (")
    assert ddl.index("create type norm_small.acct_email_record as (") < account
    assert ddl.index("create type norm_small.acct_phone_record as (") < account


def test_build_return_type_covers_only_the_requested_subtree(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    ddl = scalar(db, "select norm_gen.build_return_type(%s, 'phone')", (schema_id(db, "user_account"),))
    assert "acct_phone_record" in ddl
    assert "acct_account_record" not in ddl


def test_generate_types_returns_null_for_an_unknown_schema(db):
    assert scalar(db, "select norm_gen.generate_types('no_such_schema')") is None


def test_create_generated_types_creates_the_record_types(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    assert scalar(db, "select norm_gen.create_generated_types('user_account')") == "user_account"
    assert attributes(db, "norm_small.acct_account_record") == [
        ("account_id", "bigint"),
        ("username", "text"),
        ("last_name", "text"),
        ("first_name", "text"),
        ("dob", "date"),
        ("emails", "norm_small.acct_email_record[]"),
        ("phones", "norm_small.acct_phone_record[]"),
    ]


def test_object_and_expression_keys_get_their_types(db, shop):
    assert dict(attributes(db, "norm_shop.shop_order_rec"))["totals"] == "norm_shop.shop_totals_rec"
    assert dict(attributes(db, "norm_shop.shop_customer_rec"))["name_upper"] == "text"
    assert attributes(db, "norm_shop.shop_totals_rec") == [("line_count", "bigint"), ("total_qty", "bigint")]
