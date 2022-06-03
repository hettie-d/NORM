drop type  if exists norm_gen.cond_record cascade;
create type norm_gen.cond_record as (
gp text,
tbl text,
cond text,
db_schema text,
db_table text, 
b_parent_fk_col text,
db_pk_col   text
);

create or replace function cond_ops (p_js text) returns  text
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
      coalesce (d_table, $$TABLE_$$ || t_obj)
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
   ||  cond_ops(op)      
   || format ($$ (%L::%I) $$, val,
      coalesce (d_col_type, $$text$$))
FROM json_each_text(
   case when position ('{'in t_value) > 0 then t_value::json
   else json_build_object( '$eq', t_value)
   end ) as  r(op, val);
$body$;


create or replace function norm_gen.nest_cond ( 
   c_in norm_gen.cond_record [] ) returns norm_gen.cond_record []
language sql
as
$body$
with 
grand_p as (
select p.gp as gp,
       p.tbl as tbl,
      p.db_schema,
      p.db_table, 
      p.db_parent_fk_col,
      p.db_pk_col, 
       norm_gen.build_object_term(
       c.gp,  c.tbl, c.cond, 
       c.db_table, p.db_pk_col, 
       c.db_parent_fk_col,
       c.db_schema)
        as cond
from
           unnest (c_in) p (gp, tbl, cond,
       db_schema,
      db_table, 
     db_parent_fk_col,
      db_pk_col 
           )
    join unnest (c_in) c(gp, tbl, cond,
           db_schema,
      db_table, 
     db_parent_fk_col,
      db_pk_col )
   on c.gp = p.tbl
  where
            c.tbl not in (select gp from unnest(c_in))
 union all
 (select gp,
         tbl,
      db_schema,
      db_table, 
       db_parent_fk_col,
       db_pk_col, 
         cond
  from unnest (c_in) as dd(gp, tbl, cond,
           db_schema,
      db_table, 
     db_parent_fk_col,
      db_pk_col )
  where tbl in (select gp from unnest(c_in))
 )
 )
select
   case when array_length(cond_arr,1) = 1 then cond_arr
         else norm_gen.nest_cond (cond_arr)
         end
from
(select array_agg(
     (gp, tbl, cond,
       db_schema,
      db_table, 
     db_parent_fk_col,
      db_pk_col 
      )::norm_gen.cond_record
            ) cond_arr
 from
 (select gp,
         tbl,
         string_agg(cond, '
AND ') as cond,
      db_schema,
      db_table, 
       db_parent_fk_col,
       db_pk_col
from  grand_p
 group by gp, tbl,
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
root_info as (
select 
key,
value,
transfer_schema_id,
transfer_schema_root_object
from json_each_text (p_in)  q_in
 join transfer_schema ts
 on q_in.key = ts.transfer_schema_name
),
scalar_keys as (
select  
     tk. t_key_name, 
     coalesce (tk.db_source_alias, o1.t_object) as t_object,
    tk.db_col, tk.db_type_calc
from transfer_schema_key tk
   join transfer_schema_object o1
   on tk.transfer_schema_object_id = o1.transfer_schema_object_id
   join root_info  ri
   on o1.transfer_schema_id= ri.transfer_schema_id
where
    tk.t_key_type not in ('array', 'object')
---) select * from scalar_keys;
),
 cplx_keys as (
select  
     tk. t_key_name, 
     o1.t_object,
     o2.db_table, 
     o2.db_parent_fk_col,
     o2.db_schema, 
     o2.db_pk_col
from transfer_schema_key tk
   join transfer_schema_object o1
   on tk.transfer_schema_object_id = o1.transfer_schema_object_id
   join transfer_schema_object o2
   on tk.ref_object = o2.t_object
      and o1.transfer_schema_id = o2.transfer_schema_id
   join root_info  ri
   on o1.transfer_schema_id= ri.transfer_schema_id
where 
    tk.t_key_type in ('array', 'object')
union all
select  
     tk. ref_object, 
     o1.t_object,
     o2.db_table, 
     o2.db_parent_fk_col,
     o2.db_schema, 
     o2.db_pk_col
from transfer_schema_key tk
   join transfer_schema_object o1
   on tk.transfer_schema_object_id = o1.transfer_schema_object_id
   join transfer_schema_object o2
   on tk.ref_object = o2.t_object
      and o1.transfer_schema_id = o2.transfer_schema_id
   join root_info  ri
   on o1.transfer_schema_id= ri.transfer_schema_id
where 
    tk.t_key_type in ('array', 'object')
union all
select  
     al. alias, 
     o5.t_object,
     al.db_table, 
     al.pk_col,
     al.db_schema, 
     al.fk_col
from  transfer_schema_object o5
   join root_info  ri
   on o5.transfer_schema_id= ri.transfer_schema_id,
   unnest (o5.link) al
union all
select 
    transfer_schema_root_object, '$root',
     o3.db_table, o3.db_parent_fk_col,
     o3.db_schema, o3.db_pk_col
from root_info  ts
   join transfer_schema_object o3
   on o3.t_object = ts.transfer_schema_root_object
   and o3.transfer_schema_id = ts.transfer_schema_id
-----) select * from cplx_keys;
),
all_keys as (
select t_key_name, t_object  from scalar_keys
union all
select t_key_name, t_object from cplx_keys
),
raw_conditions as (
select NULL::text  as parent,
           key,
           value
from root_info
union all
select 
          k.t_object as parent,
          s.key,
          s.value
from  
    raw_conditions p,
     json_each_text (p.value::json) s
join  all_keys k
   on s.key = k.t_key_name
where   position ('{'in p.value) > 0  
---- ) select * from raw_conditions;
),
per_object as (
select r.parent,
          string_agg(
       norm_gen.build_simple_term (
           r.key, 
        r.value,  t.db_col, t.db_type_calc),
          $and$ AND $and$
          )  as conds
from raw_conditions r
   join scalar_keys t
   on t.t_key_name = r.key
   group by   r.parent
 ---) select * from per_object;
 )
select  cond
from unnest (norm_gen.nest_cond (
(select
   array_agg(
    (ck.t_object, parent, conds,
     ck.db_schema, ck.db_table, 
     ck.db_parent_fk_col,
     ck.db_pk_col
    )::norm_gen.cond_record)
from per_object po
     join cplx_keys ck
     on  po.parent = ck.t_key_name
     )
)
);
$body$;
