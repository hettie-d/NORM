create or replace function norm_gen.generate_select_by_id(
  p_schema_name text) returns text 
language plpgsql as
$body$
declare
v_func text;
v_name text;
begin
execute norm_gen.generate_types(p_schema_name);
select 
format( $fmt$create or replace function %1$s.%2$s_select_by_ids (
   p_ids %3$s [] ) returns  %1$s.%2$s_%4$s []
  language 'plpgsql'
as $BODY$
declare
v_result  %1$s.%2$s_%4$s [];
v_sql text;
begin
v_sql:= %5$s || $where$
where %6$s  in( $where$||
array_to_string(p_ids,$c$,$c$) || $p$) $p$;
execute v_sql into v_result;
return  v_result;
end; $BODY$;  
$fmt$,
s.norm_schema, --1
s.db_prefix,  --2
k.db_type_calc,  ---3
o.db_record_type,  ---4
quote_literal(norm_gen.nested_root(s.transfer_schema_name)),  --- 5
k.db_col  -- 6
),
s.norm_schema ||$$.$$ || s.db_prefix || $$_select_by_ids$$
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
