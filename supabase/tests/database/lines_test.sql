-- Lines and shares (docs/spec/schema.md, 5-8, section 13 "Righe e quote").
-- Invented users: Anna (a1), Bruno (b1, from 30 days ago) and Carla (c1,
-- from 10 days ago) in "Casa di prova". Anna has a bank account; Bruno and
-- Carla only their cash.
begin;

create extension if not exists pgtap with schema extensions;

select plan(45);

create function pg_temp.login(user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, true);
  perform set_config(
    'request.jwt.claims',
    json_build_object('sub', user_id, 'role', 'authenticated')::text,
    true
  );
end;
$$;

create function pg_temp.check_deferred()
returns void
language plpgsql
as $$
begin
  set constraints all immediate;
  set constraints all deferred;
end;
$$;

create function pg_temp.cash_of(member_id uuid)
returns uuid
language sql
security definer
as $$
  select a.id from public.accounts a where a.owner_member_id = cash_of.member_id and a.kind = 'cash'
$$;

create function pg_temp.first_line(transaction_id uuid)
returns uuid
language sql
security definer
as $$
  select l.id from public.transaction_lines l
  where l.transaction_id = first_line.transaction_id and l.position = 1
$$;

create function pg_temp.category(kind text, parent_name text, name text)
returns uuid
language sql
security definer
as $$
  select c.id
  from public.categories c
  left join public.categories p on p.id = c.parent_id
  where c.kind = category.kind
    and c.name = category.name
    and p.name is not distinct from category.parent_name
    and c.archived_at is null
$$;

-- Shares as JSON: weights of Anna, Bruno and Carla (null: no share).
create function pg_temp.shares(anna numeric, bruno numeric, carla numeric)
returns jsonb
language sql
as $$
  select jsonb_agg(jsonb_build_object('member_id', m, 'weight', w))
  from (values
    ('00000000-0000-4000-8000-0000000000a1'::uuid, anna),
    ('00000000-0000-4000-8000-0000000000b1'::uuid, bruno),
    ('00000000-0000-4000-8000-0000000000c1'::uuid, carla)
  ) as t (m, w)
  where w is not null
$$;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000c', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000c', 'Carla');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 60);
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 60, now() - interval '60 days');
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 30, now() - interval '30 days');
insert into public.members (id, household_id, user_id, start_date, joined_at) values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', current_date - 10, now() - interval '10 days');

insert into public.bank_connections (id, member_id, aspsp_name, aspsp_country, uses_global_app, status) values
  ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000a1',
   'Banca di Prova', 'IT', true, 'active');
insert into public.accounts (id, household_id, owner_member_id, kind, connection_id, currency, display_name) values
  ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000a1', 'bank', '00000000-0000-4000-8000-0000000000e1', 'EUR', 'Banca di Prova');

-- Imported by the server: the supermarket 5 days ago, the market 20 days ago.
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, movement_date, amount_cents, currency, counterparty
) values
  ('00000000-0000-4000-8000-000000000101', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000e2', 'bank', '00000000-0000-4000-8000-0000000000a1',
   current_date - 5, -9000, 'EUR', 'Supermercato di prova'),
  ('00000000-0000-4000-8000-000000000103', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-0000000000e2', 'bank', '00000000-0000-4000-8000-0000000000a1',
   current_date - 20, -2000, 'EUR', 'Mercato di prova');
select pg_temp.check_deferred();

-- Anna classifies the supermarket as Cibo > Spesa, shares it with Bruno
-- and splits off 30,00.
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$update public.transaction_lines
    set kind = 'expense', category_id = pg_temp.category('expense', 'Cibo', 'Spesa')
    where id = pg_temp.first_line('00000000-0000-4000-8000-000000000101');
    select public.set_line_shares(pg_temp.first_line('00000000-0000-4000-8000-000000000101'),
                                  pg_temp.shares(1, 1, null));
    select public.split_line(pg_temp.first_line('00000000-0000-4000-8000-000000000101'),
      '[{"id": "00000000-0000-4000-8000-000000000201", "amount_cents": -3000}]');
    select pg_temp.check_deferred()$$,
  'Anna classifies, shares and splits a line'
);

