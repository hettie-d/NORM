--delete from norm_gen.transfer_schema_object

drop type if exists norm_gen.json_schema_top cascade;
create type norm_gen.json_schema_top as (
  title text,
  type text,
  description text,
  db_mapping json,
  items json,
  definitions json,
  b_schema text
  );

drop type if exists norm_gen.t_d_object cascade;
create type norm_gen.t_d_object as (
  db_schema text,
  db_table text,
  pk_col text,
  parent_fk_col text,
t_parent_object text,
t_parent_object_id int,
  record_type text,
  embedded norm_gen.t_d_link[],
  properties json
  );
drop type if exists norm_gen.json_schema_object cascade;
create type norm_gen.json_schema_object as (
  "type" text,
  db_mapping json,
  properties json
  );


drop type if exists norm_gen.json_schema_key;
create type norm_gen.json_schema_key as (
  "type"text,
  items json,
  "format" text,
  db_mapping json
 );

drop type if exists norm_gen.td_key_mapping cascade;
create type  norm_gen.td_key_mapping as (
  db_table text,
  db_source_alias text,
  db_col text,
  db_type text,
  fk_col text,
  ref_object text,
  ref_object_id int
  );

drop function if exists norm_gen.save_transfer_schema (p_schema json,
 p_delete boolean) cascade;

create or replace function norm_gen.save_transfer_schema (p_schema json,
p_delete boolean default false)
returns int
language plpgsql
as
$body$
declare v_transfer_schema_id int;
begin
if p_delete is true
then
delete from norm_gen.transfer_schema where transfer_schema_name=(
   select title from json_populate_record (NULL::norm_gen.json_schema_top,
            p_schema));
end if;
insert into norm_gen.transfer_schema (
     transfer_schema_name,
     transfer_schema_type,
     transfer_schema_description,
     transfer_schema_root_object,
     definitions,
     db_schema)
select
      title,
      type,
      description,
      split_part(p.items->>'$ref', '/',3) as root_object,
      definitions,
      db_mapping->>'db_schema'
      from  json_populate_record (NULL::norm_gen.json_schema_top,p_schema) p
      returning transfer_schema_id into v_transfer_schema_id;
      return v_transfer_schema_id;
end ;$body$;


drop function if exists norm_gen.save_schema_object(p_transfer_schema_id int) cascade;
create or replace function norm_gen.save_schema_object (p_transfer_schema_id int)
returns setof norm_gen.transfer_schema_object
language plpgsql
as
$body$
declare
v_dflt_schema text;
v_definitions json;
begin
select db_schema, definitions
into v_dflt_schema,
  v_definitions
from norm_gen.transfer_schema
     where transfer_schema_id=p_transfer_schema_id;
delete from norm_gen.transfer_schema_object
  where transfer_schema_id=p_transfer_schema_id;
insert into norm_gen.transfer_schema_object
(transfer_schema_id,
 t_object,
db_schema,
db_table,
db_pk_col,
db_parent_fk_col,
db_record_type,
link ,
properties)
select p_transfer_schema_id,
d.key as t_object_name,
coalesce(m.db_schema,
      v_dflt_schema),
m.db_table,
m.pk_col,
m.parent_fk_col,
m.record_type,
m.embedded,
f.properties
  from   (select * from   json_each (v_definitions )) d,
        json_populate_record (NULL::norm_gen.json_schema_object, d.value)f,
        json_populate_record (
         NULL::norm_gen.t_d_object,  f.db_mapping) m
      ;
return query
select * from  norm_gen.transfer_schema_object
      where transfer_schema_id=p_transfer_schema_id;
end; $body$;

