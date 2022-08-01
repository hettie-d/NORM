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
where transfer_schema_name =  p_hierarchy
---- $$ACCOUNT_hierarchy$$
---) select * from schema_info;
),
func_prefix as (
select  format( $prefix$

drop function if exists  %3$s.%4$s_%5$s_to_db;
create or replace function %3$s.%4$s_%5$s_to_db (
   p_in json) returns jsonb
  language SQL
  as
  $funcbody$
with 
 pgn_input_%2$s as materialized (
 select * 
   from  json_populate_recordset (NULL::%3$s.%2$s_record_in, p_in)
   ),
$prefix$, 
     schema_name,  ---1
     root_object,  ---2
     db_schema,    ---3. 
     root_object, --4
     schema_id ---5
      )
 as f_prefix
 from schema_info 
---) select * from func_prefix;
),
ts_object as (
select  o1.*
from norm_gen.transfer_schema_object o1
   join   schema_info si
   on o1.transfer_schema_id = si.schema_id
---) select t_object  from ts_object;
),
ts_object_key as (
select  
  o2.t_object, tk.*
from norm_gen.transfer_schema_key tk
join ts_object o2
   on tk.transfer_schema_object_id = o2.transfer_schema_object_id
where tk.t_key_type <> $$object$$
   and tk.db_source_alias is null
---) select   t_object, t_key_name from ts_object_key;
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
     otr.db_pk_col
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
     o2.db_pk_col
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
pgn_input as (
select string_agg(pgni, $$  $$) as pgn_inp
from (select 
   format($format$
   pgn_input_%1$s as (select 
         prnt.%4$s,
         %3$s,
         n.cmd
    from pgn_input_%2$s prnt,
       unnest (prnt.%1$s) n
where prnt.%1$s is not null
),
$format$,  
   tn.node,  ---1
   tn.parent_node, ---2
   (select string_agg(key ,$$,
   $$) as n_keys
    from ( select  
        $$n.$$ || tk.t_key_name  as key
       from ts_object_key tk
      where tk.t_object = tn.t_object
      order by key_position) nkeys
      ), ---3
      (select pk.t_key_name
       from ts_object_key  pk
          join tree_node pn on pn.t_object = pk.t_object
          join ts_object po on po.t_object = pn.t_object
    where pn.node = tn.parent_node
       and po.db_pk_col = pk.db_col
      ) ---4
   ) as  pgni
from tree_node tn
where level > 1
order by level asc, t_object 
)  pgn
---) select * from pgn_input;
),
delete_stmt as (
select string_agg(del_cte, $$ $$) as deletions
from (select   format($format$
   delete_%1$s as (
   delete from %6$s.%2$s
   where  %3$s in
      (select %4$s from pgn_input_%1$s
      where cmd = $$d$$)
   returning %5$s,   %3$s as pk
   ),
   $format$,
   tn.node,  ---1
   tn.db_table, ---2
   tn.db_pk_col, ---3
   (select tk.t_key_name
   from ts_object_key tk
   where tk.t_object = tn.t_object
   and tn.db_pk_col = tk.db_col), ---4
   tn.db_parent_fk_col, ---5
   tn.db_schema --- 6
   ) del_cte
from tree_node tn
order by level desc, t_object) dcte 
---) select * from delete_stmt;
),
update_stmt as (
select string_agg(upd_cte, $$ $$) as updates
from (select   format($format$
   update_%1$s as (
   update %7$s.%2$s as a set
        ---- columns ---
        %6$s
   from pgn_input_%1$s i
   where  a.%3$s = i.%4$s
   returning a.%5$s,  a.%3$s as pk
   ),
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
order by level desc, t_object) dcte 
---) select * from update_stmt;
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
pre_insert as (
select 
  tn.level, tn.node,
format($format$
pre_insert_%1$s as (
select 
     %2$s
from pgn_input_%1$s
where %3$s is null 
    %4$s
 ),
$format$,
tn.node,
(select  string_agg(tk.t_key_name, $$,
$$) as cols
from ts_object_key tk
where tk.t_object =tn.t_object and tk.t_key_type <>$$object$$
),
(select    tk.t_key_name
from ts_object_key tk
where tk.t_object = tn.t_object and tk.db_col = tn.db_pk_col
),
(select  Coalesce($$ and ( $$||
    string_agg(tk.t_key_name || $nn$ is not null $nn$, $or$ or $or$) || $b$ ) $b$,
    ' ') sub_objects
from ts_object_key tk
where tk.t_object = tn.t_object and tk.t_key_type = $$array$$)
)  pre_ins
from tree_node tn
where tn.node in (select parent_node from tree_node)
order by  tn.level, tn.node
---) select * from pre_insert;
),
insert_parent as (
select  format($format$
insert_%1$s as (
insert into %6$s.%2$s (
     %3$s)
select
     %4$s
from pre_insert_%1$s 
returning %5$s
),
$format$,
node,  ---1
db_table,   ---2
ic.db_cols,  ---3
ic.key_names, ---4
   db_pk_col,   ---5
   db_schema ---6
)  ins_root
from  tree_node tn
   join insertable_columns ic on ic.t_object=tn.t_object
where level = 1
---) select * from insert_parent;
),
parent_link as (
select tn.level, tn.node,
 format($format$
parent_link_%1$s as materialized (
   (select 
       %5$s,  -- parent PK key
       %6$s  --- column list
  from rows from  (
     unnest (
    (select array_agg(%3$s)  --- parent PK col
     from insert_%2$s)
        ),
     unnest (
  /* array of phones arrays */
 (select array_agg(row(%1$s)::%7$s.%1$s_rec_in_array) 
   from pre_insert_%2$s)
        ) 
        ---as (%1$s  %7$s.%1$s_rec_in_array)
         ) nin (%5$s, %1$s),
       unnest (nin.%1$s) u
    ) 
  UNION ALL
  /* Pre-existing parents with new child items */
  (select  
       %5$s,
       %6$s
    from (select *
    from pgn_input_%2$s p
     where %5$s is not null) np,
       unnest (np.%1$s) u
    ) 
    ),
$format$,
tn.node, ---1
tn.parent_node, ---2
tn.parent_pk_col,   --3
tn.t_object,  ---4
(select t_key_name from ts_object_key 
where  t_object=tn.parent_object and db_col=tn.parent_pk_col), ---5
ic.columns_in, ---6
tn.db_schema ---7
) p_link
from tree_node tn
   join object_cols_in ic on ic.t_object=tn.t_object
where level > 1
order by tn.level, tn.node
---) select * from parent_link;
),
insert_flat  as (
select  tn.level, tn.node,
format($format$
insert_flat_%1$s as (
insert into %9$s.%8$s (
   %2$s)
 select
   %3$s
 from %4$s i 
 where %5$s is null 
       %6$s
returning %7$s
),
$format$,
tn.node, ---1
ic.db_cols, --2
ic.key_names, ---3
case when level =1 then $$pgn_input_$$ || tn.node
else $$parent_link_$$ || tn.node end,---4
(select tk.t_key_name from ts_object_key tk
where tk.t_object = tn.t_object and tk.db_col=tn.db_pk_col
), ---5
(select  Coalesce($$ and ( $$||
    string_agg(tk.t_key_name || $nn$ is  null $nn$, $and$ and $and$) || $b$ ) $b$,
    ' ') sub_objects
from ts_object_key tk
where tk.t_object = tn.t_object and tk.t_key_type = $$array$$), ---6
tn.db_parent_fk_col, ---7
tn.db_table, ---8
tn.db_schema --- 9
) i_flat
from tree_node tn
join insertable_columns ic on ic.t_object =tn.t_object
order by tn.level, tn.node 
----) select * from insert_flat;
),
insert_deep as (
select format($format$
insert_deep_%1$s as (
insert into %9$s.%8$s (
   %2$s)
 select
   %3$s
 from %4$s i 
 where %5$s is null 
       %6$s
returning %7$s
),
$format$,
tn.node, ---1
ic.db_cols, --2
ic.key_names, ---3
case when level =1 then $$pgn_input_$$ || tn.node
else $$parent_link_$$ || tn.parent_node end,---4
(select tk.t_key_name from ts_object_key tk
where tk.t_object = tn.t_object and tk.db_col=tn.db_pk_col
), ---5
(select  Coalesce($$ and ( $$||
    string_agg(tk.t_key_name || $nn$ is  not  null $nn$, $or$ or $or$) || $b$ ) $b$,
    ' ') sub_objects
from ts_object_key tk
where tk.t_object = tn.t_object and tk.t_key_type = $$array$$), ---6
tn.db_pk_col, ---7
tn.db_table, ---8
tn.db_schema ---9
) i_deep
from tree_node tn
join insertable_columns ic on ic.t_object =tn.t_object
where level > 1 and tn.node in
 (select parent_node from tree_node)
order by tn.level , tn.node
----) select * from insert_deep;
),
del_upd_stmt as (
select string_agg(exe_stmt, $$union $$) as exec_du
from (select format($exec$
Select %1$s from    delete_%2$s
union
Select %1$s from    update_%2$s
$exec$,
tn.db_parent_fk_col,
tn.node
) as exe_stmt
from tree_node tn
order by tn.level desc, tn.node) stmt
---) select * from del_upd_stmt;
),
ins_stmt as (
select string_agg(exe_stmt, $$union $$) as exec_ins
from (select format($exec$
Select %1$s from    insert_flat_%2$s
%3$s
$exec$,
tn.db_parent_fk_col, --- 1
tn.node, ---2
case when tn.level >1 
   and tn.node in (select parent_node from tree_node)
  then $$union 
Select %1$s from    insert_deep_%2$s
$$
else $$ $$
end ---3
) as exe_stmt
from tree_node tn
order by tn.level asc, tn.node) stmt
---) select exec_ins from ins_stmt;
),
wrap_output as (
select format($format$
select to_json(array_agg(%1$s)) from (
$format$,
tn.db_pk_col) w_out
from tree_node tn where level = 1
---) select * from wrap_output;
)
select
 (select in_types from in_type_def) ||
 (select arr_types from w_array_type) ||
(select f_prefix from func_prefix) ||
    (select pgn_inp from pgn_input) ||
    (select  deletions from delete_stmt) ||
    (select updates  from update_stmt) ||
    (select  string_agg(pre_ins,$$ $$) from pre_insert) ||
    (select ins_root from insert_parent) ||
    (select string_agg(p_link, $$ $$) from parent_link) ||
    (select string_agg(i_flat, $$ $$ ) from insert_flat) ||
    (select coalesce(string_agg(i_deep, $$ $$), $$ $$) from insert_deep)   || 
  $px$ last_cte as (select $$ $$ as blank)
  $px$ ||
  (select w_out from wrap_output) ||
  (select exec_du from del_upd_stmt) ||
  $$UNION$$ ||
  (select exec_ins from ins_stmt) ||
$zz$) final;
  $funcbody$;
$zz$
;
$generator$;

