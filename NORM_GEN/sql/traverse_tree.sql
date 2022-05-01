--select  norm_gen.traverse_tree (7, 'account') 
--select * from norm_gen.transfer_schema 
drop function if exists norm_gen.traverse_tree (int, text);
create or replace function norm_gen.traverse_tree (
  p_transfer_schema_id int, p_root_object text)
  returns text
language SQL as
$body$
select 
/* Entering an object */
    ( $$/* entering $$ || p_transfer_schema_id::text || $$ : $$ || p_root_object || $$ */
   $$) ||
  /* traverse sub-tree recursively */
  (select coalesce(string_agg(
       norm_gen.traverse_tree ( p_transfer_schema_id, ref_object), 
       $$
  $$), $$ $$)
  from norm_gen.transfer_schema_key k
join norm_gen.transfer_schema_object   ob
on k.transfer_schema_object_id = ob.transfer_schema_object_id
where 
  transfer_schema_id=p_transfer_schema_id 
  and ob.t_object = p_root_object
  and t_key_type in ($$object$$,$$array$$)
  )  ||
  /* The sub-tree is done, complete processing of current object */
  (select 
  $$create type $$ || db_record_type || $$ as (
     $$||
  --- $$ ---generate type columns here $$ || 
  (select 
      string_agg(db_col  || $$  $$ || db_type_calc, $$,
      $$) 
from norm_gen.transfer_schema_key k
join  norm_gen.transfer_schema_object   ob
on k.transfer_schema_object_id = ob.transfer_schema_object_id
where    ob.t_object = p_root_object
/* order by key position */
  ) ||
  $$
  );
  $$
   from norm_gen.transfer_schema_object 
   where t_object = p_root_object
   and transfer_schema_id=p_transfer_schema_id)
  ;
$body$;
/*
drop function if exists norm_gen.generate_types( p_schema_title text);
create function norm_gen.generate_types( p_schema_title text)
returns text
language sql as
$body$
select norm_gen.traverse_tree (transfer_schema_id, transfer_schema_root_object)                                                                                                                                                    
  from norm_gen.transfer_schema
 where transfer_schema_name=p_schema_title
;
end;
$body$; 
*/
--select  traverse_tree (transfer_schema_name, transfer_schema_root_object) 
--  from transfer_schema;
  