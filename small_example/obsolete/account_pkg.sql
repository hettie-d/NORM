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
	              email  text,
                  email_priority_id int,
                  email_priority text);
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
    p_object json)
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
  when v_rec.key ='email_addresses' then v_emails_array:=v_rec.value;
  else null;
end  case;
end loop;
---create account
insert into account (username, last_name, first_name, dob)
  values (v_account_rec.username, v_account_rec.last_name, v_account_rec.first_name, v_account_rec.dob)
    returning account_id into v_account_id;
--create phones
for v_phone_rec in (select * from json_to_recordset(v_phones_array::json)
                     as phone(phone text, phone_type_id int ) 
                     ) loop
            insert into phone (account_id, phone, phone_type_id)  
                values (v_account_id,  v_phone_rec.phone, v_phone_rec.phone_type_id);    
end  loop;
--create emails
for v_email_rec in (select * from json_to_recordset(v_emails_array::json)
                     as email(email_address text, email_priority_id int ) 
                     ) loop
            insert into email (account_id, email, email_priority_id)  
                values (v_account_id,  v_email_rec.email_addressr, v_email_rec.email_priority_id);    
end  loop;

return query (
select * from array_transport(account_search_by_id(v_account_id)));
end;

$BODY$;

create or replace function account_search_by_id(p_account_id bigint)
returns account_record[]
  language 'plpgsql'
as $BODY$
declare
v_result account_record[];
v_sql text;
begin
select array_agg(single_item)
  from
  (select
     row (account_id ,
          username,
          first_name,
          last_name,
          dob ,
          (select array_agg(row(phone_id,
                        phone,
                        p.phone_type_id,
                        phone_type )::phone_record)
                        from phone p 
                             join phone_type pt using(phone_type_id)
                         where p.account_id=a.account_id),
           (select array_agg(row(email_id,
                        email,
                        e.email_priority_id,
                        email_priority )::email_record)
                        from email e 
                             join email_priority ep using(email_priority_id)
                         where e.account_id=a.account_id)
                         )::account_record as single_item 
           from account a 
              where a.account_id=p_account_id )s
         into v_result;
    return (v_result);
  
end;
$BODY$;    

create or replace function account_select_by_id(p_account_id bigint)
returns setof text
language 'plpgsql'
as
$BODY$
begin
return query (
select * from array_transport(account_search_by_id(p_account_id)));
end;

$BODY$; 


--set search_path to norm;

create or replace function account_search(p_search_json json)
returns account_record[]
  language 'plpgsql'
as $BODY$
declare
v_search_condition text:=null;
--v_json_rec account_record;
v_sql text;
result account_record[];
v_rec record;
v_where_account text;
v_where_email text;
v_where_phone text;
v_result account_record[];
begin
for v_rec in	
 (select * from json_each_text(p_search_json) )
 loop
  case when v_rec.key in ('last_name', 'first_name','username') then
              if v_where_account is null  
                 then v_where_account:=v_rec.key ||' like '|| quote_literal(v_rec.value||'%' ); 
                    else v_where_account:=v_where_account ||' and ' 
                    ||v_rec.key ||' like '|| quote_literal(v_rec.value||'%' ); 
                  end if;
       when v_rec.key ='account_id' then 
             if v_where_account is null  
                 then v_where_account:='a1.account_id='|| v_rec.value;
                    else v_where_account:=v_where_account ||' and ' 
                    ||v_rec.key ||'='|| v_rec.value;     
                  end if;
     when v_rec.key = 'phone' then
            v_where_phone :=' phone like '|| quote_literal(v_rec.value||'%' ) ;
     when v_rec.key = 'email' then
            v_where_email :=' email like '|| quote_literal(v_rec.value||'%' ) ;
    else null;
  end case; 
  end loop; 
v_search_condition:=concat_ws(' intersect ',  
$$select a1.account_id from account a1
  where $$||
  v_where_account,
 $$select account_id from phone where $$ ||
    v_where_phone ,
    $$select account_id from email
where $$||
v_where_email);

