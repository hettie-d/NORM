--set search_path to norm_gen;

drop type if exists norm_gen.t_d_link cascade;
create type norm_gen.t_d_link as (
  alias text,
  db_schema text,
  db_table text,
  pk_col text,
  fk_col text
  );
  
drop table if exists norm_gen.transfer_schema cascade;
create table norm_gen.transfer_schema (
transfer_schema_id serial primary key,
transfer_schema_name text unique,
transfer_schema_type text,
transfer_schema_description text,
transfer_schema_root_object text,
definitions json ,
db_schema text
);

drop table if exists norm_gen.transfer_schema_object cascade ;
create table norm_gen.transfer_schema_object (
transfer_schema_object_id serial primary key,
transfer_schema_id int references norm_gen.transfer_schema(transfer_schema_id)
   on delete cascade,
t_object text,
t_parent_object text,
db_schema text,
db_table text,
db_pk_col text,
db_parent_fk_col text,
db_record_type text,
link norm_gen.t_d_link[],
properties json
);

drop table if exists norm_gen.transfer_schema_key cascade;
create table norm_gen.transfer_schema_key(
   transfer_schema_key_id serial primary key,
   transfer_schema_object_id int references norm_gen.transfer_schema_object(transfer_schema_object_id)
       on delete cascade,
   t_key_name text,
   t_key_type text,
   t_key_format text,
   t_key_items json, /* shouldb be items, not object_items */
   db_table text,
   db_source_alias text,
   db_col text,
   db_type text,
   fk_col  text,  
   ref_object text,
   ref_object_id int,
   db_type_calc text,
   key_position int
);
