# What is NORM_GEN?
 
NORM_GEN is a set of packages which can be used to automate the  process of building NORM functions.

In order to automate this process we need to present a contract in a more formalized way. We are presenting a contract as a JSON schema, then parse it and store the results in meta tables, which are later used to build the types and functions.

## Quick Start

To use NORM_GEN, run the file 
\_load\_all\_norm\_gen.sql from this directory on your local Postgres database
It will create a NORM\_GEN schema with metadata tables and deploy the following packages:

process_schema

build_conditions

build_return_type

build_select

build_to_db



It addition, it will create a function ts_all which runs all functions from the process_schema package and populates all metadata.

## Demo

For demo, we use a JSON schema which describes a user account - see user\_account.json

This JSON schema describes the mapping of the User account transport object to the database. The database schema can be found in

../sql/create\_tables.sql

To see how NORM_GEN works, you can follow the steps listed in the 

ts\_all\_call.sql

More examples of JSON schemas can be found in:

flight-booking.json
flight-boarding.json
