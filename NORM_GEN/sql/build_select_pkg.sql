---select norm_gen.nested_root('User account')
drop function if exists norm_gen.build_from_clause;
create or replace function norm_gen.build_from_clause (
p_schema text, p_table text, p_alias text, p_link norm_gen.t_d_link[ ]
) returns text
language SQL as
$bbody$
select
format (
 $$  
from  %I.%I  %I $$, 
p_schema,
p_table, 
p_alias) ||
---- embedded ----
(select  coalesce( string_agg(  
  format ($$
   join %I.%I %I on  %I.%I = %I.%I $$,  
   al.db_schema,
   al.db_table,  
   al.alias,  
   al.alias, 
   al.pk_col,   
   p_alias,  
   al.fk_col),
    $$  $$),$$ $$)
   from unnest(p_link) al
   )
   as from_clause;
$bbody$;

drop function if exists norm_gen.build_nested_row;
create or replace function norm_gen.build_nested_row (
p_schema_id int,   p_object_id int, p_row_type text, p_alias text) 
returns text
language SQL as 
$body$
select $$ /* Entering $$||  p_row_type || $$ */
    row($$ ||
(select  string_agg(
case 
when t_key_type = $$array$$ then 
$$   (
    select array_agg( $$ || (
select norm_gen.build_nested_row(p_schema_id, r.transfer_schema_object_id, 
       r.db_record_type, k.t_key_name) || 
       norm_gen.build_from_clause (r.db_schema,r.db_table, k.t_key_name, r.link)
from norm_gen.transfer_schema_object r
where r.t_object = k.ref_object
and r.transfer_schema_id = p_schema_id) ||$$)
$$
when t_key_type = $$object$$ then 
$$(  $$ || (
select norm_gen.build_nested_row(p_schema_id, r.transfer_schema_object_id, 
       r.db_record_type, k.t_key_name) || 
       norm_gen.build_from_clause (r.db_schema, r.db_table, k.t_key_name, r.link)
from norm_gen.transfer_schema_object r
where r.t_object = k.ref_object
and r.transfer_schema_id = p_schema_id) ||$$)
$$
else  coalesce(k.db_source_alias,p_alias, k.db_table) ||$$.$$||
k.db_col
end,
$$  ,
    $$)
from (
select * from norm_gen.transfer_schema_key 
where transfer_schema_object_id = p_object_id
order by  key_position) k
)
|| $$)::$$  || p_row_type 
 as nested_object;
$body$;




drop function if exists norm_gen.nested_root;
create or replace function norm_gen.nested_root(
   p_hierarchy text) returns text
   language SQL as
   $body$
   select 
   $$ /* selecting $$ || p_hierarchy ||$$ $$ || transfer_schema_root_object || $$ */
 select    ---to_json (
           array_agg( 
   $$ 
   ||  norm_gen.build_nested_row(s.transfer_schema_id,  tso.transfer_schema_object_id, tso.db_record_type, $$top$$::text)
   || $$   )  --- close array_agg
   ---   )   --- close to_json
   $$ 
   || norm_gen.build_from_clause(tso.db_schema,tso.db_table,$$top$$, tso.link)
   from norm_gen.transfer_schema s
   join norm_gen.transfer_schema_object tso
   on tso.transfer_schema_id = s.transfer_schema_id
   and tso.t_object = s.transfer_schema_root_object
   where s.transfer_schema_name = p_hierarchy;
   $body$;
	
