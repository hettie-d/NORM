set search_path to norm;

select * from account_create($${
"username":"johnsmithaccount",
"first_name":"john",
"last_name":"smith",
"dob":"1991-04-01",
"phones":[{"phone":"3123334556", "phone_type_id":"1"}]							 
}
$$::json);

elect * from account_search_by_id(1);


