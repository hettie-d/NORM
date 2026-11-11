"""Parsing transfer schemas into the norm_gen metatables (process_schema_pkg.sql, ts_all.sql)."""

import psycopg
import pytest
from psycopg.rows import dict_row
from psycopg.types.json import Json

from helpers import SHOP_JSON, USER_ACCOUNT_JSON, compile_schema, load_schema, scalar, schema_id


def save(db, schema, delete=False):
    """Run norm_gen.save_transfer_schema and return the saved row."""
    new_id = scalar(db, "select norm_gen.save_transfer_schema(%s, %s)", (Json(schema), delete))
    return (
        db.cursor(row_factory=dict_row)
        .execute("select * from norm_gen.transfer_schema where transfer_schema_id = %s", (new_id,))
        .fetchone()
    )


def objects(db, title):
    """A compiled schema's objects, by name."""
    rows = db.cursor(row_factory=dict_row).execute(
        """select o.* from norm_gen.transfer_schema_object o
             join norm_gen.transfer_schema s using (transfer_schema_id)
            where s.transfer_schema_name = %s""",
        (title,),
    )
    return {row["t_object"]: row for row in rows}


def keys(db, title, t_object):
    """One object's keys, by name, in key_position order."""
    rows = db.cursor(row_factory=dict_row).execute(
        """select k.* from norm_gen.transfer_schema_key k
             join norm_gen.transfer_schema_object o using (transfer_schema_object_id)
             join norm_gen.transfer_schema s using (transfer_schema_id)
            where s.transfer_schema_name = %s and o.t_object = %s
            order by k.key_position""",
        (title, t_object),
    )
    return {row["t_key_name"]: row for row in rows}


def test_ts_all_returns_the_schema_id_and_no_errors(db):
    message = compile_schema(db, USER_ACCOUNT_JSON)
    assert message.split() == [f"transfer_schema_id:{schema_id(db, 'user_account')}"]


