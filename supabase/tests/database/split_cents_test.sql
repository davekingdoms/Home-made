-- split_cents (docs/spec/schema.md, 6): integer part towards zero, missing
-- cents to the largest remainders, ties to the payer, then to the oldest
-- joined_at, then to the smallest id. The same cases go in the Dart tests.
-- Invented members: Anna (a1, joined first), Bruno (b1), Carla (c1).
begin;

create extension if not exists pgtap with schema extensions;

select plan(9);

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
   '00000000-0000-4000-8000-00000000000a', current_date - 60, now() - interval '60 days'),
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 30, now() - interval '30 days'),
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000c', current_date - 10, now() - interval '10 days');

-- Weights 1:1:1 for Anna, Bruno and Carla.
create function pg_temp.equal3()
returns jsonb
language sql
as $$
  select '[{"member_id": "00000000-0000-4000-8000-0000000000a1", "weight": 1},
           {"member_id": "00000000-0000-4000-8000-0000000000b1", "weight": 1},
           {"member_id": "00000000-0000-4000-8000-0000000000c1", "weight": 1}]'::jsonb
$$;

select results_eq(
  $$select member_id, amount_cents
    from public.split_cents(1000, pg_temp.equal3(), '00000000-0000-4000-8000-0000000000b1')
    order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 333::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 334::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, 333::bigint)$$,
  '10,00 at 1:1:1 paid by Bruno: Bruno 3,34, Anna 3,33, Carla 3,33'
);
select results_eq(
  $$select member_id, amount_cents
    from public.split_cents(-1000, pg_temp.equal3(), '00000000-0000-4000-8000-0000000000b1')
    order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, -333::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, -334::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, -333::bigint)$$,
  'an expense splits the same way, with its sign'
);
select results_eq(
  $$select member_id, amount_cents
    from public.split_cents(1, pg_temp.equal3(), '00000000-0000-4000-8000-0000000000c1')
    order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 0::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 0::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, 1::bigint)$$,
  '0,01 among three goes to the payer'
);
select results_eq(
  $$select member_id, amount_cents
    from public.split_cents(2, pg_temp.equal3(), '00000000-0000-4000-8000-0000000000c1')
    order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 1::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 0::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, 1::bigint)$$,
  '0,02 among three: the payer, then the member who joined first'
);
select results_eq(
  $$select member_id, amount_cents
    from public.split_cents(1001,
      '[{"member_id": "00000000-0000-4000-8000-0000000000b1", "weight": 1},
        {"member_id": "00000000-0000-4000-8000-0000000000c1", "weight": 1}]',
      '00000000-0000-4000-8000-0000000000a1')
    order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000b1'::uuid, 501::bigint),
           ('00000000-0000-4000-8000-0000000000c1'::uuid, 500::bigint)$$,
  '"Per Bruno e Carla" paid by Anna: the odd cent goes to who joined first'
);
select results_eq(
  $$select member_id, amount_cents
    from public.split_cents(1000,
      '[{"member_id": "00000000-0000-4000-8000-0000000000a1", "weight": 2},
        {"member_id": "00000000-0000-4000-8000-0000000000b1", "weight": 1}]',
      '00000000-0000-4000-8000-0000000000b1')
    order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 667::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 333::bigint)$$,
  'at 2:1 the larger remainder wins over the payer'
);
select results_eq(
  $$select member_id, amount_cents
    from public.split_cents(999,
      '[{"member_id": "00000000-0000-4000-8000-0000000000a1", "weight": 0.5},
        {"member_id": "00000000-0000-4000-8000-0000000000b1", "weight": 1.5}]',
      '00000000-0000-4000-8000-0000000000b1')
    order by member_id$$,
  $$values ('00000000-0000-4000-8000-0000000000a1'::uuid, 250::bigint),
           ('00000000-0000-4000-8000-0000000000b1'::uuid, 749::bigint)$$,
  'decimal weights: 9,99 at 0,5:1,5'
);
select is_empty(
  $$select a from generate_series(-500, 500) as a
    where a <> 0
      and (select sum(amount_cents) from public.split_cents(a, pg_temp.equal3(),
             '00000000-0000-4000-8000-0000000000a1')) <> a$$,
  'at 1:1:1 the cents always add up to the amount'
);
select is_empty(
  $$select a from generate_series(-500, 500) as a
    where a <> 0
      and (select sum(amount_cents) from public.split_cents(a,
             '[{"member_id": "00000000-0000-4000-8000-0000000000a1", "weight": 1},
               {"member_id": "00000000-0000-4000-8000-0000000000b1", "weight": 2.5},
               {"member_id": "00000000-0000-4000-8000-0000000000c1", "weight": 3.3333}]',
             '00000000-0000-4000-8000-0000000000c1')) <> a$$,
  'at 1:2,5:3,3333 the cents always add up to the amount'
);

select * from finish();
rollback;
