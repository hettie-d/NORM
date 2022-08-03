create or replace function norm_gen.build_to_db (p_hierarchy text) returns text
language SQL as
$generator$
with  recursive
schema_info as (
select 
transfer_schema_id as schema_id,
transfer_schema_name as schema_name,
transfer_schema_root_object as root_object,
db_schema
from   norm_gen.transfer_schema ts
where transfer_schema_name = p_hierarchy
 ---$$ACCOUNT_hierarchy$$
---) select * from schema_info;
),
ts_object as (
select  o1.*, 
   si.db_schema as si_db_schema
from norm_gen.transfer_schema_object o1
   join   schema_info si
   on o1.transfer_schema_id = si.schema_id
---) select t_object  from ts_object;
),
ts_object_key as (
select  
  o2.t_object, o2.si_db_schema,  tk.*
from norm_gen.transfer_schema_key tk
join ts_object o2
   on tk.transfer_schema_object_id = o2.transfer_schema_object_id
where tk.t_key_type <> $$object$$
   and tk.db_source_alias is null
---) select   t_object, t_key_name, db_col from ts_object_key;
),
tree_node as (
select 
1 as level,
schema_name as parent_node,
root_object as node,
   root_object as parent_object,
    root_object as t_object,
    'root' as node_type,
     otr.db_table, 
     coalesce (otr.db_parent_fk_col, otr.db_pk_col) as db_parent_fk_col,
     otr.db_schema, 
     otr.db_pk_col as parent_pk_col,
     otr.db_pk_col,
     otr.si_db_schema
from schema_info s
join ts_object otr 
on  otr.t_object = s.root_object
union
select
tn.level + 1 as level,
tn.node as parent_node,
tk.t_key_name as node,
tn.t_object as parent_object,
tk.ref_object as t_object,
tk.t_key_type as node_type,
     o2.db_table, 
     o2.db_parent_fk_col,
     o2.db_schema, 
     tn.db_pk_col as parent_pk_col,
     o2.db_pk_col,
     o2.si_db_schema
from ts_object_key tk
join ts_object o2 on o2.t_object = tk.ref_object
join tree_node tn on tk.t_object = tn.t_object
where tk.t_key_type in ('array') -- , 'object')
---) select *   from tree_node;
),
object_cols_in as (
select  tn.t_object, 
(select  string_agg (t_key_name, $$,
   $$) as cols
   from (select     tk.t_key_name
   from ts_object_key tk
   where tk.t_object = tn.t_object
   order by key_position) kt
   ) as columns_in
from  ts_object  tn
---) select * from object_cols_in;
),
types_in as (
select 
  t_object,
  (select max(level) from tree_node tr
  where tr.t_object = tn.t_object) as level,
   format($format$drop type if exists %3$s.%1$s_record_in cascade;
create type %3$s.%1$s_record_in as(
     %2$s,
    cmd text);
   $format$, 
       tn.t_object, ---1
   (select  string_agg (key_type_def, $$,
   $$)
   from (select  
      tk.t_key_name || $$ $$ ||
         case when tk.t_key_type = $$array$$ then 
              tn.db_schema ||$dot$.$dot$ ||
              tk.ref_object || $$_record_in  [ ]$$
         else coalesce(tk.db_type_calc, tk.db_type)
         end
    as key_type_def
   from ts_object_key tk
   where tk.t_object = tn.t_object
   order by key_position) kt
   ),  ---2
   tn.db_schema --3
  ) as type_in_def
from ts_object  tn
order by level desc, t_object
---) select * from types_in;
),

