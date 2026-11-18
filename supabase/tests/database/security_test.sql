-- Rules that hold for the whole public schema (docs/spec/schema.md, 1):
-- RLS on every table, nothing for anon, functions with an empty search_path,
-- touch_row on every table with a version. The list of the functions the
-- app may call grows with the schema.
begin;

create extension if not exists pgtap with schema extensions;

select plan(6);

select is_empty(
  $$select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p')
      and not c.relrowsecurity$$,
  'RLS is enabled on every table'
);

select is_empty(
  $$select c.relname from pg_class c
    where c.relnamespace = 'public'::regnamespace
      and c.relkind in ('r', 'p', 'v', 'm')
      and (has_table_privilege('anon', c.oid, 'select, insert, update, delete, truncate, references, trigger')
        or has_any_column_privilege('anon', c.oid, 'select, insert, update, references'))$$,
  'anon has no privilege on any table'
);

select is_empty(
  $$select p.proname from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and has_function_privilege('anon', p.oid, 'execute')$$,
  'anon executes no function'
);

select set_eq(
  $$select p.proname::text from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and has_function_privilege('authenticated', p.oid, 'execute')$$,
  array[
    'current_member_id', 'current_household_id', 'is_household_member',
    'max_household_members', 'create_household', 'create_invite',
    'invite_preview', 'redeem_invite', 'set_my_start_date',
    'is_account_owner', 'can_see_transaction', 'can_see_line', 'can_edit_line',
    'can_see_installment_plan', 'set_line_shares', 'split_line',
    'default_shares_at', 'set_default_shares', 'merge_categories',
    'set_initial_balances', 'member_balances', 'is_piggy_bank_member'
  ],
  'the app calls only the support and RPC functions'
);

select is_empty(
  $$select p.proname from pg_proc p
    where p.pronamespace = 'public'::regnamespace
      and (p.proconfig is null or not p.proconfig @> array['search_path=""'])$$,
  'every function has an empty search_path'
);

select is_empty(
  $$select c.table_name from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'version'
      and not exists (
        select 1 from pg_trigger t
        where t.tgrelid = format('public.%I', c.table_name)::regclass
          and t.tgfoid = 'public.touch_row'::regproc
      )$$,
  'every table with a version has the touch_row trigger'
);

select * from finish();
rollback;