drop function  if exists  norm_gen.save_schema_object_key (p_transfer_schema_id int) cascade;
create or replace function norm_gen.save_schema_object_key (p_transfer_schema_id int)
returns setof norm_gen.transfer_schema_key
language plpgsql
as
$body$
begin
insert into norm_gen.transfer_schema_key(
   transfer_schema_object_id,
   t_key_name,
   t_key_type,
   t_key_format,
   t_key_items,
   db_table,
   db_source_alias,
   db_col,
   db_type,
   fk_col,
   ref_object,
   ref_object_id,
   key_position
)
select
   s.transfer_schema_object_id,
   k.key as t_key_name,
   p."type"as t_key_type,
   p.format as t_key_format,
   p.items as t_object_items,
   coalesce (km.db_table, 
      case 
      when km.db_source_alias is not null then
           (select db_table 
           from        unnest (s.link) al
           where al.alias = km.db_source_alias
           )
      else  s.db_table
      end
      ) as db_table,
   km.db_source_alias,
   coalesce (km.db_col, k.key) as db_col,
   coalesce(km.db_type,
      s.db_schema || $$.$$ || 
coalesce (km.db_table, 
      case 
      when km.db_source_alias is not null then
           (select db_table 
           from        unnest (s.link) al
           where al.alias = km.db_source_alias
           )
      else  s.db_table
      end)
     || $$.$$ || coalesce(km.db_col, k.key)|| $$%type$$),
   km.fk_col,
 split_part(p.items->>'$ref', '/',3),
 (select transfer_schema_object_id from norm_gen.transfer_schema_object
        where transfer_schema_id=p_transfer_schema_id and t_object=split_part(p.items->>'$ref', '/',3) ),
 row_number()  over(partition by s.transfer_schema_object_id ) 
from  norm_gen.transfer_schema_object s,
   json_each(s.properties) k,
   json_populate_record (NULL::norm_gen.json_schema_key,   k.value) p,
   json_populate_record (NULL::norm_gen.td_key_mapping,   p.db_mapping) km
   where transfer_schema_id=p_transfer_schema_id
;

update norm_gen.transfer_schema_object o
set
t_parent_object =(select  po.t_object from norm_gen.transfer_schema_key k
				  join norm_gen.transfer_schema_object po
				  using (transfer_schema_object_id)
				  where
				  k.ref_object = o.t_object
				   and po.transfer_schema_id=o.transfer_schema_id)
				where transfer_schema_id=p_transfer_schema_id;
				
/*correctly assign db types for record types */

update norm_gen.transfer_schema_key k 
set db_type_calc =(
select  ob.db_schema||'.'||ob.db_record_type  
from norm_gen.transfer_schema_object ob
where ob.transfer_schema_object_id=k.ref_object_id)
	where  t_key_type = $$object$$
   and k.transfer_schema_object_id in (
				    select transfer_schema_object_id from norm_gen.transfer_schema_object
				       where transfer_schema_id=p_transfer_schema_id )
;
/*correctly assign db types for arrays of records */

update norm_gen.transfer_schema_key k 
set db_type_calc =(
select  ob.db_schema||'.'||ob.db_record_type ||'[]'
from norm_gen.transfer_schema_object ob
where ob.transfer_schema_object_id=k.ref_object_id)
	where  t_key_type = $$array$$
   and k.transfer_schema_object_id in (
				    select transfer_schema_object_id from norm_gen.transfer_schema_object
				       where transfer_schema_id=p_transfer_schema_id )
;
return query select * from norm_gen.transfer_schema_key
  where transfer_schema_object_id in (select transfer_schema_object_id
      from norm_gen.transfer_schema_object  where transfer_schema_id =p_transfer_schema_id );
end;$body$;

create or replace function norm_gen.update_db_type (p_transfer_schema_id int)
returns setof norm_gen.transfer_schema_key
language plpgsql
as
$body$
begin
update norm_gen.transfer_schema_key k set 
db_type_calc = (select t.typname  :: text
   from pg_class c 
     JOIN pg_attribute a ON c.oid = a.attrelid and 
        c.relname=k.db_table and attname=k.db_col
        JOIN pg_namespace n ON n.oid = c.relnamespace 
				and n.nspname=(select db_schema from norm_gen.transfer_schema_object
							  where transfer_schema_object_id=k.transfer_schema_object_id )
             join pg_type t on atttypid =t.oid
				)
				where  transfer_schema_object_id in (
				    select transfer_schema_object_id from norm_gen.transfer_schema_object
				    where transfer_schema_id=p_transfer_schema_id )
				    and t_key_type not in  ('array', 'object');
				    
return query select * from norm_gen.transfer_schema_key
  where transfer_schema_object_id in (select transfer_schema_object_id
      from norm_gen.transfer_schema_object  where transfer_schema_id =p_transfer_schema_id );
end;$body$;
