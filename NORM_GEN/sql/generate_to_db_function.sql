create or replace function norm_gen.generate_to_db_function(
  p_schema_name text)
returns boolean 
language plpgsql as
$body$
declare 
v_sql text;
begin
select norm_gen.build_to_db (p_schema_name) into v_sql;
execute v_sql;
return true;
exception when others then 
return false;
end;$body$;

