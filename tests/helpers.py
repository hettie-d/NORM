"""Helpers shared by the tests."""

import json
from pathlib import Path

from psycopg.types.json import Json

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = ROOT / "tests" / "data"
USER_ACCOUNT_JSON = ROOT / "small_example" / "user_account.json"
SHOP_JSON = DATA_DIR / "shop.json"


def load_schema(path: Path) -> dict:
    return json.loads(path.read_text())


def scalar(db, sql, params=()):
    """The first column of the first row, or None if there are no rows."""
    row = db.execute(sql, params).fetchone()
    return row[0] if row else None


def column(db, sql, params=()) -> list:
    """The first column of every row."""
    return [row[0] for row in db.execute(sql, params)]


def to_json(db, sql, params=()):
    """The single value a query returns, converted to JSON."""
    return scalar(db, f"select to_json(x) from ({sql}) as q(x)", params)


def schema_id(db, title):
    return scalar(
        db,
        "select transfer_schema_id from norm_gen.transfer_schema where transfer_schema_name = %s",
        (title,),
    )


def compile_schema(db, schema: dict | Path) -> str:
    """Load a transfer schema into the metatables with norm_gen.ts_all."""
    if isinstance(schema, Path):
        schema = load_schema(schema)
    return scalar(db, "select norm_gen.ts_all(%s)", (Json(schema),))


def generate_all(db, title):
    """Create the types and every generated function for a compiled schema."""
    for generator in [
        "create_generated_types",
        "generate_select_by_id",
        "generate_from_db",
        "generate_to_db_function",
    ]:
        result = scalar(db, f"select norm_gen.{generator}(%s)", (title,))
        assert result and not result.startswith("ERROR"), f"{generator}: {result}"
