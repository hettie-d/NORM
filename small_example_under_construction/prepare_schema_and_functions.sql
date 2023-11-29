--- This script must be executed after 'create_and_initialize_tables.sql'
--- cd to the directory containing small example
\cd <your  directory containing small example>

set search_path to norm_small,norm_gen;

--- compile JSON schema
\set  p_schema `cat user_account.json`
select ts_all(:'p_schema'::json);

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

The function returns all data related to accounts listed in the array of account_id values passed as an argument. The example below returns all accounts in our example. The output is additionally processed with jsonb_pretty function to meke the output readable.
*/

select  jsonb_pretty(to_jsonb(
 norm_small.acct_select_by_ids(
(select array_agg(account_id) from account)
)));

/*
See files building_search_conditions_readme.sql and to_db_examples.sql 
for usage of  acct_from_db and acct_to_db, respectively.
*/