--- This script must be executed after 'create_and_initialize_tables.sql'
--- cd to the directory containing small example
\cd <your  directory containing small example>

set search_path to norm_small,norm_gen;

--- compile JSON schema
\set  p_schema `cat user_account.json`
select ts_all(:'p_schema'::json);

/* 
The names of all generated database objects (functions and types) have a prefix 'acct'specified in the schema.
*/ 
--- generate type definitions for SELECT clause
select 
   norm_gen.create_generated_types(transfer_schema_name)
from transfer_schema
where transfer_schema_name='user_account';

--- Generate NORM functions 
select 
   transfer_schema_name,
   norm_gen.generate_to_db_function(transfer_schema_name) to_db,
   norm_gen.generate_select_by_id(transfer_schema_name) select_by_ids,
   norm_gen.generate_from_db(transfer_schema_name) from_db
from transfer_schema
where transfer_schema_name='user_account';

/* The statement above generated the following (and some other) functions:

 norm_small.acct_to_db
 norm_small.acct_select_by_ids
 norm_small.acct_from_db

These functions provide an easiest way to use NORM.

Files select_by_ids.sql, building_search_conditions_readme.sql, and to_db_examples.sql 
contain usage examples for acct_select_by_ids,  acct_from_db, and acct_to_db, respectively.
*/