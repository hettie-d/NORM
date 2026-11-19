drop function if exists norm_gen.generate_from_db;
create or replace function norm_gen.generate_from_db(
  p_schema_name text, 
  p_top_alias text = 'top') returns text 
language plpgsql as
$body$
declare
v_select_from text;
v_rec_type text;
v_func text;
v_name text;
begin
v_select_from :=$$select array_agg($$ || p_top_alias || $$_row) from (
$$ ||
norm_gen.build_nested_select_clause(p_schema_name,p_top_alias=>p_top_alias, p_agg=>' ');

select 
s.norm_schema ||$$.$$ || s.db_prefix || $$_from_db$$,
 s.norm_schema ||$$.$$ || s.db_prefix ||$$_$$ ||o.db_record_type ||$$ [] $$
into  v_name, v_rec_type
from norm_gen.transfer_schema s
join norm_gen.transfer_schema_object o
on o.transfer_schema_id=s.transfer_schema_id
and o.t_object = s.transfer_schema_root_object
join norm_gen.transfer_schema_key k
on k.transfer_schema_object_id=o.transfer_schema_object_id
and o.db_pk_col= k.db_col
where s.transfer_schema_name=p_schema_name;
------
v_func := format( 
$fmt$create or replace function %1$s (
   p_cond json) returns  %2$s 
  language 'plpgsql'
as $BODY$
declare
v_result  %2$s;
v_sql text;
begin
if  (select key from json_each(p_cond) k
     where k.key not in ('$OrderBy','$Limit','$Offset')
) <> %3$s  
then
   raise exception $$Schema name in the condition should be %% $$, %3$s;
   end if;
v_sql:=  %4$s || $CR$
 $CR$||
coalesce($$where $$ ||
norm_gen.build_conditions(p_cond,%5$s),$$ $$) ||
norm_gen.build_order_by(p_cond,%5$s) || $$
) pre_agg$$;
execute v_sql into v_result;
return  v_result;
end; $BODY$;  
$fmt$,
v_name, --1
v_rec_type,  --2
quote_literal(p_schema_name),  ---3
quote_literal(v_select_from),  --- 4
quote_literal(p_top_alias)   --- 5
);
execute 'drop function if exists ' || v_name;
execute v_func;
return  $$Function: $$ ||v_name ||$$, Return type: $$ || v_rec_type ;
--exception when others then 
--return $$ERROR:$$ || coalesce(v_func, $$Invalid schema name: $$|| p_schema_name);
end;$body$;