in_type_def as (
select string_agg(type_in_def, $$
$$)  as in_types
from types_in
---) select  in_types from in_type_def;
),
w_array_type as (
select string_agg(
format ($format$
drop type if exists %2$s.%3$s_rec_in_array cascade;
create type %2$s.%3$s_rec_in_array as(
    %3$s %2$s.%1$s_record_in [] ); $format$,
    t_object, ---1
    db_schema, ---2
    node ---3
    ), $$
$$)  arr_types
from tree_node
---) select * from w_array_type;
),
wp_array_type as (
select string_agg(
format ($format$
drop type if exists %2$s.%1$s_rec_in_array_pnt cascade;
create type %2$s.%1$s_rec_in_array_pnt as(
    %3$s  %4$s,
    %1$s %2$s.%5$s_record_in [] ); $format$,
    tn.node, ---1
    tn.db_schema, ---2
    tn.parent_pk_col, ---3
    coalesce(tk.db_type_calc, tk.db_type), ---4
    tn.t_object ---5
    ), $$
$$)  arr_types
from tree_node tn
join ts_object_key tk
on tk.t_object = tn.parent_object 
   and tk.db_col = tn.parent_pk_col
---) select * from wp_array_type;
),
func_parse as (
select  format( $prefix$
drop  function if exists %3$s.h%4$s_parse;
create or replace function %3$s.h%4$s_parse (
   p_in json) returns %3$s.%2$s_record_in[]
  language sql
  as
  $funcbody$
 select array_agg(row(
    %5$s,  ---root columns
    cmd
    )::%3$s.%2$s_record_in)  as parsed_input
   from  json_populate_recordset (NULL::%3$s.%2$s_record_in, p_in);
  $funcbody$;
$prefix$, 
     si.schema_name,  ---1
     si.root_object,  ---2
     si.db_schema,    ---3. 
     si.schema_id,  ---4
     (select  string_agg (key_def, $$,
   $$)
   from (select  
      tk.t_key_name as key_def
   from ts_object_key tk
   where tk.t_object = si.root_object
   order by key_position) kt
   ) ---5
      ) func_def
 from schema_info si
---) select * from func_parse;
),
func_h_delete_drop as (
select string_agg(del_cte_d, $$ $$) as func_def
from (select   format($format$
drop  function  if exists %1$s.h_%2$s_delete;
   $format$,
     tn.si_db_schema,    ---1
     tn.node ---2
   ) del_cte_d
from tree_node tn
order by level desc, t_object) dcte 
---) select * from func_h_delete_drop;
),
func_h_delete as (
select string_agg(del_cte, $$ $$) as func_def
from (select   format($format$
create or replace function %1$s.h_%2$s_delete (
   ids_in %3$s[]) returns %3$s[]
  language plpgsql
  as
$funcbody$
declare
v_ret  %3$s[];
begin
---    invoke h_delete for all chald nodes
%4$s
---   actual delete statement for current node
with del_stmt as(
   delete from %5$s.%6$s
   where  %7$s in 
      (select i  from unnest(ids_in) a(i))
   returning %8$s  ---  %7$s
)
select array_agg(%9$s) into v_ret from del_stmt;
 return v_ret;
 end;
$funcbody$;
   $format$,
     tn.si_db_schema,    ---1
     tn.node, ---2
   (select     tk.db_type_calc
   from ts_object_key tk
   where tk.t_object = tn.t_object
   and db_col = tn.db_pk_col
   ), ---3
   (select string_agg(ch_del, $$ $$) from (
      select format ($chfmt$
  perform %1$s.h_%2$s_delete (
      (select array_agg(%3$s) from %4$s.%5$s  where %6$s in (
      select i from unnest(ids_in) a(i)))
       );
      $chfmt$,
      ch.si_db_schema, ---ch-1
      ch.node,    ---ch-2
      ch.db_pk_col, ---ch 3
      ch.db_schema, ---ch 4
      ch.db_table, ---ch 5
      ch.db_parent_fk_col ---ch 6
      ) as ch_del
    from tree_node ch where  ch.parent_node = tn.node) sch
   ), ---4
   tn.db_schema, ---5
   tn.db_table, ---6
   tn.db_pk_col, ---7
      (select tk.t_key_name
   from ts_object_key tk
   where tk.t_object = tn.t_object
   and tn.db_pk_col = tk.db_col), ---8
   tn.db_parent_fk_col ---9
   ) del_cte
from tree_node tn
order by level desc, t_object) dcte 
---) select * from func_h_delete;
),
insertable_columns as (
select
  tk.t_object,
  string_agg(tk.db_col, $$,
      $$) as db_cols,
  string_agg(tk.t_key_name, $$,
      $$) as key_names
from ts_object_key tk
    join ts_object tso on tso.t_object = tk.t_object
   where    tk.db_col <> tso.db_pk_col
   and tk.t_key_type <>$$array$$
group by tk. t_object
---) select * from insertable_columns;
) ,
func_h_insert_drop as (
select string_agg(ins_d, $$ $$) as func_ins_d
from (select   format($format$
drop function if exists %1$s.h_%2$s_insert;
   $format$,
     tn.si_db_schema,    ---1
     tn.node) ---2
     as ins_d
from tree_node tn
order by level desc, t_object) inse 
---) select * from func_h_insert_drop;
),
insert_child_nodes as (
  select  pnode,
     string_agg(ch_ins, $$ $$) as ch_ins
 from (
      select tn.node as pnode,
      format ($chfmt$
  perform %1$s.h_%2$s_insert (
       ---build parameter ---
       (select  array_agg(ch_objects) from (
        select 
         row(  p.pk , ch_in. %2$s)::%1$s.%2$s_rec_in_array_pnt
            as ch_objects    
       from rows from (
       unnest (v_ret),
       unnest ( rows_in ) 
       ) rf(pk, %2$s), --- rows from 
       unnest (rf.%2$s) ch_in
       where r_in.%2$s is not null ) subq
       ) --- parameter
       ); --- perform 
      $chfmt$,
      tn.si_db_schema, ---ch-1
      ch.node,    ---ch-2
      ch.db_pk_col, ---ch 3
      ch.db_schema, ---ch 4
      ch.db_table, ---ch 5
      ch.db_parent_fk_col, ---ch 6
      tn.db_pk_col ---ch 7
      ) as ch_ins
    from  tree_node tn
    join tree_node ch 
    on  ch.parent_node = tn.node
   ) ch
group by pnode
---)select * from insert_child_nodes;
),
func_h_insert as (
select string_agg(ins_f, $$ $$) as func_def
from (select   format($format$
create or replace function %1$s.h_%2$s_insert (
   rows_in %1$s.%2$s_rec_in_array_pnt[]) 
   returns %3$s[]
  language plpgsql
  as
$funcbody$
declare
v_ret %3$s[ ];
begin
--- insert stmt for current node
with
insert_stmt as (
insert into %5$s.%6$s (
    %7$s  --- tn.db_parent_fk_col,
   %8$s)  --- insertable columns
(select  
  %9$s  ---value for PK, if level > 1
%10$s    --- insertable_keys
from  unnest(rows_in) r_in(p, a),
        unnest (r_in.a) r)
 returning %11$s)
select array_agg(  %11$s)  into v_ret
from  insert_stmt;
----------
---    invoke h_insert for all chald nodes
%4$s
   return v_ret;
   end;
   $funcbody$;
   $format$,
     tn.si_db_schema,    ---1
     tn.node, ---2
   (select     tk.db_type_calc
   from ts_object_key tk
   where tk.t_object = tn.t_object
   and db_col = tn.db_pk_col
   ), ---3.  pk_type
   (select ch_ins from insert_child_nodes
   where pnode = tn.node), ---4 --- all child nodes
   tn.db_schema, ---5
   tn.db_table, ---6
   case when tn.level=1 then $$ $$
  else tn.db_parent_fk_col ||$$,$$ 
  end, ---7
  (select db_cols
  from insertable_columns ic
  where ic.t_object = tn.t_object), ---8
(case when level > 1 then $$r_in.p,$$
  else $$ $$ end), ---9
(select key_names
  from insertable_columns ic
  where ic.t_object = tn.t_object), ---10
  tn.db_pk_col, ---11
  tn.db_parent_fk_col ---12
   ) ins_f
from tree_node tn
order by level desc, t_object) inse 
---) select * from func_h_insert;
),
func_h_update_drop as (
select string_agg(upd_d, $$ $$) as func_upd_d
from (select   format($format$
drop function if exists %1$s.h_%2$s_update;
   $format$,
     tn.si_db_schema,    ---1
     tn.node) ---2
     as upd_d
from tree_node tn
order by level desc, t_object) inse 
---) select * from func_h_update_drop;
),
update_child_nodes as (
  select  pnode,
     string_agg(ch_upd, $$ $$) as ch_upd
 from (
      select tn.node as pnode,
      format ($chfmt$  perform %1$s.h_%2$s_update (
       (select  array_agg(ch_objects) from (
        select 
         row(  ch_in.%3$s , ch_in. %2$s)::%1$s.%2$s_rec_in_array_pnt
            as ch_objects  
       from        
       unnest ( rows_in) rf,
       unnest (rf.r_in.%2$s) ch_in ) flat
       ) --- parameter
       ); --- perform 
      $chfmt$,
      tn.si_db_schema, ---ch-1
      ch.node,    ---ch-2
      (select tk.t_key_name
   from ts_object_key tk
   where tk.t_object = tn.t_object
   and tn.db_pk_col = tk.db_col) --3
      ) as ch_upd
from  tree_node tn
    join tree_node ch 
    on  ch.parent_node = tn.node
   ) ch
group by pnode
---)select * from update_child_nodes;
),
update_stmt as (
select   tn.node,
   format($format$ with
   update_stmt as (
   update %7$s.%2$s as a set
        ---- columns ---
        %6$s
   from unnest (rwos_in)  ri,
        unnest (ri.%1$s) i
   where  a.%3$s = i.%4$s
   returning a.%5$s,  a.%3$s as pk)
   select array_agg(%5$s) into v_upd
    from  update_stmt;
   $format$,
   tn.node, ---1
   tn.db_table, ---2
   tn.db_pk_col, ---3
   (select tk.t_key_name
   from ts_object_key tk
   where tk.t_object = tn.t_object
   and tn.db_pk_col = tk.db_col), ---4
   tn.db_parent_fk_col, ---5
   (select  string_agg(
      format($f$ %1$s = coalesce(i.%2$s, a.%1$s)$f$,
      tk.db_col,tk.t_key_name),$$,
      $$) 
   from ts_object_key tk
   where tk.t_object = tn.t_object
   and tk.db_col not in (tn.db_pk_col, tn.db_parent_fk_col)
   and tk.t_key_type not in ($$array$$,$$object$$)
   ), ---6
   tn.db_schema ---7
   ) upd_cte
from tree_node tn
---) select * from update_stmt;
),
func_h_update as (
select string_agg(upd_f, $$ $$) as func_def
from (select   format($format$
create or replace function %1$s.h_%2$s_update (
   rows_in %1$s.%2$s_rec_in_array_pnt[]) 
   returns %3$s[]
  language plpgsql
  as
$funcbody$
declare
v_ret %3$s[ ];
v_ins %3$s[ ];
v_del %3$s[ ];
v_upd %3$s[ ];
begin
--- update stmt for current node
%5$s
---    invoke h_update for all chald nodes
%4$s
---  invoke delete for current level
select  %1$s.h_%2$s_delete (
(select array_agg(%6$s) 
from unnest (rows_in) r_in, unnest (r_in.%2$s) o_in
where cmd=$$d$$)
 ) into v_del;
--- invoke insert for current level
select  %1$s.h_%2$s_insert(
(select
 array_agg( row(p, array_agg(row(
   %7$s
   )::%1$s.%2$s_record_in))::%1$s.%2$s_rec_in_array_pnt) 
from unnest (rows_in) r_in(p,%2$s), unnest (r_in.%2$s) o_in
where %6$s is null
group by p)
 ) into v_ins;
 select array_agg(id) into v_ret from (
 select distinct id from unnest(v_upd || v_ins || v_del) r(id %3$s)) d;
   return v_ret;
   end;
   $funcbody$;
   $format$,
     tn.si_db_schema,    ---1
     tn.node, ---2
   (select     tk.db_type_calc
   from ts_object_key tk
   where tk.t_object = tn.t_object
   and db_col = tn.db_pk_col
   ), ---3.  pk_type
   (select ch_upd from update_child_nodes
   where pnode = tn.node), ---4 --- all child nodes
   (select upd_cte from update_stmt
   where node = tn.node), ---5 --- 
      (select tk.t_key_name
   from ts_object_key tk
   where tk.t_object = tn.t_object
   and tn.db_pk_col = tk.db_col), ---6
(select  
   string_agg(t_key_name, $$,
   $$) as key_names
   from (select  
      tk.t_key_name
   from ts_object_key tk
   where tk.t_object = tn.t_object
   order by key_position) kt) ---7
   ) upd_f
from tree_node tn
order by level desc, t_object) upde 
---) select * from func_h_update;
),
func_to_db as (
select format($format$
drop function if exists %3$s.h%4$s_to_db;
create or replace function %3$s.h%4$s_to_db (
   p_in json) returns %5$s[]
  language sql
  as
$funcbod$
select %3$s.h_%2$s_update(
   ----  have  to combine with fake  parent ID
array[ row( NULL::%5$s,
   (%3$s.h%4$s_parse(p_in)::%3$s.%2$s_record_in[]))
   ]::%3$s.%2$s_rec_in_array_pnt[]
   );
$funcbod$;
$format$,
     si.schema_name,  ---1
     si.root_object,  ---2
     si.db_schema,    ---3. 
     si.schema_id,  ---4
   (select     tk.db_type_calc
   from ts_object_key tk
   where tk.t_object = si.root_object
   and db_col = (
      select db_pk_col from ts_object tso
      where tso.t_object = tk.t_object)
   ) ---5
      ) func_def
from schema_info si
---) select * from func_to_db;
),


last_cte as (select $$;$$)
select 
 (select in_types from in_type_def) ||
 (select arr_types from w_array_type) ||
 (select arr_types from wp_array_type) ||
(select func_def from func_parse) ||
(select func_def from func_h_delete_drop) ||
(select func_def from func_h_delete) ||
(select func_ins_d from func_h_insert_drop) ||
(select func_def from func_h_insert) ||
(select func_upd_d from func_h_update_drop) ||
(select func_def from func_h_update) ||
(select func_def from func_to_db) 
;;
$generator$;

