--- select * from norm_gen.generate_select_by_id_function('User account')

create or replace function norm_gen.generate_select_by_id_function(
  p_schema_name text,
  p_root_object_name text default null)
returns boolean 
language plpgsql as
$body$
declare 
v_sql text;
v_schema_name text;
v_root_object_name text;
v_transfer_schema_id int;
v_root_object_pk text;
v_root_object_pk_type text;
v_db_record_type text;
begin
select s.db_schema, 
        transfer_schema_root_object, 
        s.transfer_schema_id,
		    db_col,
		    db_type_calc,
		    db_record_type
		 into
		   v_schema_name,
		   v_root_object_name,
		   v_transfer_schema_id,
		   v_root_object_pk,
		   v_root_object_pk_type,
		   v_db_record_type  
from norm_gen.transfer_schema s
join norm_gen.transfer_schema_object o
on o.transfer_schema_id=s.transfer_schema_id
and t_object=transfer_schema_root_object
join norm_gen.transfer_schema_key k
on k.transfer_schema_object_id=o.transfer_schema_object_id
and db_pk_col=db_col
where transfer_schema_name=p_schema_name;
v_sql:=
$txt$ create or replace function $txt$ ||
       v_schema_name||$txt$.$txt$||
       coalesce(p_root_object_name, v_root_object_name) ||
       $txt$_search_by_ids(p_$txt$||
       v_root_object_pk||$txt$s $txt$||
       v_root_object_pk_type||$txt$[]
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
$$ where $txt$||v_root_object_pk|| 
$txt$ in($$ ||array_to_string(p_$txt$||
       v_root_object_pk||$txt$s ,',')||$$) )s
$$;
  execute v_sql into v_result;
    return (v_result);

end;
$BODY$;
$txt$;	
raise notice '%', v_sql;
return true;
end;$body$;
