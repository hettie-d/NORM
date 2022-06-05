create or replace function norm_gen.generate_search_generic_function(
  p_schema_name text,
  p_root_object_name text default null)
returns boolean 
language plpgsql as
$body$
declare 
v_sql text;
v_schema_name text;
v_root_object_name text;
v_db_record_type text;
begin
select s.db_schema, 
        transfer_schema_root_object, 
		db_record_type
		 into
		   v_schema_name,
		   v_root_object_name,
		   v_db_record_type  
from norm_gen.transfer_schema s
join norm_gen.transfer_schema_object o
  on o.transfer_schema_id=s.transfer_schema_id
  and t_object=transfer_schema_root_object
where transfer_schema_name=p_schema_name;
v_sql:=
$txt$ create or replace function $txt$ ||
       v_schema_name||$txt$.$txt$||
       coalesce(p_root_object_name, v_root_object_name) ||
       $txt$_search_generic(p_search_json json
       ) returns $txt$ ||v_schema_name||$txt$.$txt$||v_db_record_type||
       $txt$[]
  language 'plpgsql'
as $BODY$
declare
v_result $txt$||v_schema_name||$txt$.$txt$||v_db_record_type||
       $txt$[];
v_sql text;
begin
v_sql:=norm_gen.nested_root($txt$||
       quote_literal(p_schema_name)||$txt$)||
       $$ where $$||norm_gen.build_conditions(('{
       "$txt$||p_schema_name||$txt$":'||p_search_json::text||'}')
::json);
      
 execute v_sql into v_result;
    return (v_result);
end;
$BODY$;
$txt$;	
execute v_sql;
return true;
exception when others then 
return false;
end;$body$;
