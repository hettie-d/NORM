set searchpath to norm;
insert into norm.account(username, first_name, last_name, dob)
values ('aliceacct1', 'alice','johns','1996-04-01');

insert into norm.account(username, first_name, last_name, dob)
values ('bobacct2', 'bob','johnson','1989-04-01');

insert into norm.account(username, first_name, last_name, dob)
values ('smithalice', 'alice','smith','1998-12-31');

insert into email (account_id, email, email_priority_id)
values (1, 'alicejons@gmail.com',1);

insert into email(account_id, email, email_priority_id)
values (2,'johnsonbs@hotmail.com',1);

insert into phone (account_id, phone, phone_type_id)
values (1, '2021234567',2);
insert into phone (account_id, phone, phone_type_id)
values (1, '3121233344',2);

