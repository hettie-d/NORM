drop type  if exists norm_gen.cond_record cascade;
create type norm_gen.cond_record as (
path text[],
node text,
cond text,
db_schema text,
db_table text, 
b_parent_fk_col text,
db_pk_col   text
);

create or replace function norm_gen.cond_ops (p_js text) returns  text
language SQL as
$body$
/* Probably this should be in a table or an arry */
select 
case p_js
when '$eq' then ' = '
when '$lt' then ' < '
when '$le' then '<= '
when '$ne' then '<> '
when '$ge' then '>= '
when '$gt' then ' > '
when '$like' then ' LIKE '
else 'UNKNOWN '
end;
$body$;

create or replace function norm_gen.build_object_term (
t_par text,
t_obj text,
row_conds text,
d_table text,
d_par_pk text,
d_fk text,
d_schema text) returns text
language SQL as
$body$
select format($$ %I IN (
   select %I from %s where
   $$,
      coalesce(d_par_pk, $$PK_$$   || t_par),
      coalesce(d_fk,  $$FK_$$ || t_obj || $$_$$ || t_par),
      coalesce(d_schema, $$SCHEMA_$$)||'.'||coalesce (d_table, $$TABLE_$$ || t_obj)
      )
    || row_conds ||   $$) $$;
$body$;

create or replace function norm_gen.build_simple_term (
t_key text,
t_value text,
d_col text,
d_col_type text) returns text
language SQL as
$body$
select 
     format ($$ %I $$,
      coalesce(d_col,$$J_$$ || t_key))
   ||  norm_gen.cond_ops(op)      
   || format ($$ (%L::%I) $$, val,
      coalesce (d_col_type, $$text$$))
FROM json_each_text(
   case when position ('{'in t_value) > 0 then t_value::json
   else json_build_object( '$eq', t_value)
   end ) as  r(op, val);
$body$;

create or replace function norm_gen.nest_cond ( 
   c_in norm_gen.cond_record [] ) returns norm_gen.cond_record []
language sql  as
$body$
with 
set_in  as (
select 
       path, 
       path[array_length(path,1)] as parent_node,
       node, 
       cond,
       db_schema,
       db_table, 
       db_parent_fk_col,
       db_pk_col 
from   unnest (c_in) p (
       path, 
       node, 
       cond,
       db_schema,
       db_table, 
       db_parent_fk_col,
       db_pk_col )
 ),
grand_p as (
select p.path as path,
       p.node as node,
      p.db_schema,
      p.db_table, 
      p.db_parent_fk_col,
      p.db_pk_col, 
       norm_gen.build_object_term(
       p.node,  c.node, c.cond, 
       c.db_table, p.db_pk_col, 
       c.db_parent_fk_col,
       c.db_schema)
        as cond
from set_in p
    join  set_in c
   on c.parent_node = p.node
  where
     c.node not in (select parent_node  
          from set_in)
 union all
 select path,
         node,
         db_schema,
         db_table, 
         db_parent_fk_col,
         db_pk_col, 
         cond
from  set_in dd
where node in (
   select parent_node from set_in)
 )
select
   case when array_length(cond_arr,1) = 1 then cond_arr
         else norm_gen.nest_cond (cond_arr)
         end
