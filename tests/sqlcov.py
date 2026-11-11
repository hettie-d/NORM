"""Statement and branch coverage for the norm_gen functions.

PostgreSQL has no built-in coverage, and plpgsql_check only measures PL/pgSQL,
while most of NORM is LANGUAGE sql. So the source is rewritten before it is
loaded, adding a probe to:

* every statement:  ``stmt;``              ->  ``perform norm_cov.hit(N); stmt;``
                                               (``select ...`` in SQL functions)
* every CASE arm:   ``WHEN c THEN``        ->  ``WHEN norm_cov.hit(N, (c)) THEN``
                    ``CASE x WHEN v THEN`` ->  ``CASE WHEN norm_cov.hit(N, (x) = (v)) THEN``
                    ``ELSE``               ->  ``WHEN norm_cov.hit(N) THEN``

Probes don't add lines, so line numbers stay correct. Each probe counts its
hits in a sequence; sequences aren't transactional, so hits survive the
rollback at the end of each test.
"""

from __future__ import annotations

import bisect
import json
import re
from collections import defaultdict
from dataclasses import dataclass, field

from pglast import parser

# A PL/pgSQL statement starts right after one of these tokens.
STATEMENT_BOUNDARIES = {";", "begin", "then", "else", "loop"}


@dataclass
class Probe:
    id: int
    line: int
    kind: str  # "statement" or "branch"
    label: str = ""


@dataclass
class Function:
    name: str
    file: str
    line: int
    probes: list[Probe] = field(default_factory=list)


def _scan(src):
    """SQL tokens of `src`, without comments."""
    return [t for t in parser.scan(src) if not t.name.endswith("_COMMENT")]


def _text(src, token):
    return src[token.start : token.end + 1]


def _snippet(text, width=40):
    text = " ".join(text.split())
    return text if len(text) <= width else text[: width - 3] + "..."


