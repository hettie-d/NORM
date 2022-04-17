# What is NORM_GEN?
 
NORM_GEN will assist in automating the  process of building NORM functions.

We are presenting a contract as a JSON schema, then parse it and store the results in meta tables, and then build the tyoes and functions.

## Quick Start

To use NORM_GEN, run the file 
\_load\_all\_norm\_gen.sql from this directory on your local Postgres dtabase
It will create a NORM|_GEN schema with meta data tables and deploy two packges:

process_schema
build_conditions

It addition, it will create a function ts_all which runs all of the above functions and returns the transfer_schema_id of the new schema.

An example which processes a JSON schema for account can be found in the 

ts\_all\_call.sql
