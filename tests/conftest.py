"""Test harness: a throwaway PostgreSQL server with NORM loaded.

The server comes from the pgserver package, which ships PostgreSQL as a Python
wheel. Set NORM_TEST_DSN to a libpq connection string to use an existing server
instead; the suite creates a database named norm_test there and drops it after.
"""

import os
import tempfile

import psycopg
import pytest
from psycopg.conninfo import make_conninfo

from helpers import DATA_DIR, ROOT, SHOP_JSON, USER_ACCOUNT_JSON, compile_schema, generate_all
from sqlcov import Instrumenter

APP_SCHEMAS = [ROOT / "small_example" / "create_and_initialize_tables.sql", DATA_DIR / "shop.sql"]


def pytest_addoption(parser):
    parser.addoption("--sql-cov", action="store_true", help="measure coverage of norm_gen")
    parser.addoption(
        "--sql-cov-fail-under",
        type=float,
        default=90,
        metavar="PCT",
        help="with --sql-cov, fail if total coverage is below PCT (default: 90)",
    )


def norm_sources():
    """(file name, SQL) pairs, in the order sql/_load_all.sql runs them."""
    for line in (ROOT / "sql" / "_load_all.sql").read_text().splitlines():
        if line.startswith("\\ir"):
            name = "sql/" + line.split()[1].rstrip(";")
            yield name, (ROOT / name).read_text()
        elif line.strip():
            yield "sql/_load_all.sql", line


@pytest.fixture(scope="session")
def pg_server():
    if "NORM_TEST_DSN" in os.environ:
        yield os.environ["NORM_TEST_DSN"]
        return
    import pgserver

    server = pgserver.get_server(tempfile.mkdtemp(prefix="norm-test-"), cleanup_mode="delete")
    yield server.get_uri()
    server.cleanup()


@pytest.fixture(scope="session")
def norm_db(request, pg_server):
    """Connection string of a fresh database with NORM and the app schemas loaded."""
    with psycopg.connect(pg_server, autocommit=True) as conn:
        conn.execute("drop database if exists norm_test with (force)")
        conn.execute("create database norm_test")
    dsn = make_conninfo(pg_server, dbname="norm_test")

    sources = list(norm_sources())
    cov = Instrumenter() if request.config.getoption("sql_cov") else None
    if cov:
        sources = [(name, cov.instrument(sql, name)) for name, sql in sources]
    with psycopg.connect(dsn, autocommit=True) as conn:
        if cov:
            conn.execute(cov.setup_sql())
        for _, sql in sources:
            conn.execute(sql)
        for path in APP_SCHEMAS:
            conn.execute(path.read_text())

    yield dsn

    if cov:
        with psycopg.connect(dsn) as conn:
            request.config.sql_cov = cov.report(cov.hits(conn))
    with psycopg.connect(pg_server, autocommit=True) as conn:
        conn.execute("drop database norm_test with (force)")


@pytest.fixture
def db(norm_db):
    """A connection to the test database. Everything a test does is rolled back."""
    conn = psycopg.connect(norm_db, options="-c timezone=UTC")
    yield conn
    conn.rollback()
    conn.close()


@pytest.fixture
def user_account(db):
    """small_example's user_account hierarchy (prefix acct), compiled and generated."""
    compile_schema(db, USER_ACCOUNT_JSON)
    generate_all(db, "user_account")


@pytest.fixture
def shop(db):
    """The three-level hierarchy in data/shop.json (prefix shop), compiled and generated."""
    compile_schema(db, SHOP_JSON)
    generate_all(db, "shop")


def pytest_sessionfinish(session):
    if hasattr(session.config, "sql_cov"):
        percent, _ = session.config.sql_cov
        if percent < session.config.getoption("sql_cov_fail_under"):
            session.exitstatus = pytest.ExitCode.TESTS_FAILED


def pytest_terminal_summary(terminalreporter, exitstatus, config):
    coverage = getattr(config, "sql_cov", None)
    minimum = config.getoption("sql_cov_fail_under")
    if coverage:
        percent, table = coverage
        terminalreporter.section("NORM SQL coverage: statements and CASE branches")
        terminalreporter.write_line(table)
        if percent < minimum:
            terminalreporter.write_line(f"FAIL: coverage is below {minimum:g}%", red=True)
    if "GITHUB_STEP_SUMMARY" in os.environ:
        github_summary(terminalreporter.stats, exitstatus == 0, coverage, minimum)


def github_summary(stats, passed, coverage, minimum):
    """Show the results on the GitHub Actions run page, and pass a one-line summary to later steps."""
    outcomes = ("passed", "failed", "error", "xfailed", "xpassed", "skipped")
    summary = ", ".join(f"{len(stats[o])} {o}" for o in outcomes if stats.get(o))
    details = []
    if coverage:
        percent, table = coverage
        passed = passed and percent >= minimum
        summary += f", {percent:.1f}% coverage"
        details = ["<details><summary>Coverage by function</summary>", "", "```", table, "```", "</details>"]
    title = "Tests with coverage" if coverage else "Tests"
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
        f.write("\n".join([f"### {'✅' if passed else '❌'} {title}: {summary}", "", *details, "", ""]))
    with open(os.environ["GITHUB_OUTPUT"], "a") as f:
        f.write(f"summary={summary}\n")