-- split_line
select results_eq(
  $$select id, amount_cents, kind, category_id = pg_temp.category('expense', 'Cibo', 'Spesa')
    from public.transaction_lines
    where transaction_id = '00000000-0000-4000-8000-000000000101'
    order by position$$,
  $$values (pg_temp.first_line('00000000-0000-4000-8000-000000000101'), -6000::bigint, 'expense'::text, true),
           ('00000000-0000-4000-8000-000000000201'::uuid, -3000::bigint, 'expense'::text, true)$$,
  'the line keeps the rest; the new line inherits kind and category; the sum stays the total'
);
select results_eq(
  $$select member_id, weight, amount_cents from public.line_shares
    where line_id = '00000000-0000-4000-8000-000000000201' order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1::numeric, -1500::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 1::numeric, -1500::bigint)$$,
  'the new line inherits the weights'
);
select results_eq(
  $$select member_id, amount_cents from public.line_shares
    where line_id = pg_temp.first_line('00000000-0000-4000-8000-000000000101') order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, -3000::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -3000::bigint)$$,
  'the cents of the line are computed again on the rest'
);
select lives_ok(
  $$select public.split_line(pg_temp.first_line('00000000-0000-4000-8000-000000000101'),
      '[{"id": "00000000-0000-4000-8000-000000000201", "amount_cents": -3000}]');
    select pg_temp.check_deferred()$$,
  'a second call with the same ids succeeds'
);
select is(
  (select count(*)::int from public.transaction_lines
   where transaction_id = '00000000-0000-4000-8000-000000000101'),
  2,
  'and creates nothing'
);
select throws_ok(
  $$select public.split_line(pg_temp.first_line('00000000-0000-4000-8000-000000000101'),
      '[{"id": "00000000-0000-4000-8000-000000000202", "amount_cents": -6000}]')$$,
  'P0001', 'invalid_parts',
  'the line keeps a part of its amount'
);
select throws_ok(
  $$select public.split_line(pg_temp.first_line('00000000-0000-4000-8000-000000000101'),
      '[{"id": "00000000-0000-4000-8000-000000000202", "amount_cents": 100}]')$$,
  'P0001', 'invalid_parts',
  'a part has the sign of the line'
);

-- The new line becomes Anna's only.
select public.set_line_shares('00000000-0000-4000-8000-000000000201', pg_temp.shares(1, null, null));
select pg_temp.check_deferred();

-- Bruno, involved in the first line
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  'select id from public.transaction_lines',
  $$values (pg_temp.first_line('00000000-0000-4000-8000-000000000101'))$$,
  'Bruno sees only the line with his share'
);
select results_eq(
  'select movement_date, counterparty, amount_cents from public.transaction_lines',
  $$values (current_date - 5, 'Supermercato di prova'::text, -6000::bigint)$$,
  'with date, counterparty and amount of the line'
);
select results_eq(
  'select member_id, amount_cents from public.line_shares order by member_id',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, -3000::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -3000::bigint)$$,
  'and its shares'
);
select is_empty('select 1 from public.transactions', 'but not the transaction, so not its total');
select lives_ok(
  $$update public.transaction_lines set category_id = pg_temp.category('expense', 'Cibo', 'Ristoranti')
    where id = pg_temp.first_line('00000000-0000-4000-8000-000000000101');
    select pg_temp.check_deferred()$$,
  'Bruno changes the category'
);
select lives_ok(
  $$select public.set_line_shares(pg_temp.first_line('00000000-0000-4000-8000-000000000101'),
                                  pg_temp.shares(1, 2, null));
    select pg_temp.check_deferred()$$,
  'Bruno changes the shares'
);
select results_eq(
  'select member_id, amount_cents from public.line_shares order by member_id',
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, -2000::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -4000::bigint)$$,
  'the cents follow the new weights'
);
select throws_ok(
  $$update public.transaction_lines set amount_cents = -5000
    where id = pg_temp.first_line('00000000-0000-4000-8000-000000000101')$$,
  '42501', null,
  'Bruno does not change the amount'
);
select throws_ok(
  $$select public.split_line(pg_temp.first_line('00000000-0000-4000-8000-000000000101'),
      '[{"id": "00000000-0000-4000-8000-000000000202", "amount_cents": -1000}]')$$,
  '42501', null,
  'nor splits the line'
);
select throws_ok(
  $$update public.transaction_lines set deleted_at = now()
    where id = pg_temp.first_line('00000000-0000-4000-8000-000000000101')$$,
  '42501', null,
  'nor deletes it'
);

-- Carla, not involved
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select is_empty('select 1 from public.transaction_lines', 'Carla sees no line');
select is_empty('select 1 from public.line_shares', 'and no share');

-- Cents: 10,00 at 1:1:1 paid by Bruno
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values (
  '00000000-0000-4000-8000-000000000104', '00000000-0000-4000-8000-0000000000f1',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
  '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', current_date - 1, -1000, 'EUR'
);
select lives_ok(
  $$select public.set_line_shares(pg_temp.first_line('00000000-0000-4000-8000-000000000104'),
                                  pg_temp.shares(1, 1, 1));
    select pg_temp.check_deferred()$$,
  'Bruno shares 10,00 with everybody'
);
select results_eq(
  $$select member_id, amount_cents from public.line_shares
    where line_id = pg_temp.first_line('00000000-0000-4000-8000-000000000104') order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, -333::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -334::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, -333::bigint)$$,
  'Bruno 3,34, Anna 3,33, Carla 3,33'
);

