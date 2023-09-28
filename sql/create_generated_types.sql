create or replace function norm_gen.generate_from_db(
  p_schema_name text) returns text 
language plpgsql as
$body$
declare
v_func text;
v_name text;
begin
select 
format( $fmt$create or replace function %1$s.%2$s_from_db (
   p_cond json) returns  %1$s.%2$s_%4$s []
  language 'plpgsql'
as $BODY$
declare
v_result  %1$s.%2$s_%4$s [];
v_sql text;
begin
if  (select key from json_each(p_cond) k) <> %3$s  
then
   raise exception $$Schema name in the condition should be %% $$, %3$s;
   end if;
v_sql:= %5$s || $where$
where  $where$||
build_conditions(p_cond) ;
execute v_sql into v_result;
return  v_result;
end; $BODY$;  
$fmt$,
s.norm_schema, --1
s.db_prefix,  --2
quote_literal(p_schema_name),  ---3
o.db_record_type,  ---4
quote_literal(norm_gen.build_nested_select_clause(s.transfer_schema_name))  --- 5
),
s.norm_schema ||$$.$$ || s.db_prefix || $$_from_db$$
into v_func, v_name
from norm_gen.transfer_schema s
join norm_gen.transfer_schema_object o
on o.transfer_schema_id=s.transfer_schema_id
and o.t_object = s.transfer_schema_root_object
join norm_gen.transfer_schema_key k
on k.transfer_schema_object_id=o.transfer_schema_object_id
and o.db_pk_col= k.db_col
where s.transfer_schema_name=p_schema_name;
execute v_func;
return  v_name;
end;$body$;
create or replace function norm_gen.create_generated_types(
  p_schema_name text) returns text 
language plpgsql as
$body$
declare
begin
execute norm_gen.generate_types(p_schema_name);
return  p_schema_name;
end;$body$;
