# What is NORM?
 
 NORM stands for No ORM framework.
 
 NORM is a methodology which allows object-oriented applications to interact with relational databases
 directly, without involving any ORM. 
 
 This methodology was developed by [Hettie Dombrovskaya](https://github.com/hettie-d) and [Boris Novikov](https://github.com/bn1206). While a completely automated version was never implemented in any production environment, it's manual version (using functions instead of ORM) was implemented at Braviant Holdings.

## What's in the repo?

This repo contains a set of packages that can be used to automate the process of building NORM functions.

The contract between an application and a database is presented in the form of JSON schema, which is then parsed and the results are stored in metatables. This information is later used to build Postgres types and functions.


 
 ##  TOC:
 
 * The documentation directory contains NORM user Guide in pdf format
 * The presentation directory contains ppt of the  presentation from SOFSEM 2020 conference, where NORM was first officially announced, and a presentation from Swiss PG Day 2022 when the automated funcitons generation was introduced.
 * The sql directory contains a source code for the generator
 * The examples directory contains examples of JSON schemas which can be used as input for NORM. All schemas are based on postges_air database and psql script that runs these examples.
 * small-example directory contains an example which was used in the earlie NOM presentations. It uses tiny amounts of data making it easy to check how NORM works.
 * The tests directory contains the test suite, see [Running the tests](#running-the-tests).

## Quick Start

To use NORM, run the file 

\_load\_all.sql from the sql directory on your local Postgres database

It will create a NORM schema with metadata tables and functions.

After that, we are ready to generate all PostgeSQL functions which will be called from the application. Specifically, we need:

- a set of functions performing data modification, and
- a set of PostgreSQL type definitions.

Both sets should be created in the database for each hierarchy.

When this is done, you can use generate_search_generic function to generate and execute dynamic SQL that extracts data based on the search conditions. Alternatively, lower-level functions build_select  and build_conditions create parts of SQL statements that can be used to handcraft more complex queries. 

Examples of json schemas and funcitons generators can be found in the [Examples](examples) folder. These examples are based on the Postgres_air database, however, neither Postgres_air database is a part of NORM nor NORM is a part of Postgres_air. 

The file examples/run_examples.sql demonstrates how to process JSON schemas and generate functions to be invoked from the application.

For details, consult the [User Guide](documentation/norm-ug.pdf) 

Please be advised that [Small example](small_example) is still a work in progress. The intention is to show an example that does not require postgres_air database installation and to demonstrate the differences (and similarities) between manually written and generated functions. 

## Running the tests

The tests use [pytest](https://pytest.org) and only need [uv](https://docs.astral.sh/uv/getting-started/installation/). Each run starts a throwaway PostgreSQL 16 server from the [pgserver](https://pypi.org/project/pgserver/) package, so you don't need Docker or a local Postgres install. From the repository root:

```sh
uv run pytest                                # run all tests
uv run pytest --sql-cov                      # also measure coverage; fails below 90%
uv run pytest tests/test_to_db.py -k delete  # run a subset
```

To use an existing server instead, set `NORM_TEST_DSN` to a connection string for a user that can create databases. The tests create a database named `norm_test` there and drop it when they finish:

```sh
NORM_TEST_DSN="postgresql://postgres@localhost:5432/postgres" uv run pytest
```

GitHub Actions runs the tests, with and without `--sql-cov`, on every pull request and every push to `master` (see `.github/workflows/tests.yml`). The results appear at the top of the workflow run page, and as a "Test results" status on the commit and the pull request.

**Coverage.** `--sql-cov` reports how many statements and `CASE` branches (each `WHEN` and `ELSE`) of every `norm_gen` function the tests ran. `plpgsql_check` only covers PL/pgSQL, and most of NORM is `LANGUAGE sql`, so `tests/sqlcov.py` adds probes to the source as it is loaded. Change the threshold with `--sql-cov-fail-under`. The functions NORM generates at runtime come from string templates, so they aren't counted; the tests check their behaviour instead.

**Known bugs.** Tests marked `xfail` describe behaviour that is broken today. They are strict: when a fix makes one pass, the run fails until its marker is removed.
