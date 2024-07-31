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


create or replace function transfer_schema_alter_table (p_schema_title text)
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
from transfer_schema_object tso
join transfer_schema ts
   on ts.transfer_schema_id = tso.transfer_schema_id
join transfer_schema_key tsk
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









