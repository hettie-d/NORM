---insert:

select * from acct_to_db ($$[{
  "username":"johnsmithaccount",
  "first_name":"john",
  "last_name":"smith",
  "dob":"1991-04-01",
   "phones":[{"phone_number":"3123334556", "phone_type_id":"1"}]				
 }]
$$::json)

--update:
select * from acct_to_db ($$[{
   "account_id":1,
   "username":"aliceacct2"}]
 $$::json
)

--update embedded objects:

select * from acct_to_db($$[{
   "account_id":"3",
   "emails":[{"email":"new.email@hotmail.com", 
                                      "email_priority_id":"1"}]
      }]
     $$::json)

--delete:

select * from acct_to_db($$[{
   "account_id":"1",
   "phones":[{"phone_id":"2", "command":"delete"}]
   }]
 $$::json)
