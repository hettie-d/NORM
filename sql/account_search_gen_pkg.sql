create or replace function norm.account_format()
returns text
language sql as
$body$
select 
$$select array_agg(single_item)
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
                        phone_type )::norm.phone_record)
                        from norm.phone p 
                             join norm.phone_type pt using(phone_type_id)
                         where p.account_id=a.account_id),
           (select array_agg(row(email_id,
                        email,
                        e.email_priority_id,
                        email_priority )::norm.email_record)
                        from norm.email e 
                             join norm.email_priority ep using(email_priority_id)
                         where e.account_id=a.account_id)
                         )::norm.account_record as single_item 
           from norm.account a 
              where $$;
  $body$;            
              
create or replace function account_search_by_ids(p_account_ids bigint[])
returns account_record[]
  language 'plpgsql'
as $BODY$
declare
v_result account_record[];
v_sql text;
begin
v_sql:=norm.account_format()||$$ a.account_id in ($$ ||array_to_string(p_account_ids,',')||$$) )s
$$;
  execute v_sql into v_result;
    return (v_result);
  
end;
$BODY$; 

---schema is not defined ----
create or replace function account_search_json(p_json json)
returns account_record[]
language 'plpgsql'
as $BODY$
declare
v_result account_record[];
v_sql text;
v_transfer_schema_id int;
begin
select transfer_schema_id into	v_transfer_schema_id from norm_gen.transfer_schema 
       where transfer_schema_name='User account';
v_sql:=norm.account_format()||
     norm_gen.build_conditions(v_transfer_schema_id, p_json)
||$$) s
$$;
  execute v_sql into v_result;
    return (v_result);

end;
$BODY$