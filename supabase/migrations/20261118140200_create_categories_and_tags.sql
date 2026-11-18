-- Categories and tags (docs/spec/schema.md, 8; docs/spec/categorie.md).
--
-- Two levels: macro and subcategory. Shared categories and tags are seen and
-- changed by all the active members; personal ones only by their owner.
-- Never deleted, only archived. A new household gets the initial list of
-- categorie.md.

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  -- Null: a macro.
  parent_id uuid references public.categories (id),
  name text not null
    constraint categories_name_not_empty check (char_length(btrim(name)) > 0),
  kind text not null
    constraint categories_kind check (kind in ('expense', 'income')),
  scope text not null
    constraint categories_scope check (scope in ('shared', 'personal')),
  owner_member_id uuid references public.members (id),
  -- cash_difference: Differenza di cassa, one for expenses and one for income.
  system_key text
    constraint categories_system_key check (system_key in ('cash_difference')),
  deductible_730_default boolean not null default false,
  position smallint not null default 0,
  archived_at timestamptz,
  merged_into_id uuid references public.categories (id),
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint categories_owner_by_scope
    check ((owner_member_id is not null) = (scope = 'personal')),
  -- A macro is always shared; a personal category is always a subcategory.
  constraint categories_personal_is_subcategory
    check (scope = 'shared' or parent_id is not null),
  -- System categories are never archived, merged or made personal.
  constraint categories_system_rules
    check (system_key is null or (scope = 'shared' and archived_at is null and merged_into_id is null))
);

comment on table public.categories is
  'Categories of the household, two levels, shared or personal; archived, never deleted.';

-- Unique name among the shared categories not archived, with the same
-- parent and the same kind (expenses and income both have a "Varie").
create unique index categories_shared_name
  on public.categories (household_id, kind, parent_id, lower(btrim(name))) nulls not distinct
  where scope = 'shared' and archived_at is null;

create unique index categories_system_key_unique
  on public.categories (household_id, kind, system_key)
  where system_key is not null;

create index categories_parent_id on public.categories (parent_id);
create index categories_owner_member_id on public.categories (owner_member_id);

create trigger categories_touch_row
  before update on public.categories
  for each row execute function public.touch_row();

create table public.tags (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  name text not null
    constraint tags_name_not_empty check (char_length(btrim(name)) > 0),
  scope text not null
    constraint tags_scope check (scope in ('shared', 'personal')),
  owner_member_id uuid references public.members (id),
  archived_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tags_owner_by_scope
    check ((owner_member_id is not null) = (scope = 'personal'))
);

comment on table public.tags is
  'Free tags across categories (e.g. a trip), shared or personal; archived, never deleted.';

create unique index tags_shared_name
  on public.tags (household_id, lower(btrim(name)))
  where scope = 'shared' and archived_at is null;

create index tags_owner_member_id on public.tags (owner_member_id);

create trigger tags_touch_row
  before update on public.tags
  for each row execute function public.touch_row();

-- Parent in the same household, a macro of the same kind; a macro with
-- subcategories stays a macro. A shared category never becomes personal; a
-- personal one promoted to shared loses its owner.
create function public.check_category()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent public.categories%rowtype;
begin
  if tg_op = 'UPDATE' then
    if new.scope = 'personal' and old.scope = 'shared' then
      raise exception 'a shared category does not become personal'
        using errcode = 'check_violation';
    end if;
    if new.scope = 'shared' and old.scope = 'personal' then
      new.owner_member_id := null;
    end if;
    if new.household_id <> old.household_id or new.kind <> old.kind then
      raise exception 'household and kind of a category do not change'
        using errcode = 'check_violation';
    end if;
  end if;

  if new.parent_id is not null then
    select c.* into v_parent from public.categories c where c.id = new.parent_id;
    if v_parent.household_id <> new.household_id
      or v_parent.parent_id is not null
      or v_parent.kind <> new.kind
    then
      raise exception 'the parent is a macro of the same household and kind'
        using errcode = 'check_violation';
    end if;
    if exists (select 1 from public.categories c where c.parent_id = new.id) then
      raise exception 'a macro with subcategories stays a macro'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

revoke all on function public.check_category() from public, anon, authenticated;

create trigger categories_check
  before insert or update on public.categories
  for each row execute function public.check_category();

create function public.check_tag()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.scope = 'personal' and old.scope = 'shared' then
    raise exception 'a shared tag does not become personal'
      using errcode = 'check_violation';
  end if;
  if new.scope = 'shared' and old.scope = 'personal' then
    new.owner_member_id := null;
  end if;
  if new.household_id <> old.household_id then
    raise exception 'the household of a tag does not change'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke all on function public.check_tag() from public, anon, authenticated;

create trigger tags_check
  before update on public.tags
  for each row execute function public.check_tag();

-- Initial list of categorie.md, sections 7 and 8: macros in order, their
-- subcategories in order, the 730 flag and the two Differenza di cassa.
create function public.seed_categories()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_macro record;
  v_parent_id uuid;