from
(select array_agg(
     (path, 
      node, 
      cond,
      db_schema,
      db_table, 
      db_parent_fk_col,
      db_pk_col 
      )::norm_gen.cond_record
    ) cond_arr
 from
 (select path,
         node,
         string_agg(cond, '
AND ') as cond,
      db_schema,
      db_table, 
       db_parent_fk_col,
       db_pk_col
from  grand_p
 group by path, node,
      db_schema,
      db_table, 
       db_parent_fk_col,
       db_pk_col
 )  u
 ) ff;
$body$;


create or replace function norm_gen.build_conditions (p_in json)
returns text
language SQL as
$body$
with  recursive
schema_info as (
select 
key,
value,
transfer_schema_id,
transfer_schema_root_object
from json_each_text (p_in)  q_in
 join norm_gen.transfer_schema ts
 on q_in.key = ts.transfer_schema_name
),
ts_object as (
select  o1.*
from norm_gen.transfer_schema_object o1
   join   schema_info si
   on o1.transfer_schema_id = si.transfer_schema_id
---) select * from ts_object;
),
ts_object_key as (
select  
  o2.t_object, tk.*
from norm_gen.transfer_schema_key tk
join ts_object o2
   on tk.transfer_schema_object_id = o2.transfer_schema_object_id
),
tree_node as (
select 
key as parent_node,
transfer_schema_root_object as node,
transfer_schema_root_object as t_object,
'root' as node_type,
     otr.db_table, 
     otr.db_parent_fk_col,
     otr.db_schema, 
     otr.db_pk_col
from schema_info s
join ts_object otr 
on  otr.t_object = s.transfer_schema_root_object
union
select
tn.node as parent_node,
tk.t_key_name as node,
tk.ref_object as t_object,
tk.t_key_type as node_type,
     o2.db_table, 
     o2.db_parent_fk_col,
     o2.db_schema, 
     o2.db_pk_col
from ts_object_key tk
join ts_object o2 on o2.t_object = tk.ref_object
join tree_node tn on tk.t_object = tn.t_object
where tk.t_key_type in ('array', 'object')
---) select * from tree_node;
),
x_tree as (
select 
parent_node, 
node, 
t_object, 
node_type, 
     db_table, 
     db_parent_fk_col,
     db_schema, 
     db_pk_col
from tree_node
union
select  
tn2.node as parent_node,
al. alias, 
al.alias as t_object,
'alias'as node_type,
     al.db_table, 
     al.pk_col,
     al.db_schema, 
     al.fk_col
from  
tree_node tn2 
join ts_object oa
on oa.t_object = tn2.t_object,
   unnest (oa.link) al
---)select * from x_tree;
),
px_tree as (
select
    array[xt.parent_node] as path,
   xt.parent_node, 
   xt.node, 
   xt.t_object, 
   xt.node_type, 
     xt.db_table, 
     xt.db_parent_fk_col,
     xt.db_schema, 
     xt.db_pk_col
from x_tree xt
join schema_info s on xt.parent_node = s.key
union
select 
    pxt.path || array[xt.parent_node] as path,
   xt.parent_node, 
   xt.node, 
   xt.t_object, 
   xt.node_type, 
     xt.db_table, 
     xt.db_parent_fk_col,
     xt.db_schema, 
     xt.db_pk_col
from x_tree xt
    join  px_tree pxt
    on pxt.node= xt.parent_node
---) select path, parent_node, node  from px_tree;
),
x_desce as (
select 
    xt.path,
    u.node as asc_node,
    xt.node as desc_node,
    xt.t_object,
    xt.node_type, 
     xt.db_table, 
     xt.db_parent_fk_col,
     xt.db_schema, 
     xt.db_pk_col
from  px_tree xt, 
  unnest (array[xt.node, xt.parent_node]) u(node)
UNION
select 
   xt.path,
  dk.asc_node,
  xt.node  as desc_node,
  xt.t_object,
  xt.node_type, 
     xt.db_table, 
     xt.db_parent_fk_col,
     xt.db_schema, 
     xt.db_pk_col
from       
   px_tree  xt
    join  x_desce dk
   on dk.desc_node = xt.parent_node 
---)select *  from x_desce;
),
scalar_keys as (
select  
     tk. t_key_name, 
     coalesce (tk.db_source_alias, tk.t_object) as t_object,
    tk.db_col, tk.db_type_calc
from ts_object_key  tk
where
    tk.t_key_type not in ('array', 'object')
    and       coalesce (tk.db_source_alias, tk.t_object)  in
    (select t_object from x_desce)
---) select t_object, t_key_name from scalar_keys;
),
x_scalar as (
select 
   sd.path, 
  sd.asc_node,
  sd.desc_node,
  sd.t_object,
  sd.node_type, 
     tk. t_key_name, 
    tk.db_col, tk.db_type_calc
from x_desce sd
join scalar_keys tk on tk.t_object = sd.t_object
---) select  t_object, t_key_name  from x_scalar;
),
all_key_node as (
select 
   path,
   asc_node,
   desc_node,
   desc_node as key,
   node_type,
   t_object  
from x_desce
union all
select 
   path,
   asc_node,
   desc_node,
   t_key_name as key,
   'scalar',
   t_object  
from x_scalar
--)select * from all_key_node order by 4,2;
),
raw_conditions as (
select 
     1 as l,
    k.path,
    k.asc_node,
    k.desc_node,
    k.t_object,
          s.key,
          s.value
from  schema_info p,
     json_each_text (p.value::json) s
join  all_key_node k
   on s.key = k.key
where 
 position ('{'in p.value) > 0  
 and k.asc_node = p.key
UNION 
select 
    r.l+1 as l,
    kr.path,
    kr.asc_node,
    kr.desc_node,
    kr.t_object,
   sr.key as key, 
   sr.value
from  
    raw_conditions r,
     json_each_text (r.value::json) sr
join  all_key_node kr
   on sr.key = kr.key
where  
 position ('{'in r.value) > 0  
 and kr.asc_node = r.key
---- )select * from raw_conditions;
),
per_object as (
select 
    r.path,
    r.asc_node,
    r.desc_node,
     string_agg(
       norm_gen.build_simple_term (
           r.key, 
        r.value,  t.db_col, t.db_type_calc),
          $and$ AND $and$
          )  as conds
from raw_conditions r
   join scalar_keys t
   on t.t_key_name = r.key
group by 
    r.path,
    r.asc_node,
    r.desc_node
---) select * from per_object;
)
select  cond
from unnest (norm_gen.nest_cond (
(select
   array_agg(
    (
    xt.path, po.desc_node, po.conds,
     xt.db_schema, xt.db_table, 
     xt.db_parent_fk_col,
     xt.db_pk_col
    )::norm_gen.cond_record)
from   px_tree xt
left join per_object po
     on  po.path = xt.path and po.desc_node = xt.node
     )
)
);
$body$;

