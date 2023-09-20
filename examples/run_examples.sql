/*
 This file contains psql input that can be used to compile example schemas and generate database type definitions and functions
*/
\cd  /Users/boris/Locally/WORKING/2023-NORM/NORM/examples
--- cd to the directory containing JSON schemas
\cd <your  directory containing JSON schemas>

--- make sure NORM and postgres_air database objects are accessible ---
set search_path to norm_gen,postgres_air;

--- compile example schemas ---
\set  p_schema `cat booking_minimal.json`
select ts_all(:'p_schema'::json);
\set  p_schema `cat booking_extended.json`
select ts_all(:'p_schema'::json);
\set  p_schema `cat flight-boarding.json`
select ts_all(:'p_schema'::json);
\set  p_schema `cat flight-booking.json`
select ts_all(:'p_schema'::json);
\set  p_schema `cat flight-summary.json`
select ts_all(:'p_schema'::json);
\set  p_schema `cat timetable_hierarchy.json`
select ts_all(:'p_schema'::json);

select transfer_schema_name, db_schema, db_prefix, norm_schema from transfer_schema;

/* Generated code will be placed into 'generated' sub-directory of examples directory.
Run something like 'mkdir generated' to make sure this sub-directory exists 
or modify  '\out' commands below to place it somewhere else 
*/
\pset tuples_only on
\out  generated/outgoung_types.sql
select 
regexp_split_to_table(
(select string_agg(
norm_gen.generate_types(transfer_schema_name), $$
$$) from transfer_schema)
,   $$
$$)  rst;
---  generate 'select full hierarchy'
\out generated/select_from.sql
select 
regexp_split_to_table(
  (select string_agg(
norm_gen.nested_root(transfer_schema_name), $$
$$) from transfer_schema)
,   $$
$$)  rst;
----- GENERATE TO_DB ----
\out generated/to_db.sql
select 
regexp_split_to_table(
(select string_agg(
norm_gen.build_to_db(transfer_schema_name), $$
$$) from transfer_schema),   $$
$$)  rst;
\out
\pset tuples_only off

--- Compile generated code to the database --
--- The following statement generates the same code as above and run it to create type definitions and functions

select 
   norm_gen.create_generated_types(transfer_schema_name)
from transfer_schema;

select 
   transfer_schema_name,
   norm_gen.generate_to_db_function(transfer_schema_name) to_db,
   norm_gen.generate_select_by_id(transfer_schema_name) select_by_ids,
   norm_gen.generate_from_db(transfer_schema_name) from_db
from transfer_schema;

/* Execute just generated function and 
extract pretty JSON for 2 bookings
*/
select  jsonb_pretty(to_jsonb(
norm.bmh_select_by_ids(
(select array_agg(booking_id) from
(select booking_id from postgres_air.booking b 
limit 2) )
)));

/*.  Get data from DB with condition in JSON */
select  jsonb_pretty(to_jsonb(
norm.bmh_from_db(
$$
{
"booking_minimal_hierarchy":{
"departure_airport_code":"ORD",
"arrival_city":{"$like":"NEW Y%"},
"last_name":"Smith"}
}
$$::json)
));



---- MORE EXAMPLES OF SEARCH CONDITIONS
/* The following examples return generated code as psql output. 
These code frabments can be appended to appropriate SELECT-FROM 
clauses generated above.
*/
select 
 build_conditions(
$$
{
"booking_minimal_hierarchy":{
"departure_airport_code":"ORD",
"arrival_city":{"$like":"HELS%"},
"last_name":"Smith"}
}
$$::json);

select  build_conditions($$
{"booking_extended_hierarchy":{
"booking":{
"leg_num":"1",
   "flight":{
"departure_airport_code":"ORD",
"arrival_city":{"$like":"Newl%"},
"scheduled_departure":{"$gt":"2023-07-20"},
"scheduled_departure":{"$le":"2023-07-21"}
},
"last_name":"Smith"}
}}
$$::json);

select  build_conditions($$
{"booking_extended_hierarchy":{
"booking":{
"booking_id":{"$gt":"0"},
"last_name":"Smith",
"leg_num":"1",
"departure_airport_code":"ORD",
"arrival_city":{"$like":"Newl%"},
"scheduled_departure":{"$gt":"2023-07-20"},
"scheduled_departure":{"$le":"2023-07-21"}
}
}}
$$::json);

select  build_conditions($$
{"flight_boarding_hierarchy":{
"departure_airport_code":"ORD",
"arrival_city":{"$like":"Newl%"},
"scheduled_departure":{"$gt":"2023-07-20"},
"scheduled_departure":{"$le":"2023-07-21"}
}}
$$::json);

select  build_conditions($$
{"booking_minimal_hierarchy":{
"booking":{
"departure_airport_code":"ORD",
"arrival_city":{"$like":"Newl%"},
"scheduled_departure":{"$gt":"2023-07-20"},
"scheduled_departure":{"$le":"2023-07-21"},
"last_name":"Smith"}
}}
$$::json);

---  Generate database objects directly to the database 


