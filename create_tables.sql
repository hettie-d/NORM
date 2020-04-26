drop schema if exists norm cascade;
create schema norm;
set search_path to norm;

--
create table account(
account_id bigserial,
username text,
last_name text,
first_name text,
dob date,
 constraint account_pk primary key (account_id)
);

create table phone_type (
phone_type_id int,
phone_type text,
constraint phone_type_pk primary key(phone_type_id)
);

insert into phone_type values
(1,'home'),
(2,'cell'),
(3,'work');


create table phone (
phone_id bigserial,
phone_type_id int,
phone text,
account_id bigint,
constraint phone_pk  primary key(phone_id),
constraint phone_phone_type_id_fk  foreign key (phone_type_id) references phone_type (phone_type_id),
constraint phone_account_id_fk  foreign key (account_id) references account(account_id)
);


create table email_priority (
email_priority_id int,
email_priority text,
constraint email_priority_pk  primary key(email_priority_id)
);

insert into email_priority values
(1,'primary'),
(2,'secondary');


create table email(
email_id bigserial,
email_priority_id int,
email text,
account_id bigint,
constraint email_pk primary key(email_id),
constraint email_email_priority_id_fk  foreign key (email_priority_id) references email_priority (email_priority_id),
constraint email_account_id_fk  foreign key (account_id) references account(account_id)
);