v_sql:=$sql$
select array_agg(single_item)
  from
  (select
     row (account_id ,
          username,
          first_name,
          last_name,
          dob ,
          (select array_agg(row(phone_id,
                        phone,
                        p.phone_type_id,
                        phone_type )::phone_record)
                        from phone p 
                             join phone_type pt using(phone_type_id)
                         where p.account_id=a.account_id),
           (select array_agg(row(email_id,
                        email,
                        e.email_priority_id,
                        email_priority )::email_record)
                        from email e 
                             join email_priority ep using(email_priority_id)
                         where e.account_id=a.account_id)
                         )::account_record as single_item 
           from account a 
              where a.account_id in (
              $sql$||
              v_search_condition||
				  $sql$
              )
               )s
$sql$;

execute v_sql into v_result;
return (v_result);
  
end;
$BODY$; 

create or replace function account_select(p_search_json json)
returns setof text
language 'plpgsql'
as
$BODY$
begin
return query (
select * from array_transport(account_search(p_search_json)));
end;

$BODY$; 


--set search_path to norm
create or replace function account_update(
    p_object json,
    p_account_id bigint)
    returns setof text
    language 'plpgsql'
as $BODY$

declare
v_rec record;
v_account_update text;
v_phones_array text;
v_phone_rec record;
v_phone_each record;
v_phone_id bigint;
v_command text;
v_phone_update text;
v_emails_array text;
v_email_rec record;
v_email_each record;
v_email_id bigint;
v_email_update text;
begin
for v_rec in
 (select * from json_each_text(p_object) )
 loop
  case 
  when v_rec.key in ('username','last_name','first_name','dob')
     then v_account_update:=concat_ws(', ', v_account_update,v_rec.key||'='||quote_literal(v_rec.value)) ;
  when v_rec.key='phones' then  v_phones_array:=v_rec.value;
  when v_rec.key ='email_addresses' then v_emails_array:=v_rec.value;
  else null;
end  case;
end loop;
---update account
if v_account_update is not null then
   execute  ($$update account set $$|| v_account_update||$$
    where account_id=$$||p_account_id::text);
   end if; 
 --update/insert/delete phones
for v_phone_rec in (select  * from json_array_elements_text(v_phones_array::json) ) loop
   ---for each phone record
   if v_phone_rec is not NULL then
       v_phone_id:=null;
       v_command :=null;
       v_phone_update:=null;
    for v_phone_each in (select * from json_each_text(v_phone_rec.value::json))
     loop
     case 
     when v_phone_each.key='phone_id' then  v_phone_id:=v_phone_each.value;
     when v_phone_each.key='command' then v_command:=v_phone_each.value;
     when v_phone_each.key in ('phone', 'phone_type_id')
       then v_phone_update:=concat_ws(', ',v_phone_update,v_phone_each.key||'='||quote_literal(v_phone_each.value)) ;
    else null;
  end case;
 end loop; --for each phone jso
   if lower(v_command )= 'delete' and v_phone_id is not null
    then delete from phone where phone_id=v_phone_id;
    end if;
   if v_phone_id is null
     then insert into phone (account_id) 
             values (p_account_id) returning phone_id into v_phone_id;
   end if;
   if v_phone_update is not null then
   execute ($$update phone set $$||v_phone_update||$$
                 where phone_id=$$||v_phone_id::text)  ;
   end if;--update
   end if;---if phone exists
end loop; ---for all phones


--update/insert/delete emails
for v_email_rec in (select  * from json_array_elements_text(v_emails_array::json) ) loop
   ---for each email record
   if v_email_rec is not NULL then
       v_email_id:=null;
       v_command :=null;
       v_email_update:=null;
    for v_email_each in (select * from json_each_text(v_email_rec.value::json))
     loop
     case 
     when v_email_each.key='phone_id' then  v_email_id:=v_email_each.value;
     when v_email_each.key='command' then v_command:=v_email_each.value;
     when v_email_each.key in ('email', 'email_priority_id')
       then v_email_update:=concat_ws(', ',v_email_update,v_email_each.key||'='||quote_literal(v_email_each.value)) ;
    else null;
  end case;
 end loop; --for each phone jso
   if lower(v_command )= 'delete' and v_email_id is not null
    then delete from email where email_id=v_email_id;
    end if;
   if v_email_id is null
     then insert into email (account_id) 
             values (p_account_id) returning email_id into v_email_id;
   end if;
   if v_email_update is not null then
   execute ($$update email set $$||v_email_update||$$
                 where email_id=$$||v_email_id::text)  ;
   end if;--update
   end if;---if email exists
end loop; ---for all emails

return query (
select * from array_transport(account_search_by_id(p_account_id)));
end;

$BODY$;
                  
