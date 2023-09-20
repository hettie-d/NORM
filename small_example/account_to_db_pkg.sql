set search_path to norm;
drop type if exists phone_record_in cascade ;
create type phone_record_in as (
                  phone_id  bigint,
                  phone_number  text,
                  phone_type_id int,
                  command text);
drop type if exists email_record_in cascade;
create type email_record_in as(
                  email_id bigint,
	                email  text,
                  email_priority_id int,
                  command text);
drop type if exists account_record_in cascade;
 create type account_record_in as (
                account_id  bigint,
                username text,
                first_name text,
                last_name text,
                dob date,
                phones phone_record_in[],
                email_addresses email_record_in[],
                command text
                );
create type phone_record_in_array  as (phones_array phone_record_in[]);
create type email_record_in_array  as (emails_array email_record_in[]);

create or replace function norm.account_to_db (
   p_json json) returns jsonb
  language SQL
  as
  $body$
with 
 parsed_input as materialized (
 select * 
   from  json_populate_recordset (NULL::account_record_in,p_json)
   ),
unnested_input_phone_record as (
   select  i.account_id,  
           i.username,
           i.first_name,
           i.last_name,
           i.dob,
           i.command as a_cmd,
           p.phone_id,
           p.phone_number,
           p.phone_type_id,
           p.command as p_cmd
    from parsed_input i,   
         unnest (i.phones) p
    where i.phones is not null
),
unnested_input_email_record as (
   select  i.account_id,  
           i.username,
           i.first_name,
           i.last_name,
           i.dob,
           i.command as a_cmd,        
           e.email_id,
	         e.email,
           e.email_priority_id,
           e.command as e_cmd
    from parsed_input i,   
         unnest (i.emails) e
    where i.emails is not null
),

parsed_deep_account as materialized (
/* Should be created for each parent node in the hierarchy   */
/* Contains all rows with NULL in parent_ID */
/* all columns of parent (including arrays */
select  
     i.username,
     i.first_name,
     i.last_name,
     i.dob,
     i.phones,
     i.emails 
 from parsed_input i
    where i.account_id  is null and 
    (i.phones is not null or i.emails is not null) 
),
insert_new_parent as (
/*  For each parent in the hierarchy */
insert into account (
   username, 
   first_name,
   last_name,
   dob     
   )
 select
   username, 
   first_name,
   last_name,
   dob
 from parsed_deep_account i 
returning account_id
),
parent_link_phones as materialized (
/* for each edge (parent-child) in the hierarchy  */
   (select account_id,
	       phone_id,
           phone_number,
           phone_type_id 
     from rows from  
     (unnest (
        (select array_agg(account_id)  
           from insert_new_parent)
           ),
            unnest (
                   /* array of phones arrays */
                   (select array_agg(row(phones)::phone_record_in_array) 
              from parsed_deep_account )
                    )         
        )  n(account_id, phones),
       unnest (n.phones) u
    ) 
  UNION ALL
  /* Pre-existing parernts with new phones */
  (select  
      account_id, 
      phone_id,
      phone_number,
      phone_type_id
   from unnested_input_phone_record p
     where account_id is not null)
   ),
insert_deep_phone as (
/* use output as "insert_parent" for next level */
insert into phone ( 
      account_id, 
      phone,
      phone_type_id
      ) 
select 
      account_id, 
      phone_number,
      phone_type_id 
  from parent_link_phones 
  where phone_id is null
     returning account_id, phone_id
),
parent_link_emails as materialized (
/* for each edge (parent-child) in the hierarchy  */
   (select account_id, 
	      email_id,
	      email,
           email_priority_id 
     from rows from  
     (unnest (
        (select array_agg(account_id)  
           from insert_new_parent)
           ),
          unnest (
                   (select array_agg(row(emails)::email_record_in_array) emails
                     from parsed_deep_account
                     )
                    ) 
        )  n(account_id, emails),
       unnest (n.emails) u
    ) 
  UNION ALL
  (select  
      account_id, 
      email_id,
	  email,
      email_priority_id
   from unnested_input_email_record
     where account_id is not null)
   ),
