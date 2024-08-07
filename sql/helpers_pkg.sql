---this package contains functions which can be used by app devs for automated generation of the initial db mappinga and/or for mapping transfer
---schema changes back to db.
---These helpers cover only the most basinc cases, and it's intentional, 
---since we believe that more complicated mapping and database design should be done in the database
---

create or replace function norm_gen.transfer_schema_alter_table_exec (p_schema_title text)
returns text
language plpgsql
as
$block$
declare v_sql text;
begin 
select norm_gen.transfer_schema_alter_table (p_schema_title) into v_sql;
execute v_sql;
return v_sql;
end;
$block$;


create or replace function norm_gen.transfer_schema_alter_table (p_schema_title text)
returns text
stable language sql
begin atomic
select 
--ts.transfer_schema_name as schema_title--,
--tso.t_object as transfer_object_name,
$$alter table $$ ||
coalesce(tso.db_schema, ts.db_schema) ||$$.$$ || coalesce(tso.db_table, tso.t_object) || 
$$ $$ ||
string_agg($$add column $$||coalesce(tsk.db_col,tsk.t_key_name) ||$$ $$ ||
       case when tsk.t_key_type = $$number$$ then $$numeric$$ 
	    when tsk.t_key_type = $$string$$ 
		     and tsk.t_key_format in ('date', 'date-time')then $$timestamptz$$ 
			 when tsk.t_key_type = $$string$$ then $$text$$
             else tsk.t_key_type
             end, 
    $$,
$$) || $$;
$$
from norm_gen.transfer_schema_object tso
join norm_gen.transfer_schema ts
   on ts.transfer_schema_id = tso.transfer_schema_id
join norm_gen.transfer_schema_key tsk
   on tsk.transfer_schema_object_id = tso.transfer_schema_object_id
   where ts.transfer_schema_name= p_schema_title
   and coalesce(tsk.db_col,tsk.t_key_name) not in (select column_name::text
   from information_schema.columns
   where table_schema= coalesce(tso.db_schema, ts.db_schema)
   and table_name=coalesce(tso.db_table, tso.t_object))
 group by 
    ts.transfer_schema_name,
    ts.db_schema,
    tso.db_schema,
    tso.t_object,
    tso.db_table,
    tso.db_pk_col
 ;
end;

/*
Functions in this file generate table definitions from a transfer schema or vice versa. The quality of output in both cases is very poor (as typically happens with ORM automations). Therefore, the output must be either tailored manyally or used as is in extremely simple cases for rapid prototyping.
*/

/* Create table definition from transfer schema 
By default, table definitions are generated for all tables referenced in all compiled schemas. The  returned columns can be used to filter needed schemas or required schema and/or object. 
Usage example:
-- explain
select pk_constraint 
from   transfer_schema_to_table()
where schema_title like $$sto%$$;    

Note that the function will be in-lined. Uncomment explain to see how filtering conditions are pushed down.
*/
create or replace function norm_gen.transfer_schema_to_table ()
returns table (
schema_title text,
transfer_object_name text,
table_def text,
pk_constraint text)
stable language sql
begin atomic
select 
ts.transfer_schema_name as schema_title,
tso.t_object as transfer_object_name,
$$create table $$ ||
coalesce(tso.db_schema, ts.db_schema, $$DB_SCHEMA$$) ||$$.$$ || coalesce(tso.db_table, tso.t_object) || $$(
$$ ||
string_agg(coalesce(tsk.db_col,tsk.t_key_name) ||$$ $$ ||
       case when tsk.t_key_type = $$number$$ then $$numeric$$ 
            else $$text$$ 
            end, 
    $$,
$$) || $$);
$$
        as table_def,
   $$alter table $$ ||
      coalesce(tso.db_schema, ts.db_schema, $$DB_SCHEMA$$) ||$$.$$ || 
      coalesce(tso.db_table, tso.t_object) ||
      $$ add constraint $$ ||
      coalesce(tso.db_table, tso.t_object) || 
$$_PK primary key $$ || tso.db_pk_col ||
   $$;$$   as pk_constraint
from norm_gen.transfer_schema_object tso
join norm_gen.transfer_schema ts
   on ts.transfer_schema_id = tso.transfer_schema_id
join norm_gen.transfer_schema_key tsk
   on tsk.transfer_schema_object_id = tso.transfer_schema_object_id
 group by 
    ts.transfer_schema_name,
    ts.db_schema,
    tso.db_schema,
    tso.t_object,
    tso.db_table,
    tso.db_pk_col
    ;
end;

/* Create single-level hierarchy from the definition of one table.
Usage example:
select jsonb_pretty(
   table_to_transfer_schema(
       $$postgres_air$$, 
       $$flight$$,
       $$flight_only$$
       )::jsonb);
 
*/ 
create or replace function norm_gen.table_to_transfer_schema (
   db_schema text,
   db_table text,
   transfer_schema_title text default null)
returns json
stable language sql
begin atomic
select
json_build_object (
   $$title$$, coalesce (transfer_schema_title, db_table),
   $$description$$, $$Generated by NORM on $$  ||now(),
   $$type$$, $$array$$,
   $$items$$,   json_build_object (
           '$ref', $$#/definitions/$$ || db_table),
   $$db_mapping$$, json_build_object (
      $$db_schema$$, db_schema,
      $$db_prefix$$, db_table),
   $$definitions$$, json_build_object (
      db_table, json_build_object(
         $$type$$, $$object$$,
         $$db_mapping$$, json_build_object(
            $$db_table$$, db_table,
            $$pk_col$$, 
            (select 
   coalesce(max(column_name), $$UNKNOWN$$)
from pg_constraint cn
join pg_namespace s 
on s.oid=connamespace
join information_schema.constraint_column_usage cc
on cc.constraint_name = conname::text
and cc.constraint_schema =  nspname::text
where  nspname::text = db_schema
and contype = 'p'
and table_name = db_table
)
,
            $$record_type$$, db_table || $$_row$$
            ), -- db_mapping
         $$properties$$, json_object_agg (
           column_name::text,
           json_build_object (
                   $$type$$, 
                   (case when data_type::text in 
                       ('numeric', 'int', 'int4', 'bigint', 'integer',
                      'float', 'double precision')  
                      then 'number'
                when data_type::text = 'boolean' then 'boolean'
                else 'string' end) ::text,
                $$db_mapping$$, json_build_object(
                   $$db_type$$,
   data_type::text||
               case when character_maximum_length is not null
                 then '('||character_maximum_length::text
                  ||')'
                 else ''
                 end ||
                 case data_type when 'numeric'
                 then '('||numeric_precision::text||','||numeric_scale::text|| ')'
                 else ''  end ::text
                   )  -- column db mapping
                )  --- column properties
            )   -- properties
         )   --- db_table
      ) --- definitions
   ) --- schema
   as transfer_schema
from information_schema.columns
where table_schema = db_schema
      and table_name =db_table
---order by ordinal_position
;      
end;