-- Personal categories and Differenza di cassa
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
insert into public.categories (id, household_id, parent_id, name, kind, scope, owner_member_id)
values ('00000000-0000-4000-8000-0000000000c5', '00000000-0000-4000-8000-0000000000f1',
        pg_temp.category('expense', null, 'Persona'), 'Cosmetici di Anna', 'expense', 'personal',
        '00000000-0000-4000-8000-0000000000a1');
select throws_ok(
  $$update public.transaction_lines set category_id = '00000000-0000-4000-8000-0000000000c5'
    where id = pg_temp.first_line('00000000-0000-4000-8000-000000000101');
    select pg_temp.check_deferred()$$,
  'P0001', 'shared_line_personal_category',
  'a shared line does not take a personal category'
);
select lives_ok(
  $$update public.transaction_lines set category_id = '00000000-0000-4000-8000-0000000000c5'
    where id = '00000000-0000-4000-8000-000000000201';
    select pg_temp.check_deferred()$$,
  'a line of the payer alone takes a personal category'
);
select throws_ok(
  $$select public.set_line_shares('00000000-0000-4000-8000-000000000201', pg_temp.shares(1, 1, null));
    select pg_temp.check_deferred()$$,
  'P0001', 'shared_line_personal_category',
  'a line with a personal category does not become shared'
);
select throws_ok(
  $$update public.transaction_lines
    set category_id = pg_temp.category('expense', 'Varie', 'Differenza di cassa')
    where id = pg_temp.first_line('00000000-0000-4000-8000-000000000101');
    select pg_temp.check_deferred()$$,
  'P0001', 'shared_line_cash_difference',
  'Differenza di cassa is only on lines of the payer alone'
);

-- Start dates: no share before the start date of a member
select throws_ok(
  $$select public.set_line_shares(pg_temp.first_line('00000000-0000-4000-8000-000000000103'),
                                  pg_temp.shares(1, null, 1))$$,
  'P0001', 'member_not_eligible',
  'no share to a member on a line before their start date'
);
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values (
  '00000000-0000-4000-8000-000000000107', '00000000-0000-4000-8000-0000000000f1',
  pg_temp.cash_of('00000000-0000-4000-8000-0000000000a1'), 'manual',
  '00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000a1', current_date - 5, -1200, 'EUR'
);
select public.set_line_shares(pg_temp.first_line('00000000-0000-4000-8000-000000000107'), pg_temp.shares(1, null, 1));
select pg_temp.check_deferred();
select throws_ok(
  $$update public.transactions set movement_date = current_date - 20
    where id = '00000000-0000-4000-8000-000000000107';
    select pg_temp.check_deferred()$$,
  'P0001', 'member_not_eligible',
  'nor moving the date of a shared movement before it'
);

-- Income of Bruno: 5 days after Carla started, and 5 days before.
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
insert into public.transactions (
  id, household_id, account_id, source, paid_by_member_id, entered_by_member_id, movement_date, amount_cents, currency
) values
  ('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
   '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', current_date - 5, 5000, 'EUR'),
  ('00000000-0000-4000-8000-000000000106', '00000000-0000-4000-8000-0000000000f1',
   pg_temp.cash_of('00000000-0000-4000-8000-0000000000b1'), 'manual',
   '00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000b1', current_date - 15, 3000, 'EUR');
update public.transaction_lines set kind = 'income'
  where transaction_id in ('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-000000000106');
select pg_temp.check_deferred();

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select set_eq(
  $$select transaction_id from public.transaction_lines where kind = 'income'$$,
  $$values ('00000000-0000-4000-8000-000000000105'::uuid), ('00000000-0000-4000-8000-000000000106'::uuid)$$,
  'the other members see the income lines of who shows them'
);
select is_empty(
  $$select 1 from public.transactions
    where id in ('00000000-0000-4000-8000-000000000105', '00000000-0000-4000-8000-000000000106')$$,
  'but not their transactions'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000c');
select results_eq(
  $$select transaction_id from public.transaction_lines where kind = 'income'$$,
  $$values ('00000000-0000-4000-8000-000000000105'::uuid)$$,
  'only from the start date of who looks'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
insert into public.user_settings (user_id, show_income) values ('00000000-0000-4000-8000-00000000000b', false);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select is_empty(
  $$select 1 from public.transaction_lines where kind = 'income'$$,
  'with show_income false the income lines stay private'
);

-- Default shares valid at the date of the expense
select results_eq(
  $$select member_id, weight from public.default_shares_at(current_date - 40)$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1::numeric)$$,
  'before Bruno: Anna alone'
);
select results_eq(
  $$select member_id, weight from public.default_shares_at(current_date - 20)$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1::numeric),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 1::numeric)$$,
  'from the start date of Bruno: Anna and Bruno'
);
select results_eq(
  $$select member_id, weight from public.default_shares_at(current_date)$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1::numeric),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 1::numeric),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, 1::numeric)$$,
  'from the start date of Carla: all three'
);

