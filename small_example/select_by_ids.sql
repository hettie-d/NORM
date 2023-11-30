/*
The function returns all data related to accounts listed in the array of account_id values passed as an argument.  The list of account_id values should be produced within another SQL statement(s). In the example such SQL statement is embedded into the function call and returns an array of all IDs found in the account table.  The output is additionally processed with jsonb_pretty function to meke the output readable.
*/

select  jsonb_pretty(to_jsonb(
 norm_small.acct_select_by_ids(
(select array_agg(account_id) from account)
)));

--- Same function with explicit list of IDs

select  jsonb_pretty(to_jsonb(
 norm_small.acct_select_by_ids(array[1,3])));
