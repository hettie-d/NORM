# What is NORM?
 
 NORM stands for No ORM framework.
 
 NORM is a methodology which allows object-oriented applications to interact with relational databases
 directly, without involving any ORM. 
 
 This methodology was developed by [Hettie Dombrovskaya](https://github.com/hettie-d) and [Boris Novikov](https://github.com/bn1206). While a completely automated version was never implemented in any production environment, it's manual version (using functions instead of ORM) was implemented at Braviant Holdings.

## What's in the repo?

This repo contains a set of packages that can be used to automate the process of building NORM functions.

The contract between an applicarion and a database is presented in the form of JSON schema, which is then parsed and the results are stored in metatables. This information is later used to build Postgres types and functions.


 
 ##  TOC:
 
 * The documentation directory contains: NORM user Guide (HTML and pdf format)
 * The presentation directory contains ppt of the  presentation from SOFSEM 2020 conference, where NORM was first officially announced, and a presentation from Swiss PG Day 2022 when the automated funcitons generation was introduced.
 * The sql directory contains a source code for the generator
 * The examples diectory contains examples of JSON schemas which can be used as input for NORM. All schemas are based on postges_air database.
 * obsolete-example directory contains an example which was used in the earlie NOM presentations.

## Quick Start

To use NORM, run the file 

\_load\_all.sql from the sql directory on your local Postgres database

It will create a NORM schema with metadata tables and deploy the following packages:

process_schema

build_conditions

build_return_type

build_select

build_to_db

generate_select_by_ids

generate_search_generic

generate_to_db_function


In addition, it will create a function ts_all which runs all functions from the process_schema package and populates all metadata.

After that, we are ready to generate all PostgeSQL functions which will be called from the application.

For details, consult the [User Guide](documentation/norm-ug.html) 

Examples of json schemas and funcitons generators can be found in the [Examples](examples) folder.