-- Tags
insert into public.tags (id, household_id, name, scope) values
  ('00000000-0000-4000-8000-0000000000e5', '00000000-0000-4000-8000-0000000000f1', 'Viaggio estate', 'shared');
insert into public.tags (id, household_id, name, scope, owner_member_id) values
  ('00000000-0000-4000-8000-0000000000e6', '00000000-0000-4000-8000-0000000000f1', 'Regali di Anna',
   'personal', '00000000-0000-4000-8000-0000000000a1');

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select lives_ok(
  $$insert into public.line_tags (line_id, tag_id)
    values (pg_temp.first_line('00000000-0000-4000-8000-000000000101'), '00000000-0000-4000-8000-0000000000e5');
    select pg_temp.check_deferred()$$,
  'who is involved adds a shared tag'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$insert into public.line_tags (line_id, tag_id)
    values (pg_temp.first_line('00000000-0000-4000-8000-000000000101'), '00000000-0000-4000-8000-0000000000e6');
    select pg_temp.check_deferred()$$,
  'P0001', 'shared_line_personal_tag',
  'a shared line has only shared tags'
);
select lives_ok(
  $$insert into public.line_tags (line_id, tag_id)
    values ('00000000-0000-4000-8000-000000000201', '00000000-0000-4000-8000-0000000000e6');
    select pg_temp.check_deferred()$$,
  'a line of the payer alone takes a personal tag'
);
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  'select tag_id from public.line_tags',
  $$values ('00000000-0000-4000-8000-0000000000e5'::uuid)$$,
  'Bruno sees the tags of his lines only'
);

-- merge_categories moves also the lines the caller does not see.
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
insert into public.categories (id, household_id, parent_id, name, kind, scope)
values ('00000000-0000-4000-8000-0000000000c7', '00000000-0000-4000-8000-0000000000f1',
        pg_temp.category('expense', null, 'Cibo'), 'Spesa bio', 'expense', 'shared');
update public.transaction_lines set category_id = '00000000-0000-4000-8000-0000000000c7'
  where id = pg_temp.first_line('00000000-0000-4000-8000-000000000103');
select pg_temp.login('00000000-0000-4000-8000-00000000000b');
update public.transaction_lines set category_id = '00000000-0000-4000-8000-0000000000c7'
  where id = pg_temp.first_line('00000000-0000-4000-8000-000000000104');
select pg_temp.check_deferred();

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$select public.merge_categories('00000000-0000-4000-8000-0000000000c7',
                                   pg_temp.category('expense', 'Cibo', 'Spesa'));
    select pg_temp.check_deferred()$$,
  'a member merges two categories'
);
select throws_ok(
  $$select public.merge_categories(pg_temp.category('expense', 'Varie', 'Differenza di cassa'),
                                   pg_temp.category('expense', 'Varie', 'Varie'))$$,
  'P0001', 'category_not_mergeable',
  'Differenza di cassa is never merged'
);

reset role;
select results_eq(
  $$select transaction_id from public.transaction_lines
    where category_id = pg_temp.category('expense', 'Cibo', 'Spesa') order by transaction_id$$,
  $$values ('00000000-0000-4000-8000-000000000103'::uuid), ('00000000-0000-4000-8000-000000000104'::uuid)$$,
  'every line moves, also the one of Bruno that Anna does not see'
);
select results_eq(
  $$select archived_at is not null, merged_into_id = pg_temp.category('expense', 'Cibo', 'Spesa')
    from public.categories where id = '00000000-0000-4000-8000-0000000000c7'$$,
  $$values (true, true)$$,
  'the merged category is archived'
);

-- A member who left gets no new share.
update public.members set left_at = now() where id = '00000000-0000-4000-8000-0000000000c1';
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select throws_ok(
  $$select public.set_line_shares(pg_temp.first_line('00000000-0000-4000-8000-000000000107'),
                                  pg_temp.shares(1, null, 1))$$,
  'P0001', 'member_not_eligible',
  'no share to a member who left'
);

-- Not signed in
reset role;
set local role anon;
select throws_ok(
  'select id from public.transaction_lines',
  '42501', null,
  'anon cannot read lines'
);

select * from finish();
rollback;
