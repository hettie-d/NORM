"""Schema <-> table helpers (helpers_pkg.sql)."""

import pytest

from helpers import compile_schema, generate_all, scalar, to_json

GADGET_DDL = """
create table norm_shop.gadget (
    gadget_id int primary key,
    label varchar(20),
    price numeric(8, 2),
    active boolean,
    note text,
    weight double precision,
    stock bigint
)"""


def one_table_schema(title, db_schema, table, properties):
    """A transfer schema with a single object, mapped to `table`."""
    return {
        "title": title,
        "items": {"$ref": f"#/definitions/{table}"},
        "db_mapping": {"db_schema": db_schema},
        "definitions": {
            table: {
                "db_mapping": {"db_table": table, "pk_col": f"{table}_id", "record_type": "rec"},
                "properties": properties,
            }
        },
    }


def columns(db, schema, table):
    """{column: data type} of a table."""
    return dict(
        db.execute(
            """select column_name::text, data_type::text from information_schema.columns
                where table_schema = %s and table_name = %s""",
            (schema, table),
        ).fetchall()
    )


def test_table_to_transfer_schema(db):
    db.execute(GADGET_DDL)
    schema = scalar(db, "select norm_gen.table_to_transfer_schema('norm_shop', 'gadget')")
    assert (schema["title"], schema["items"]) == ("gadget", {"$ref": "#/definitions/gadget"})
    assert schema["db_mapping"] == {"db_schema": "norm_shop", "db_prefix": "gadget"}
    gadget = schema["definitions"]["gadget"]
    assert gadget["db_mapping"] == {"db_table": "gadget", "pk_col": "gadget_id", "record_type": "gadget_row"}
    assert {key: (p["type"], p["db_mapping"]["db_type"]) for key, p in gadget["properties"].items()} == {
        "gadget_id": ("number", "integer"),
        "label": ("string", "character varying(20)"),
        "price": ("number", "numeric(8,2)"),
        "active": ("boolean", "boolean"),
        "note": ("string", "text"),
        "weight": ("number", "double precision"),
        "stock": ("number", "bigint"),
    }


def test_table_to_transfer_schema_title_and_missing_primary_key(db):
    db.execute("create table norm_shop.no_pk (a text)")
    schema = scalar(db, "select norm_gen.table_to_transfer_schema('norm_shop', 'no_pk', 'custom')")
    assert schema["title"] == "custom"
    assert schema["definitions"]["no_pk"]["db_mapping"]["pk_col"] == "UNKNOWN"


def test_table_to_transfer_schema_output_compiles_and_works(db):
    db.execute(GADGET_DDL)
    db.execute("insert into norm_shop.gadget values (7, 'lamp', 9.99, true, 'desk', 1.5, 3)")
    schema = scalar(db, "select norm_gen.table_to_transfer_schema('norm_shop', 'gadget')")
    assert compile_schema(db, schema).split()[1:] == []  # no mapping errors
    generate_all(db, "gadget")
    assert to_json(db, "select norm_shop.gadget_select_by_ids(array[7])") == [
        {
            "gadget_id": 7,
            "label": "lamp",
            "price": 9.99,
            "active": True,
            "note": "desk",
            "weight": 1.5,
            "stock": 3,
        }
    ]


AUTHOR = one_table_schema(
    "draft", "norm_draft", "author", {"author_id": {"type": "number"}, "name": {"type": "string"}}
)


def test_transfer_schema_to_table(db):
    compile_schema(db, AUTHOR)
    table_def = scalar(
        db, "select table_def from norm_gen.transfer_schema_to_table() where schema_title = 'draft'"
    )
    db.execute("create schema norm_draft")
    db.execute(table_def)
    assert columns(db, "norm_draft", "author") == {"author_id": "numeric", "name": "text"}


@pytest.mark.xfail(strict=True, reason="pk_constraint omits the parentheses around the column list")
def test_transfer_schema_to_table_primary_key(db):
    compile_schema(db, AUTHOR)
    table_def, pk_constraint = db.execute(
        "select table_def, pk_constraint from norm_gen.transfer_schema_to_table() where schema_title = 'draft'"
    ).fetchone()
    db.execute("create schema norm_draft")
    db.execute(table_def)
    db.execute(pk_constraint)


def test_transfer_schema_alter_table_exec_adds_missing_columns(db):
    properties = {
        "product_id": {"type": "number"},
        "weight": {"type": "number"},
        "launched": {"type": "string", "format": "date"},
        "updated": {"type": "string", "format": "date-time"},
        "sku": {"type": "string"},
        "active": {"type": "boolean"},
    }
    compile_schema(db, one_table_schema("product_v2", "norm_shop", "product", properties))
    sql = scalar(db, "select norm_gen.transfer_schema_alter_table_exec('product_v2')")
    assert sql.startswith("alter table norm_shop.product add column ")
    assert columns(db, "norm_shop", "product") == {
        "product_id": "integer",
        "product_name": "text",
        "unit_price": "numeric",
        "weight": "numeric",
        "launched": "timestamp with time zone",
        "updated": "timestamp with time zone",
        "sku": "text",
        "active": "boolean",
    }


def test_transfer_schema_drop_column_exec_drops_unmapped_columns(db):
    properties = {"product_id": {"type": "number"}, "product_name": {"type": "string"}}
    compile_schema(db, one_table_schema("product_slim", "norm_shop", "product", properties))
    sql = scalar(db, "select norm_gen.transfer_schema_drop_column_exec('product_slim')")
    assert sql.split() == ["alter", "table", "norm_shop.product", "drop", "column", "unit_price;"]
    assert columns(db, "norm_shop", "product") == {"product_id": "integer", "product_name": "text"}
