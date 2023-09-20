create or replace function norm_gen.create_generated_types(
  p_schema_name text) returns text 
language plpgsql as
$body$
declare
begin
execute norm_gen.generate_types(p_schema_name);
return  p_schema_name;
end;$body$;