class Instrumenter:
    def __init__(self, schemas=("norm_gen",), probe_schema="norm_cov"):
        self.schemas = set(schemas)
        self.probe_schema = probe_schema
        # Keyed by name, so a later definition replaces an earlier one.
        self.functions: dict[str, Function] = {}
        self.probe_count = 0

    def setup_sql(self) -> str:
        """SQL creating the probe function and one sequence per probe."""
        s = self.probe_schema
        sequences = "".join(f"create sequence {s}.p{i};\n" for i in range(1, self.probe_count + 1))
        return f"""
            drop schema if exists {s} cascade;
            create schema {s};
            create function {s}.hit(p_id int, p_cond boolean default true) returns boolean
            language plpgsql as $$
            begin
                if p_cond then
                    perform nextval(format('{s}.p%s', p_id));
                end if;
                return p_cond;
            end $$;
            {sequences}"""

    def hits(self, conn) -> set[int]:
        """Ids of the probes that ran."""
        rows = conn.execute(
            "select sequencename from pg_sequences where schemaname = %s and last_value is not null",
            (self.probe_schema,),
        )
        return {int(name[1:]) for (name,) in rows}

    def instrument(self, text: str, file: str) -> str:
        """Return ``text`` with probes added to the functions it defines."""
        self._file = file
        self._line_starts = [0] + [m.end() for m in re.finditer("\n", text)]
        self._edits = []  # (start, end, replacement)
        for sl in parser.split(text, with_parser=True, only_slices=True):
            node = json.loads(parser.parse_sql_json(text[sl]))["stmts"][0]["stmt"]
            node = node.get("CreateFunctionStmt")
            if node and node["funcname"][0]["String"]["sval"] in self.schemas:
                self._function(text[sl], sl.start, node)

        out, pos = [], 0
        for start, end, new in sorted(self._edits, key=lambda e: e[0]):
            out += [text[pos:start], new]
            pos = end
        return "".join(out) + text[pos:]

    def _line(self, pos):
        return bisect.bisect_right(self._line_starts, pos)

    def _probe(self, fn, pos, kind, label=""):
        self.probe_count += 1
        fn.probes.append(Probe(self.probe_count, self._line(pos), kind, label))
        return self.probe_count

    def _function(self, stmt, offset, node):
        name = ".".join(n["String"]["sval"] for n in node["funcname"])
        fn = self.functions[name] = Function(name, self._file, self._line(offset))
        tokens = _scan(stmt)
        names = [t.name for t in tokens]

        if "sql_body" in node:  # BEGIN ATOMIC ... END
            end = len(names) - 1 - names[::-1].index("END_P")
            body = tokens[names.index("ATOMIC") + 1 : end]
            self._sql_statements(fn, body, offset)
            self._case_arms(fn, body, stmt, offset)
            return

        literal = tokens[names.index("AS") + 1]  # the dollar-quoted body
        literal_text = _text(stmt, literal)
        quote = literal_text[: literal_text.index("$", 1) + 1]
        src = literal_text[len(quote) : -len(quote)]
        offset += literal.start + len(quote)
        body = _scan(src)
        options = {o["DefElem"]["defname"]: o["DefElem"]["arg"] for o in node["options"]}
        if options["language"]["String"]["sval"].lower() == "plpgsql":
            self._plpgsql_statements(fn, node, literal_text, body, src, offset)
        else:
            self._sql_statements(fn, body, offset)
        self._case_arms(fn, body, src, offset)

    def _statement(self, fn, pos, verb):
        pid = self._probe(fn, pos, "statement")
        self._edits.append((pos, pos, f"{verb} {self.probe_schema}.hit({pid}); "))

    def _sql_statements(self, fn, body, offset):
        for prev, token in zip([None, *body], body):
            if prev is None or prev.name == "ASCII_59":  # first token, or after ";"
                self._statement(fn, offset + token.start, "select")

    def _plpgsql_statements(self, fn, node, literal, body, src, offset):
        # libpg_query's PL/pgSQL parser can't resolve schema-qualified types,
        # so parse the body under a header that only uses built-in types.
        params = ", ".join(p["FunctionParameter"]["name"] + " text" for p in node.get("parameters", []))
        returns = "setof record" if node["returnType"].get("setof") else "text"
        header = f"create function f({params}) returns {returns} language plpgsql as "
        tree = json.loads(parser.parse_plpgsql_json(header + literal))[0]["PLpgSQL_function"]

        def linenos(value):
            if isinstance(value, dict):
                for key, child in value.items():
                    if key.startswith("PLpgSQL_stmt_") and child.get("lineno"):
                        yield child["lineno"]
                    yield from linenos(child)
            elif isinstance(value, list):
                for child in value:
                    yield from linenos(child)

        # Tokens that can start a statement, grouped by line.
        starts = defaultdict(list)
        for prev, token in zip([None, *body], body):
            if prev is None or _text(src, prev).lower() in STATEMENT_BOUNDARIES:
                starts[self._line(offset + token.start)].append(token)

        first_line = self._line(offset)
        # The function's outer block is not a statement of its own.
        for lineno in linenos(tree["action"]["PLpgSQL_stmt_block"]):
            line = first_line + lineno - 1
            if not starts[line]:
                raise ValueError(f"{self._file}:{line}: cannot find where the statement starts")
            self._statement(fn, offset + starts[line].pop(0).start, "perform")

    def _case_arms(self, fn, body, src, offset):
        hit = f"{self.probe_schema}.hit"
        stack = []  # one [paren depth, operand, open WHEN token] per open CASE
        depth = 0
        for i, token in enumerate(body):
            if token.name == "ASCII_40":
                depth += 1
            elif token.name == "ASCII_41":
                depth -= 1
            elif token.name == "CASE" and (i == 0 or body[i - 1].name != "END_P"):  # not "END CASE"
                operand = None
                if body[i + 1].name != "WHEN":
                    # Simple CASE: move the operand into each WHEN as "(operand) = (value)".
                    j = next(j for j in range(i + 1, len(body)) if body[j].name == "WHEN")
                    if any(t.name == "CASE" for t in body[i + 1 : j]):
                        raise ValueError(f"{self._file}: CASE inside a CASE operand is not supported")
                    start, end = body[i + 1].start, body[j - 1].end + 1
                    operand = src[start:end]
                    self._edits.append((offset + start, offset + end, ""))
                stack.append([depth, operand, None])
            elif stack and stack[-1][0] == depth:
                case = stack[-1]
                if token.name == "WHEN":
                    case[2] = token
                elif token.name == "THEN" and case[2]:
                    when, operand = case[2], case[1]
                    value = src[when.end + 1 : token.start]
                    test = value if operand is None else f"{operand} = {value}"
                    pid = self._probe(fn, offset + when.start, "branch", "when " + _snippet(test))
                    prefix = "(" if operand is None else f"({operand}) = ("
                    self._edits.append(
                        (offset + when.end + 1, offset + when.end + 1, f" {hit}({pid}, {prefix}")
                    )
                    self._edits.append((offset + token.start, offset + token.start, ")) "))
                    case[2] = None
                elif token.name == "ELSE":
                    pid = self._probe(fn, offset + token.start, "branch", "else")
                    self._edits.append(
                        (offset + token.start, offset + token.end + 1, f"WHEN {hit}({pid}) THEN")
                    )
                elif token.name == "END_P":
                    stack.pop()

    def report(self, hits: set[int]) -> tuple[float, str]:
        """Total coverage percentage, and a table of coverage per function."""
        rows = []
        for fn in sorted(self.functions.values(), key=lambda f: (f.file, f.line)):
            missed = sorted((p for p in fn.probes if p.id not in hits), key=lambda p: p.line)
            rows.append(
                (
                    fn.name,
                    f"{fn.file}:{fn.line}",
                    sum(p.kind == "statement" for p in fn.probes),
                    sum(p.kind == "branch" for p in fn.probes),
                    len(missed),
                    f"{100 * (1 - len(missed) / len(fn.probes)):.0f}%",
                    ", ".join(f"{p.line} ({p.label})" if p.label else str(p.line) for p in missed),
                )
            )
        stmts, branches, missed = (sum(row[i] for row in rows) for i in (2, 3, 4))
        percent = 100 * (1 - missed / (stmts + branches))

        header = ("Function", "File", "Stmts", "Branches", "Miss", "Cover", "Missing")
        footer = ("TOTAL", "", stmts, branches, missed, f"{percent:.1f}%", "")
        name_width = max(len(row[0]) for row in [header, *rows])
        file_width = max(len(row[1]) for row in [header, *rows])
        fmt = f"{{:<{name_width}}}  {{:<{file_width}}}  {{:>5}}  {{:>8}}  {{:>4}}  {{:>6}}  {{}}"
        lines = [fmt.format(*row).rstrip() for row in [header, *rows, footer]]
        rule = "-" * len(lines[0])
        return percent, "\n".join([lines[0], rule, *lines[1:-1], rule, lines[-1]])