begin
  for v_macro in
    select *
    from (values
      ('expense', 1, 'Casa', false, array[
        'Mutuo', 'Assicurazioni casa e mutuo', 'Luce', 'Gas', 'Acqua', 'Condominio',
        'Internet', 'Manutenzione e riparazioni', 'Arredo ed elettrodomestici',
        'Pulizia e detersivi', 'Tasse casa', 'Giardinaggio']),
      ('expense', 2, 'Cibo', false, array['Spesa', 'Ristoranti', 'Delivery']),
      ('expense', 3, 'Trasporti', false, array[
        'Rata auto', 'Carburante', 'Assicurazione e bollo', 'Manutenzione auto',
        'Pedaggi e parcheggi', 'Mezzi pubblici', 'Bici e altro', 'Multe']),
      ('expense', 4, 'Salute', true, array['Farmaci', 'Visite ed esami', 'Ottico']),
      ('expense', 5, 'Persona', false, array[
        'Abbigliamento', 'Parrucchiere', 'Estetista', 'Cosmetici', 'Cellulare', 'Tecnologia']),
      ('expense', 6, 'Animali', false, array[
        'Alimentazione', 'Veterinario', 'Accessori e giochi', 'Toelettatura']),
      ('expense', 7, 'Tempo libero', false, array[
        'Abbonamenti', 'Libri e media', 'Cinema, concerti, musei', 'Sport', 'Hobby']),
      ('expense', 8, 'Viaggi', false, array['Trasporto', 'Alloggio']),
      ('expense', 9, 'Regali e donazioni', false, array['Regali', 'Donazioni']),
      ('expense', 10, 'Formazione', false, array['Corsi', 'Materiale', 'Tasse universitarie']),
      ('expense', 11, 'Finanza', false, array[
        'Commissioni bancarie', 'Bolli e tasse', 'Altre assicurazioni', 'Tasse personali']),
      ('expense', 12, 'Varie', false, array['Varie', 'Differenza di cassa']),
      ('income', 1, 'Stipendio', false, array[]::text[]),
      ('income', 2, 'Rendimenti', false, array[]::text[]),
      ('income', 3, 'Vendite usato', false, array[]::text[]),
      ('income', 4, 'Regali ricevuti', false, array[]::text[]),
      ('income', 5, 'Varie', false, array['Differenza di cassa'])
    ) as t (kind, position, name, deductible, subcategories)
  loop
    insert into public.categories (household_id, kind, scope, name, position, deductible_730_default)
    values (new.id, v_macro.kind, 'shared', v_macro.name, v_macro.position, v_macro.deductible)
    returning id into v_parent_id;

    insert into public.categories (
      household_id, parent_id, kind, scope, name, position, deductible_730_default, system_key
    )
    select
      new.id,
      v_parent_id,
      v_macro.kind,
      'shared',
      s.name,
      s.position,
      v_macro.deductible or s.name in ('Veterinario', 'Tasse universitarie'),
      case when s.name = 'Differenza di cassa' then 'cash_difference' end
    from unnest(v_macro.subcategories) with ordinality as s (name, position);
  end loop;

  return null;
end;
$$;

revoke all on function public.seed_categories() from public, anon, authenticated;

create trigger households_seed_categories
  after insert on public.households
  for each row execute function public.seed_categories();

-- RLS: shared ones for the active members, personal ones for their owner.

alter table public.categories enable row level security;
alter table public.tags enable row level security;

revoke all on table public.categories from anon, authenticated;
revoke all on table public.tags from anon, authenticated;

grant select on table public.categories to authenticated;
grant insert (
  id, household_id, parent_id, name, kind, scope, owner_member_id,
  deductible_730_default, position
) on table public.categories to authenticated;
-- Promotion to shared: the owner changes scope (the owner goes away).
grant update (
  parent_id, name, scope, deductible_730_default, position, archived_at
) on table public.categories to authenticated;

create policy categories_select_visible on public.categories
  for select to authenticated
  using (
    household_id = (select public.current_household_id())
    and (scope = 'shared' or owner_member_id = (select public.current_member_id()))
  );

create policy categories_insert_visible on public.categories
  for insert to authenticated
  with check (
    household_id = (select public.current_household_id())
    and (scope = 'shared' or owner_member_id = (select public.current_member_id()))
  );

create policy categories_update_visible on public.categories
  for update to authenticated
  using (
    household_id = (select public.current_household_id())
    and (scope = 'shared' or owner_member_id = (select public.current_member_id()))
  )
  with check (
    household_id = (select public.current_household_id())
    and (scope = 'shared' or owner_member_id = (select public.current_member_id()))
  );

grant select on table public.tags to authenticated;
grant insert (id, household_id, name, scope, owner_member_id) on table public.tags to authenticated;
grant update (name, scope, archived_at) on table public.tags to authenticated;

create policy tags_select_visible on public.tags
  for select to authenticated
  using (
    household_id = (select public.current_household_id())
    and (scope = 'shared' or owner_member_id = (select public.current_member_id()))
  );

create policy tags_insert_visible on public.tags
  for insert to authenticated
  with check (
    household_id = (select public.current_household_id())
    and (scope = 'shared' or owner_member_id = (select public.current_member_id()))
  );

create policy tags_update_visible on public.tags
  for update to authenticated
  using (
    household_id = (select public.current_household_id())
    and (scope = 'shared' or owner_member_id = (select public.current_member_id()))
  )
  with check (
    household_id = (select public.current_household_id())
    and (scope = 'shared' or owner_member_id = (select public.current_member_id()))
  );
