# What is NORM?
 
 NORM stands for No ORM framework.
 
 NORM is a methodology which allows object-oriented applications to interact with relational databases
 directly, without involving any ORM. 
 
 This methodology was developed by [Hettie Dombrovskaya](https://github.com/hettie-d) and [Boris Novikov](https://github.com/bn1206) and was fully implemented at Braviant Holidings, Chicago IL.


## What's in the repo?

This repo contains a set of packages that can be used to automate the process of building NORM functions.

To automate this process, we need to present a contract more formally. We present a contract as a JSON schema, then parse it and store the results in meta tables, later used to build the types and functions.


 
 ##  TOC:
 
 * The documentation directory contains: 
 * The presentation directory contains ppt of the  presentation from SOFSEM 2020 conference, where NORM was first officially announced.Take a look to find out why NORM was developed, and what are the advantages of this approach.
 * The sql directory contains a source code for the generator
 

## Quick Start

To use NORM, run the file 

\_load\_all\_norm\_gen.sql from this directory on your local Postgres database

It will create a NORM_GEN schema with metadata tables and deploy the following packages:
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

For details, consult the [User Guide](documentation/NORM-ug.html) 

Examples of json schemas and funcitons generators can be found in the [Examples](examples) folder.