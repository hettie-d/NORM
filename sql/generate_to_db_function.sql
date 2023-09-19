create or replace function norm_gen.generate_to_db_function(
  p_schema_name text)
returns text 
language plpgsql as
$body$
declare 
v_sql text;
v_func text;
begin
select norm_gen.build_to_db (p_schema_name) into v_sql;
execute v_sql;
select 
ts.norm_schema ||$$.$$ || ts.db_prefix || $$_to_db$$
into v_func
from   norm_gen.transfer_schema ts
where transfer_schema_name = p_schema_name;
return v_func;
exception when others then 
return $$--- ERROR ---$$;
end;$body$;


