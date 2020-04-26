set search_path to norm;

drop type if exists phone_record cascade ;
create type phone_record as (
                  phone_id  bigint,
                  phone_number  text,
                  phone_type_id int,
                  phone_type   text);
drop type if exists email_record cascade;
create type email_record as(
                  email_id bigint,
                  email_priority_id int,
                  email_priority text,
                  email_address text);
                  account_number  text);
 drop type if exists account_record cascade;
 create type account_record as (
                account_id  bigint,
                username text,
                first_name text,
                last_name text,
                dob date,
                phones phone_record[],
                email_addresses email_record[]
                );
                
create or replace function account_create(
    p_object json
    returns setof text
    language 'plpgsql'
as $BODY$

declare
v_rec record;
v_account_id bigint;
v_account_rec account_record;
v_phones_array text;
v_phone_rec record;
v_phone_id bigint;
v_emails_array text;
v_email_rec record;
v_email_id bigint;
begin
for v_rec in
 (select * from json_each_text(p_object) )
 loop
  case 
  when v_rec.key ='username' then v_account_rec.username:=v_rec.value;
  when v_rec.key ='last_name' then v_account_rec.last_name:=v_rec.value;
  when v_rec.key ='first_name' then v_account_rec.first_name:=v_rec.value;
  when v_rec.key ='dob' then v_account_rec.dob:=v_rec.value;
  when v_rec.key='phones' then  v_phones_array:=v_rec.value;
  when v_rec.key ='email_addresses' v_emails_array:=v_rec.value;
  else null;
end  case;
end loop;
---create account
insert into account (username, last_name, first_name, dob)
  values (v_account_rec.username, v_account_rec.last_name, v_account_rec.first_name, v_account_rec.dob)
    returning account_id into v_account_id;
--create phones
for v_phone_rec in (select * from json_to_recordset(v_phones_array::json)
                     as phone(phone_number text, phone_type_id int ) 
                     ) loop
            insert into phone (account_id, phone, phone_type_id)  
                values (v_account_id,  v_phone_rec.phone_number, v_phone_rec.phone_type_id);    
end  loop;
--create emails
for v_email_rec in (select * from json_to_recordset(v_emails_array::json)
                     as email(email_address text, email_priority_id int ) 
                     ) loop
            insert into email (account_id, email, email_priority_id)  
                values (v_account_id,  v_email_rec.email_addressr, v_email_rec.email_priority_id);    
end  loop;

return query (
select * from array_transport(account_search($$a.account_id=$$||quote_literal(v_account_id))));
end;

$BODY$;


                  
