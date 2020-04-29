set search_path to norm;

select * from account_create($${
"username":"johnsmithaccount",
"first_name":"john",
"last_name":"smith",
"dob":"1991-04-01",
"phones":[{"phone":"3123334556", "phone_type_id":"1"}]							 
}
$$::json);

select * from account_search_by_id(1);
select * from account_select_by_id(1);

select * from account_select('{"last_name":"john", "username":"ali"}'::json);
select * from account_select('{"last_name":"john"}'::json)
select * from account_select('{"last_name":"john", "username":"john"}'::json)
select * from account_select('{"first_name":"john", "username":"john"}'::json)
select * from account_select('{"username":"alic","phone":"202"}'::json)
select * from account_select('{"phone":"202"}'::json);
select * from account_select('{"last_name":"john", "email":"john"}'::json)