def test_ts_all_replaces_a_schema_with_the_same_title(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    old_id = schema_id(db, "user_account")
    compile_schema(db, USER_ACCOUNT_JSON)
    assert schema_id(db, "user_account") != old_id
    assert (
        scalar(
            db,
            "select count(*) from norm_gen.transfer_schema_object where transfer_schema_id = %s",
            (old_id,),
        )
        == 0
    )


def test_save_transfer_schema_stores_the_top_level_mapping(db):
    row = save(db, load_schema(USER_ACCOUNT_JSON))
    assert row["transfer_schema_name"] == "user_account"
    assert row["transfer_schema_description"] == "all account details with DB mappings"
    assert row["transfer_schema_root_object"] == "account"
    assert (row["db_schema"], row["db_prefix"], row["norm_schema"]) == ("norm_small", "acct", "norm_small")


@pytest.mark.parametrize(
    "mapping, prefix, norm_schema",
    [
        ({"db_schema": "app"}, "t", "app"),  # defaults: the title and db_schema
        ({"db_schema": "app", "db_prefix": "pfx", "norm_schema": "api"}, "pfx", "api"),
    ],
)
def test_save_transfer_schema_prefix_and_norm_schema(db, mapping, prefix, norm_schema):
    row = save(db, {"title": "t", "items": {"$ref": "#/definitions/x"}, "db_mapping": mapping})
    assert (row["db_prefix"], row["norm_schema"]) == (prefix, norm_schema)


def test_save_transfer_schema_replaces_a_title_only_when_deleting(db):
    schema = load_schema(USER_ACCOUNT_JSON)
    save(db, schema)
    with pytest.raises(psycopg.errors.UniqueViolation), db.transaction():
        save(db, schema)
    save(db, schema, delete=True)


def test_objects_are_saved_with_their_mapping(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    objs = objects(db, "user_account")
    assert set(objs) == {"account", "email", "phone"}

    account, email = objs["account"], objs["email"]
    assert (account["db_table"], account["db_pk_col"], account["db_expression"]) == (
        "account",
        "account_id",
        "N",
    )
    assert (account["db_parent_fk_col"], account["t_parent_object"], account["link"]) == (None, None, None)
    assert (email["db_parent_fk_col"], email["t_parent_object"]) == ("account_id", "account")
    # An embedded lookup defaults to the object's schema and db_expression 'N'.
    assert email["link"] == '{"(ep,norm_small,email_priority,N,email_priority_id,email_priority_id)"}'


def test_embedded_lookups_can_set_schema_and_expression(db):
    schema = load_schema(USER_ACCOUNT_JSON)
    schema["definitions"]["phone"]["db_mapping"]["embedded"][0].update(
        {"db_schema": "lookups", "db_expression": "Y"}
    )
    compile_schema(db, schema)
    phone = objects(db, "user_account")["phone"]
    assert phone["link"] == '{"(pt,lookups,phone_type,Y,phone_type_id,phone_type_id)"}'


def test_keys_are_saved_with_their_mapping(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    email = keys(db, "user_account", "email")
    assert list(email) == ["email_address", "email_id", "email_priority", "email_priority_id"]
    # db_col overrides the key name; without a db_type the column's own type is used.
    assert (email["email_address"]["db_col"], email["email_address"]["db_type"]) == (
        "email",
        "norm_small.email.email%type",
    )
    # A key read through an embedded alias takes its table from the alias.
    assert email["email_priority"]["db_table"] == "email_priority"

    phones = keys(db, "user_account", "account")["phones"]
    assert (phones["t_key_type"], phones["ref_object"]) == ("array", "phone")
    assert phones["ref_object_id"] == objects(db, "user_account")["phone"]["transfer_schema_object_id"]
    assert phones["db_type_calc"] == "norm_small.acct_phone_record[]"


def test_object_keys_get_the_record_type(db):
    compile_schema(db, SHOP_JSON)
    product = keys(db, "shop", "line")["product"]
    assert (product["t_key_type"], product["ref_object"]) == ("object", "product")
    assert product["db_type_calc"] == "norm_shop.shop_product_rec"


def test_update_db_type_reads_column_types_from_the_catalog(db):
    compile_schema(db, SHOP_JSON)
    customer = keys(db, "shop", "customer")
    assert customer["customer_id"]["db_type_calc"] == "int4"
    assert customer["joined"]["db_type_calc"] == "date"
    assert customer["tier"]["db_type_calc"] == "text"  # from the embedded tier table
    # An expression is not a table column, so its declared db_type is used.
    assert (customer["name_upper"]["db_type_calc"], customer["name_upper"]["db_type"]) == (None, "text")


BROKEN = {
    "title": "broken",
    "items": {"$ref": "#/definitions/missing_root"},
    "db_mapping": {"db_schema": "norm_shop", "db_prefix": "brk"},
    "definitions": {
        "a": {
            "db_mapping": {"db_table": "customer", "pk_col": "customer_id", "record_type": "a_rec"},
            "properties": {
                "customer_id": {"type": "number"},
                "no_such_column": {"type": "string"},
                "kids": {"type": "array", "items": {"$ref": "#/definitions/ghost"}},
            },
        },
        "b": {
            "db_mapping": {"db_table": "no_such_table", "pk_col": "x", "record_type": "b_rec"},
            "properties": {"x": {"type": "number"}},
        },
        "c": {
            "db_mapping": {
                "db_schema": "no_such_schema",
                "db_table": "t",
                "pk_col": "x",
                "record_type": "c_rec",
            },
            "properties": {"x": {"type": "number"}},
        },
    },
}


def test_ts_all_reports_every_kind_of_mapping_error(db):
    message = compile_schema(db, BROKEN)
    errors = sorted(line.strip(" ,") for line in message.split("\n")[1:] if line.strip())
    assert errors == [
        "Column in a/no_such_column: norm_shop.customer.no_such_column does not exist",
        "Invalid link in a/kids: ghost",
        "Invalid ref to root object:missing_root",
        "Orphan: a",
        "Orphan: b",
        "Orphan: c",
        "Schema: no_such_schema does not exist",
        "Table in b: norm_shop.no_such_table does not exist",
    ]


def test_transfer_schema_xref_lists_only_schemas_with_errors(db):
    compile_schema(db, USER_ACCOUNT_JSON)
    compile_schema(db, BROKEN)
    rows = db.execute("select transfer_schema_id from norm_gen.transfer_schema_xref()").fetchall()
    assert rows == [(schema_id(db, "broken"),)]
