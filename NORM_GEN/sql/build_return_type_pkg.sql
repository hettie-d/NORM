drop function if exists norm_gen.build_return_type (int, text);
create or replace function norm_gen.build_return_type (
  p_transfer_schema_id int, p_root_object text)
  returns text
language SQL as
$body$
select 
/* Entering an object */
    ( $$/* entering $$ || $$ : $$ || p_root_object || $$ */
   $$) ||
  /* traverse sub-tree recursively */
  (select coalesce(string_agg(
       norm_gen.build_return_type ( p_transfer_schema_id, ref_object), 
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
  $$create type $$ ||db_schema||'.'|| db_record_type || $$ as (
      $$||
  --- $$ ---generate type columns here $$ || 
  (select 
      string_agg(db_col  || $$  $$ || 
      coalesce (db_type_calc,db_type), $$,
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

drop function if exists norm_gen.generate_types(p_schema_title text);
create or replace function norm_gen.generate_types(p_schema_title text)
returns text
language sql as
$body$
select norm_gen.build_return_type (transfer_schema_id, transfer_schema_root_object)                                                                                                                                                    
  from norm_gen.transfer_schema
 where transfer_schema_name=p_schema_title
;
$body$; 

--select norm_gen.generate_types('User account')
  