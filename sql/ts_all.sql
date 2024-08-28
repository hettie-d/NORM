drop function if exists ts_all;
create or replace function norm_gen.ts_all (p_schema json)
returns text
language plpgsql
as
$body$
declare v_transfer_schema_id int;
begin
select norm_gen.save_transfer_schema (p_schema, 'true') into v_transfer_schema_id;
perform norm_gen.save_schema_object (v_transfer_schema_id);
perform norm_gen.save_schema_object_key (v_transfer_schema_id);
perform norm_gen.update_db_type(v_transfer_schema_id);
--
return 
   'transfer_schema_id:'|| v_transfer_schema_id ||$$
   $$ ||
   (select coalesce(max(error_msgs), $$ $$) from norm_gen.transfer_schema_xref()
where transfer_schema_id = v_transfer_schema_id)
   ;
end;
$body$;
--

