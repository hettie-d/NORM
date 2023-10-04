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

