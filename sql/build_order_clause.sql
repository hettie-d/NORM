create or replace function norm_gen.select_options (jkw text) returns  text
language SQL
begin atomic;
select 
case jkw
when '$Limit' then 'LIMIT '
when '$Offset' then 'OFFSET '
else 'UNKNOWN '
end;
end;

drop function if exists norm_gen.build_order_by;
create or replace function norm_gen.build_order_by (
   p_in json,
   p_top_alias text = 'top') -- set to NULL if alias is not needed
returns text
language SQL 
begin atomic;
with  
intput_keys as (
select 
   key,
   value
from json_each_text (p_in)  q_in
---) select * from intput_keys;
),
schema_info as (
select 
   key,
   value,
   transfer_schema_id,
   transfer_schema_root_object
from intput_keys q_in
 join norm_gen.transfer_schema ts
 on q_in.key = ts.transfer_schema_name
where q_in.key not in ('$OrderBy','$Limit','$Offset')
---) select * from schema_info;
),
ts_object as (
select  
   o1.t_object, 
   o1.db_table,
   tk.t_key_name, 
   tk.db_col, 
   tk.db_source_alias
from norm_gen.transfer_schema_object o1
   join   schema_info si
   on o1.transfer_schema_id = si.transfer_schema_id
---   and o1.t_object = si.transfer_schema_root_object
join transfer_schema_key tk
   on tk.transfer_schema_object_id = o1.transfer_schema_object_id
---) select *  from ts_object;
),
order_keys as(
select 
   row_number() over() as pos,
   --- a.value, 
   case when position('{' in a.value)>0 then
      (select 
          case when key = '$Expression' 
          then value
          else ''  end
      from json_each_text(a.value::json))
      else '' end  as expression,
   case when position('{' in a.value)>0 then
      (select 
          case when key = '$Expression' 
          then '' else key  end
      from json_each_text(a.value::json))
      else a.value end order_key,
   case when position('{' in a.value)>0 then
      (select 
          case when key = '$Expression' 
          then '' else ' ' ||  value  end
      from json_each_text(a.value::json))
      else '' end as order_sup
 from  intput_keys s,
 json_array_elements_text(s.value::json) a
 where s.key ='$OrderBy'
 --) select * from order_keys;
),
order_clause as(
select 
coalesce('ORDER BY ' ||
string_agg (
   k.expression ||
   case when k.order_key = '' then ''
   else 
     coalesce(t.db_source_alias, p_top_alias) ||'.'||
     coalesce(t.db_col,'INVALID KEY' || k.order_key)
   end || 
   k.order_sup, ', ' ORDER BY k.pos),'')  order_by_clause
from order_keys k
left join ts_object t
on k.order_key = t.t_key_name
---order by k.pos
),
limit_offset as(
select 
   coalesce(string_agg(
   norm_gen.select_options(key) || value,'
'),'') l_o
from intput_keys q_in
where q_in.key in ('$Limit','$Offset')
)
select 
   coalesce(string_agg(obc,'
'),'') as opt
from
(select order_by_clause as obc from order_clause
union all
select l_o from limit_offset) x
;
end;