insert_deep_email as (
/* use output as "insert_parent" for next level */
insert into email ( 
      account_id,
	    email,
      email_priority_id
      ) 
select 
      account_id,
	  email,
      email_priority_id
  from parent_link_emails 
  where email_id is null
     returning account_id, email_id
),
insert_flat as (
/* root rows without descendents */
insert into account (
   username, 
   first_name,
   last_name,
   dob     
   )
 select
   username, 
   first_name,
   last_name,
   dob
 from parsed_input i 
 where account_id is null 
       and phones is null
       and emails is null
returning account_id
),
/* delete is needed for each node */
delete_phone as (
  delete from  phone
  where phone_id  in (
     select phone_id from unnested_input_phone_record
     where a_cmd='d'   /* cascade  */
           or p_cmd='d')
     returning account_id, phone_id
     ),
delete_email as (
  delete from  email
  where email_id  in (
     select email_id from unnested_input_email_record
     where a_cmd='d'  /* cascade  */
           or e_cmd='d')
     returning account_id, email_id
     ),     
delete_account as (
  delete from  account
  where account_id in (
     select account_id 
     from parsed_input  
     where  command='d')
  returning account_id
),

/* update is needed for each node */
update_account as (
   update account as a set
      username   = coalesce(i.username  , a.username ),
      last_name  = coalesce(i.last_name , a.last_name) ,
      first_name = coalesce(i.first_name, a.first_name),
      dob        = coalesce(i.dob       , a.dob       )      
   from parsed_input i where i.account_id=a.account_id
   returning a.account_id
   ),
update_phone as (
    update phone as p set       
      phone  = coalesce(i.phone_number ,p.phone ),
      phone_type_id = coalesce(i.phone_type_id,p.phone_type_id)
    from unnested_input_phone_record i where i.phone_id=p.phone_id
    returning p.account_id, p.phone_id
    ),
 update_email as (
    update email as e set       
      email             = coalesce(i.email             ,e.email           ),
      email_priority_id = coalesce(i.email_priority_id ,e.email_priority_id)
    from unnested_input_email_record i 
    where i.email_id=e.email_id
    returning e.account_id, e.email_id
    ),
   
run_all as (
select 'insert deep phone', account_id, phone_id, null::int as email_id, null::int as cnt  from insert_deep_phone
union all select 'insert deep phone count', null, null, null, count(*) from insert_deep_phone
union all select 'insert deep email', account_id, null, email_id, null::int as cnt  from insert_deep_email
union all select 'insert deep email count', null, null,  null, count(*) from insert_deep_email
union all  select 'insert account', account_id, null, null, null  from insert_flat
union all  select 'insert account count', null, null, null, count(*) from insert_flat
union all  select 'delete phone', account_id, phone_id, null, null   from delete_phone
union all  select 'delete phone count', null, null, null,   count(*) from delete_phone
union all  select 'delete email', account_id, null, email_id, null  from delete_email
union all  select 'delete email count', null, null, null, count(*) from delete_email
union all  select 'delete account', account_id, null, null, null  from delete_account
union all  select 'delete count count', null, null, null, count(*) from delete_account
union all select 'update account', account_id, null, null, null  from update_account
union all select 'update account count', null, null, null, count(*) from update_account
union all select 'update phone', account_id, phone_id, null, null  from update_phone
union all select 'update phone count', null, null, null, count(*) from update_phone
union all select 'update email', account_id, null, email_id, null  from update_email
union all select 'update email count', null, null, null, count(*) from update_email
),
filtering_conditions as (
   select 
     distinct account_id 
   from run_all 
   where account_id is not null
   ),
build_feedback  as (
  select   
    to_jsonb  (account_search_by_ids(array_agg ( account_id)))
    from filtering_conditions
   )
select * from   build_feedback;
$body$;

