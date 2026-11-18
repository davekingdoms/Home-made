-- Categories and tags: the initial list, shared and personal, unique names,
-- system categories, promotion. Invented users: Anna (a) and Bruno (b) in
-- "Casa di prova", Dario (d) alone in his household.
begin;

create extension if not exists pgtap with schema extensions;

select plan(38);

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

-- Id of a category of "Casa di prova" by kind, parent name and name.
create function pg_temp.category(kind text, parent_name text, name text)
returns uuid
language sql
security definer
as $$
  select c.id
  from public.categories c
  left join public.categories p on p.id = c.parent_id
  where c.household_id = '00000000-0000-4000-8000-0000000000f1'
    and c.kind = category.kind
    and c.name = category.name
    and p.name is not distinct from category.parent_name
    and c.archived_at is null
$$;

insert into auth.users (id, aud, role) values
  ('00000000-0000-4000-8000-00000000000a', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000b', 'authenticated', 'authenticated'),
  ('00000000-0000-4000-8000-00000000000d', 'authenticated', 'authenticated');
insert into public.profiles (id, display_name) values
  ('00000000-0000-4000-8000-00000000000a', 'Anna'),
  ('00000000-0000-4000-8000-00000000000b', 'Bruno'),
  ('00000000-0000-4000-8000-00000000000d', 'Dario');
insert into public.households (id, name, start_date) values
  ('00000000-0000-4000-8000-0000000000f1', 'Casa di prova', current_date - 60),
  ('00000000-0000-4000-8000-0000000000f2', 'Casa di Dario', current_date - 60);
insert into public.members (id, household_id, user_id, start_date) values
  ('00000000-0000-4000-8000-0000000000a1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000a', current_date - 60),
  ('00000000-0000-4000-8000-0000000000b1', '00000000-0000-4000-8000-0000000000f1',
   '00000000-0000-4000-8000-00000000000b', current_date - 60),
  ('00000000-0000-4000-8000-0000000000d1', '00000000-0000-4000-8000-0000000000f2',
   '00000000-0000-4000-8000-00000000000d', current_date - 60);

-- Structure
select has_table('public', 'categories', 'categories exists');
select has_table('public', 'tags', 'tags exists');
select policies_are(
  'public', 'categories',
  array['categories_select_visible', 'categories_insert_visible', 'categories_update_visible'],
  'categories has select, insert and update policies, no delete'
);

-- The initial list (categorie.md, 7 and 8)
select results_eq(
  $$select kind, count(*)::int from public.categories
    where household_id = '00000000-0000-4000-8000-0000000000f1' and parent_id is null
    group by kind order by kind$$,
  $$values ('expense'::text, 12), ('income'::text, 5)$$,
  'twelve expense macros and five income ones'
);
select results_eq(
  $$select c.name from public.categories c
    join public.categories p on p.id = c.parent_id
    where c.household_id = '00000000-0000-4000-8000-0000000000f1' and p.name = 'Casa'
    order by c.position$$,
  $$values ('Mutuo'::text), ('Assicurazioni casa e mutuo'), ('Luce'), ('Gas'), ('Acqua'),
           ('Condominio'), ('Internet'), ('Manutenzione e riparazioni'),
           ('Arredo ed elettrodomestici'), ('Pulizia e detersivi'), ('Tasse casa'), ('Giardinaggio')$$,
  'the subcategories of Casa, in order'
);
select results_eq(
  $$select c.name from public.categories c
    join public.categories p on p.id = c.parent_id
    where c.household_id = '00000000-0000-4000-8000-0000000000f1' and p.name = 'Viaggi'
    order by c.position$$,
  $$values ('Trasporto'::text), ('Alloggio')$$,
  'Viaggi has only Trasporto and Alloggio'
);
select set_eq(
  $$select name from public.categories
    where household_id = '00000000-0000-4000-8000-0000000000f1' and deductible_730_default$$,
  $$values ('Salute'::text), ('Farmaci'), ('Visite ed esami'), ('Ottico'), ('Veterinario'), ('Tasse universitarie')$$,
  'the 730 flag on Salute, Animali > Veterinario and Formazione > Tasse universitarie'
);
select results_eq(
  $$select c.kind, p.name, c.name, c.scope from public.categories c
    join public.categories p on p.id = c.parent_id
    where c.household_id = '00000000-0000-4000-8000-0000000000f1' and c.system_key = 'cash_difference'
    order by c.kind$$,
  $$values ('expense'::text, 'Varie'::text, 'Differenza di cassa'::text, 'shared'::text),
           ('income', 'Varie', 'Differenza di cassa', 'shared')$$,
  'two Differenza di cassa, under the expense and the income Varie'
);
select results_eq(
  $$select name from public.categories
    where household_id = '00000000-0000-4000-8000-0000000000f1' and kind = 'income' and parent_id is null
    order by position$$,
  $$values ('Stipendio'::text), ('Rendimenti'), ('Vendite usato'), ('Regali ricevuti'), ('Varie')$$,
  'the income categories, in order'
);

-- Shared and personal
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');

select lives_ok(
  $$insert into public.categories (id, household_id, parent_id, name, kind, scope, owner_member_id)
    values ('00000000-0000-4000-8000-0000000000c5', '00000000-0000-4000-8000-0000000000f1',
            pg_temp.category('expense', null, 'Persona'), 'Cosmetici di Anna', 'expense', 'personal',
            '00000000-0000-4000-8000-0000000000a1')$$,
  'a member creates a personal subcategory under a shared macro'
);
select lives_ok(
  $$insert into public.categories (household_id, parent_id, name, kind, scope)
    values ('00000000-0000-4000-8000-0000000000f1', pg_temp.category('expense', null, 'Trasporti'),
            'Taxi', 'expense', 'shared')$$,
  'a member creates a shared subcategory'
);
select throws_ok(
  $$insert into public.categories (household_id, name, kind, scope, owner_member_id)
    values ('00000000-0000-4000-8000-0000000000f1', 'Solo mia', 'expense', 'personal',
            '00000000-0000-4000-8000-0000000000a1')$$,
  '23514', null,
  'a macro is always shared'
);
select throws_ok(
  $$insert into public.categories (household_id, parent_id, name, kind, scope)
    values ('00000000-0000-4000-8000-0000000000f1', pg_temp.category('expense', 'Cibo', 'Spesa'),
            'Spesa bio', 'expense', 'shared')$$,
  '23514', null,
  'two levels only'
);
select throws_ok(
  $$insert into public.categories (household_id, parent_id, name, kind, scope)
    values ('00000000-0000-4000-8000-0000000000f1', pg_temp.category('expense', null, 'Cibo'),
            'Buoni pasto', 'income', 'shared')$$,
  '23514', null,
  'a subcategory has the kind of its macro'
);
select throws_ok(
  $$insert into public.categories (household_id, parent_id, name, kind, scope)
    values ('00000000-0000-4000-8000-0000000000f1', pg_temp.category('expense', null, 'Cibo'),
            ' spesa ', 'expense', 'shared')$$,
  '23505', null,
  'a shared name is unique under the same macro, ignoring case and spaces'
);
select lives_ok(
  $$insert into public.categories (household_id, name, kind, scope)
    values ('00000000-0000-4000-8000-0000000000f1', 'Casa', 'income', 'shared')$$,
  'an expense and an income category can have the same name'
);
select throws_ok(
  $$insert into public.categories (household_id, parent_id, name, kind, scope, owner_member_id)
    values ('00000000-0000-4000-8000-0000000000f1', pg_temp.category('expense', null, 'Persona'),
            'Di Bruno', 'expense', 'personal', '00000000-0000-4000-8000-0000000000b1')$$,
  '42501', null,
  'a member does not create personal categories of others'
);
select throws_ok(
  $$delete from public.categories where id = '00000000-0000-4000-8000-0000000000c5'$$,
  '42501', null,
  'categories are never deleted'
);
select throws_ok(
  $$update public.categories set owner_member_id = '00000000-0000-4000-8000-0000000000a1'
    where id = pg_temp.category('expense', 'Trasporti', 'Taxi')$$,
  '42501', null,
  'the owner of a category does not change from the app'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select is_empty(
  $$select 1 from public.categories where id = '00000000-0000-4000-8000-0000000000c5'$$,
  'another member does not see a personal category'
);
select isnt_empty(
  $$select 1 from public.categories where name = 'Taxi'$$,
  'every member sees the shared categories'
);
update public.categories set name = 'Cambiata da Bruno'
  where id = '00000000-0000-4000-8000-0000000000c5';
select lives_ok(
  $$update public.categories set archived_at = now()
    where id = pg_temp.category('expense', 'Trasporti', 'Taxi')$$,
  'any member archives a shared category'
);

-- System categories
reset role;
select throws_ok(
  $$update public.categories set archived_at = now()
    where household_id = '00000000-0000-4000-8000-0000000000f1' and system_key = 'cash_difference' and kind = 'expense'$$,
  '23514', null,
  'Differenza di cassa is never archived'
);
select throws_ok(
  $$update public.categories set scope = 'personal', owner_member_id = '00000000-0000-4000-8000-0000000000a1'
    where household_id = '00000000-0000-4000-8000-0000000000f1' and system_key = 'cash_difference' and kind = 'expense'$$,
  '23514', null,
  'Differenza di cassa never becomes personal'
);
select is(
  (select name from public.categories where id = '00000000-0000-4000-8000-0000000000c5'),
  'Cosmetici di Anna',
  'Bruno did not change the personal category of Anna'
);

-- Promotion to shared
set local role authenticated;
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$update public.categories set scope = 'shared' where id = '00000000-0000-4000-8000-0000000000c5'$$,
  'the owner promotes a personal category to shared'
);
select results_eq(
  $$select scope, owner_member_id from public.categories where id = '00000000-0000-4000-8000-0000000000c5'$$,
  $$values ('shared'::text, null::uuid)$$,
  'a promoted category has no owner'
);
insert into public.categories (id, household_id, parent_id, name, kind, scope, owner_member_id)
values ('00000000-0000-4000-8000-0000000000c6', '00000000-0000-4000-8000-0000000000f1',
        pg_temp.category('expense', null, 'Cibo'), 'Spesa', 'expense', 'personal',
        '00000000-0000-4000-8000-0000000000a1');
select throws_ok(
  $$update public.categories set scope = 'shared' where id = '00000000-0000-4000-8000-0000000000c6'$$,
  '23505', null,
  'a promotion checks the name against the shared categories'
);
select throws_ok(
  $$update public.categories set scope = 'personal' where id = '00000000-0000-4000-8000-0000000000c5'$$,
  '23514', null,
  'a shared category never becomes personal'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000d');
select is_empty(
  $$select 1 from public.categories where household_id = '00000000-0000-4000-8000-0000000000f1'$$,
  'Dario does not see the categories of "Casa di prova"'
);
select is(
  (select count(*)::int from public.categories),
  72,
  'Dario sees the initial list of his own household'
);

-- Tags
select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$insert into public.tags (id, household_id, name, scope)
    values ('00000000-0000-4000-8000-0000000000e1', '00000000-0000-4000-8000-0000000000f1', 'Viaggio estate', 'shared')$$,
  'a member creates a shared tag'
);
select lives_ok(
  $$insert into public.tags (id, household_id, name, scope, owner_member_id)
    values ('00000000-0000-4000-8000-0000000000e2', '00000000-0000-4000-8000-0000000000f1', 'Regali di Anna',
            'personal', '00000000-0000-4000-8000-0000000000a1')$$,
  'a member creates a personal tag'
);
select throws_ok(
  $$insert into public.tags (household_id, name, scope)
    values ('00000000-0000-4000-8000-0000000000f1', 'viaggio ESTATE', 'shared')$$,
  '23505', null,
  'a shared tag name is unique, ignoring case'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000b');
select results_eq(
  'select name from public.tags',
  $$values ('Viaggio estate'::text)$$,
  'another member sees the shared tags, not the personal ones'
);
select throws_ok(
  $$delete from public.tags where id = '00000000-0000-4000-8000-0000000000e1'$$,
  '42501', null,
  'tags are never deleted'
);

select pg_temp.login('00000000-0000-4000-8000-00000000000a');
select lives_ok(
  $$update public.tags set scope = 'shared' where id = '00000000-0000-4000-8000-0000000000e2'$$,
  'the owner promotes a personal tag'
);
select throws_ok(
  $$update public.tags set scope = 'personal' where id = '00000000-0000-4000-8000-0000000000e1'$$,
  '23514', null,
  'a shared tag never becomes personal'
);

select * from finish();
rollback;
