"""Tests for the coverage instrumenter in sqlcov.py."""

import pytest

from sqlcov import Instrumenter

SOURCE = """\
create schema cov_demo;

create function cov_demo.grade(n int) returns text language sql as $$
select case when n >= 90 then 'A' when n >= 80 then 'B' else 'C' end;
$$;

create function cov_demo.kind(k text) returns text language sql
begin atomic
  select case k when 'a' then 'apple' when 'b' then 'banana' end;
end;

create function cov_demo.walk(n int) returns int language plpgsql as $body$
declare total int := 0;
begin
  for i in 1..n loop
    if i % 2 = 0 then
      total := total + i;
    else
      total := total - 1;
    end if;
  end loop;
  return 100 / total;
exception when division_by_zero then
  return -1;
end $body$;
"""


@pytest.fixture
def cov(db):
    """An instrumenter with SOURCE instrumented and loaded."""
    cov = Instrumenter(schemas=("cov_demo",), probe_schema="cov_selftest")
    text = cov.instrument(SOURCE, "demo.sql")
    db.execute(cov.setup_sql())
    db.execute(text)
    return cov


def probes(cov, ids=None):
    """(function, kind, line, label) of each probe, or only of those in `ids`."""
    return [
        (fn.name, p.kind, p.line, p.label)
        for fn in cov.functions.values()
        for p in fn.probes
        if ids is None or p.id in ids
    ]


def test_probes_are_placed_on_statements_and_case_arms(cov):
    assert probes(cov) == [
        ("cov_demo.grade", "statement", 4, ""),
        ("cov_demo.grade", "branch", 4, "when n >= 90"),
        ("cov_demo.grade", "branch", 4, "when n >= 80"),
        ("cov_demo.grade", "branch", 4, "else"),
        ("cov_demo.kind", "statement", 9, ""),
        ("cov_demo.kind", "branch", 9, "when k = 'a'"),
        ("cov_demo.kind", "branch", 9, "when k = 'b'"),
        ("cov_demo.walk", "statement", 15, ""),
        ("cov_demo.walk", "statement", 16, ""),
        ("cov_demo.walk", "statement", 17, ""),
        ("cov_demo.walk", "statement", 19, ""),
        ("cov_demo.walk", "statement", 22, ""),
        ("cov_demo.walk", "statement", 24, ""),
    ]


def test_probes_keep_line_numbers():
    cov = Instrumenter(schemas=("cov_demo",))
    lines = cov.instrument(SOURCE, "demo.sql").split("\n")
    assert len(lines) == len(SOURCE.split("\n"))
    for fn in cov.functions.values():
        for p in fn.probes:
            assert f"hit({p.id}" in lines[p.line - 1]


def test_instrumented_functions_return_the_same_results(db, cov):
    def results(sql, args):
        return [db.execute(sql % arg).fetchone()[0] for arg in args]

    assert results("select cov_demo.grade(%s)", [95, 85, 10, "null"]) == ["A", "B", "C", "C"]
    assert results("select cov_demo.kind(%s)", ["'a'", "'b'", "'z'", "null"]) == [
        "apple",
        "banana",
        None,
        None,
    ]
    # walk(4) = 100 / (-1 + 2 - 1 + 4); walk(2) = 100 / (-1 + 2); walk(0) divides by zero.
    assert results("select cov_demo.walk(%s)", [4, 2, 0]) == [25, 100, -1]


def test_hits_are_recorded_per_probe(db, cov):
    db.execute("select cov_demo.grade(95), cov_demo.kind('z'), cov_demo.walk(1)")
    assert probes(cov, cov.hits(db)) == [
        ("cov_demo.grade", "statement", 4, ""),
        ("cov_demo.grade", "branch", 4, "when n >= 90"),
        ("cov_demo.kind", "statement", 9, ""),
        ("cov_demo.walk", "statement", 15, ""),
        ("cov_demo.walk", "statement", 16, ""),
        ("cov_demo.walk", "statement", 19, ""),
        ("cov_demo.walk", "statement", 22, ""),
    ]


def test_hits_survive_a_rollback(db, cov):
    db.execute("savepoint s")
    db.execute("select cov_demo.grade(85)")
    db.execute("rollback to savepoint s")
    assert ("cov_demo.grade", "branch", 4, "when n >= 80") in probes(cov, cov.hits(db))


def test_report(db, cov):
    db.execute("select cov_demo.grade(95), cov_demo.kind('z'), cov_demo.walk(1)")
    percent, table = cov.report(cov.hits(db))
    assert round(percent, 1) == 53.8  # 7 of 13 probes
    assert "9 (when k = 'a'), 9 (when k = 'b')" in table
    assert table.splitlines()[-1].split() == ["TOTAL", "8", "5", "6", "53.8%"]


def test_a_redefined_function_is_counted_once():
    cov = Instrumenter(schemas=("cov_demo",))
    cov.instrument(SOURCE, "first.sql")
    cov.instrument(SOURCE, "second.sql")
    assert {fn.file for fn in cov.functions.values()} == {"second.sql"}
