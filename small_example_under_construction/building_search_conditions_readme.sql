--
---search JSON structure 
--
/*
There are several ways to pass search parameters to the *_search_generic functions.
You can pass them on the top level of json, and if the keys are unique across json (i.e., 
there are no keys with the same name on different levels of hierarhy) NORM_GEN will 
identify the right object and generate a correstponding selection criterion.

Alternatively, you can explicitly place a condition on the proper level of hierarhy.
For example, compare different ways of setting up condition on the phone table 
(phone_type and phone_number).

If no operation is specifies, the condition is set to '=', otherwise, you can 
specify one of the following:

$eq   =     
$lt   <     
$le  <=     
$ne  <>     
$ge  >=     
$gt   >     
$like  LIKE 

*/
---example of the call
--
select acct_from_db($${"user_account":{
"phone_type":"cell", 
"email_priority":"primary",
"account":{"last_name":"johns",
     "emails":{"email_address":{"$like":"%gmail%"}},
     "dob":{"$gt":"1901-01-01"},
     "phones":{"phone_number":{"$like":"312%"}}
     }}
}$$::json);
---
---The SELECT statement generated during this call"
---
/* selecting User account account */
 select  
           array_agg( 
    /* Entering account_record */
    row(top.account_id  ,
    top.username  ,
    top.last_name  ,
    top.first_name  ,
    top.dob  ,
       (
    select array_agg(  /* Entering email_record */
    row(emails.email  ,
    emails.email_id  ,
    ep.email_priority  ,
    emails.email_priority_id)::norm.email_record)  
from  norm.email  emails 
   join norm.email_priority ep on  ep.email_priority_id = emails.email_priority_id 
where  top.account_id = emails.account_id
)
  ,
       (
    select array_agg(  /* Entering phone_record */
    row(phones.phone_id  ,
    pt.phone_type  ,
    phones.phone  ,
    phones.phone_type_id)::norm.phone_record)  
from  norm.phone  phones 
   join norm.phone_type pt on  pt.phone_type_id = phones.phone_type_id 
where  top.account_id = phones.account_id
)
)::norm.account_record)  
from  norm.account  top   where  account_id IN (
   select account_id from norm.phone where
    phone_id IN (
   select phone_type_id from norm.phone_type where
    phone_type  =  ('cell'::text) ) 
AND  phone  LIKE  ('312%'::text) ) 
AND  account_id IN (
   select account_id from norm.email where
    email_id IN (
   select email_priority_id from norm.email_priority where
    email_priority  =  ('primary'::text) ) 
AND  email  LIKE  ('%gmail%'::text) ) 
AND  dob  >  ('1901-01-01'::date)  AND  last_name  =  ('johns'::text) 
