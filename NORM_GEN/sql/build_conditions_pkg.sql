drop type  if exists norm_gen.cond_record cascade;
create type norm_gen.cond_record as (
gp text,
tbl text,
cond text);

create or replace function norm_gen.build_object_term (
t_par text,
t_obj text,
row_conds text,
d_table text,
d_par_pk text,
d_fk text) returns text
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
t_op text,
t_value text,
d_col text,
d_col_type text) returns text
language SQL as
$body$
select format ($$ %I $$,
      coalesce(d_col,$$J_$$ || t_key))
   ||  coalesce(t_op,
         case
         when d_col_type = $$text$$ then $$ LIKE $$
         else $$ = $$
         end)
   || format ($$ (%L::%I) $$, t_value,
      coalesce (d_col_type, $$text$$));
$body$;


create or replace function norm_gen.nest_cond (p_schema_id int,
   c_in norm_gen.cond_record [] ) returns norm_gen.cond_record []
language sql
as
$body$
with tr_schema as(
select
   tso.t_object,
   tso.t_parent_object,
   t_parent_object,
   tso.db_schema||'.'||tso.db_table d_table_name,
   tso.db_pk_col  d_pk,
   tso.db_parent_fk_col  d_parent_fk
from norm_gen.transfer_schema_object tso
where tso.transfer_schema_id = p_schema_id
)
select
   case when array_length(cond_arr,1) = 1 then cond_arr
         else norm_gen.nest_cond (p_schema_id,cond_arr)
         end
from
(select array_agg(
            (gp, tbl, cond)::norm_gen.cond_record
            ) cond_arr
 from
 (select gp,
         tbl,
         string_agg(cond, '
AND ') as cond
from (
select p.gp as gp,
       p.tbl as tbl,
       norm_gen.build_object_term(
       c.gp,  c.tbl, c.cond, tc.d_table_name, tp.d_pk, tc.d_parent_fk)
        as cond
from
           unnest (c_in) p (gp, tbl, cond)
    join unnest (c_in) c(gp, tbl, cond)
                          on c.gp = p.tbl
      left join tr_schema tp
                           on tp.t_object = c.gp
      left join tr_schema tc
                          on tc.t_object = c.tbl
  where
            c.tbl not in (select gp from unnest(c_in))
 union all
 (select gp,
         tbl,
         cond
  from unnest (c_in)
  where tbl in (select gp from unnest(c_in))
 )
 ) aa
 group by gp, tbl
 )  u(gp, tbl, cond)
 ) ff;
$body$;


create or replace function norm_gen.build_conditions (p_schema_id int, p_in json)
returns text
language SQL as
$body$
with recursive raw_conditions as (
   select '$root' as gp,
          '$root'  as tbl,
           key,
           value
   from json_each_text (p_in)
  union all
   select p.tbl as gp,
          p.key as tbl,
          s.key,
          s.value
   from raw_conditions p,
        json_each_text (p.value::json) s
   where position ('{'in p.value) > 0
   ),
per_object as (
   select r.gp,
          r.tbl,
          string_agg(
       norm_gen.build_simple_term (
           r.key,NULL,  /* t_op, */
        r.value,  t.db_col, t.db_type_calc),
          $and$ AND $and$
          )  as conds
   from raw_conditions r
       left join norm_gen.transfer_schema_key  t
          on r.key = t.t_key_name
          and r.tbl =
          (select  t_object
          from norm_gen.transfer_schema_object o1
          where o1.transfer_schema_object_id = t.transfer_schema_object_id)
      and   p_schema_id  =
       (select  transfer_schema_id
          from norm_gen.transfer_schema_object o2
          where o2.transfer_schema_object_id = t.transfer_schema_object_id)
   where position ('{'in value) = 0
   group by  gp, tbl
   )
select  cond
from unnest (norm_gen.nest_cond (p_schema_id,
(select
   array_agg(
    (gp, tbl, conds)::norm_gen.cond_record)
from per_object)
)
);
$body$;
