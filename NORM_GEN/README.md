# What is NORM_GEN?
 
NORM_GEN is a set of packages which will be used to automate the  process of building NORM functions.

In order to automate this procee we need to present a contract in a more formalized way. We are presenting a contract as a JSON schema, then parse it and store the results in meta tables, which are later used to build the types and functions.

## Quick Start

To use NORM_GEN, run the file 
\_load\_all\_norm\_gen.sql from this directory on your local Postgres database
It will create a NORM\_GEN schema with metadata tables and deploy the following packages:

###process_schema
###build_conditions
###build_return_type
###build_select

It addition, it will create a function ts_all which runs all functions from the process_schema package and populates all metadata.

To run all funcitons for user account, execute:

ts\_all\_call.sql
