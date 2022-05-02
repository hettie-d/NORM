drop function build_from_clause;
create or replace function build_from_clause (
p_table text, p_alias text, p_link t_d_link[ ]
) returns text
language SQL as
$bbody$
select
 $$  
FROM $$ || p_table ||$$ $$|| p_alias ||
---- embedded ----
(select  coalesce( string_agg(  $$
   JOIN $$ 
   || al.db_table || ' ' || al.alias || 
   $$ ON $$ || al.alias ||'.' || al.pk_col ||$$=$$ ||
   p_alias ||$$.$$ || al.fk_col, $$  $$),$$ $$)
   from unnest(p_link) al
   )
   as from_clause;
$bbody$;

select build_from_clause (db_table, db_table || 's', link)
 from transfer_schema_object;


drop function build_nested_row;
create or replace function build_nested_row (
p_schema_id int,   p_oid int, p_row_type text, p_alias text default NULL) 
returns text
language SQL as 
$body$
select $$ /* Entering $$||  p_row_type || $$ */
row($$ ||
(select  string_agg(
case 
when t_key_type = $$array$$ then 
$$(
select array_agg( $$ || (
select build_nested_row(p_schema_id, r.transfer_schema_object_id, r.db_record_type, k.t_key_name) || 
build_from_clause (r.db_table, k.t_key_name, r.link)
from transfer_schema_object r
where r.t_object = k.ref_object) ||$$)
$$
when t_key_type = $$object$$ then 
$$(  $$ || (
select build_nested_row(p_schema_id, r.transfer_schema_object_id, r.db_record_type, k.t_key_name) || 
build_from_clause (r.db_table, k.t_key_name, r.link)
from transfer_schema_object r
where r.t_object = k.ref_object) ||$$)
$$
else  coalesce(k.db_source_alias,p_alias, k.db_table) ||$$.$$||
k.db_col
end,
$$,
$$)
from (
select * from transfer_schema_key 
where transfer_schema_object_id = p_oid
order by  key_position) k
)
|| $$)::$$  || p_row_type 
 as nested_object;
$body$;

select build_nested_row (transfer_schema_id, transfer_schema_object_id, db_record_type)
from transfer_schema_object;

drop function nested_root;
create or replace function nested_root(
   p_hierarchy text) returns text
   language SQL as
   $body$
   select 
   $$ /* selecting $$ || p_hierarchy ||$$ $$ || transfer_schema_root_object || $$ */
   select to_json (array_agg( 
   $$ 
   ||  build_nested_row(s.transfer_schema_id,  tso.transfer_schema_object_id, tso.db_record_type, $$top$$::text)
   || $$ ))$$ 
   || build_from_clause(tso.db_table,$$top$$, tso.link)
   from transfer_schema s
   join transfer_schema_object tso
   on tso.transfer_schema_id = s.transfer_schema_id
   and tso.t_object = s.transfer_schema_root_object
   where s.transfer_schema_name = p_hierarchy;
   $body$;

select  nested_root(transfer_schema_name) nested_qyery
from transfer_schema;
