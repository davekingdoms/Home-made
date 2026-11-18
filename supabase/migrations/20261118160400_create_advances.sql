-- External people and advances (docs/spec/schema.md, 11).
--
-- A member pays something a third person will give back: the line is an
-- advance, linked to a contact of the personal address book of the member.
-- The refunds are linked to it and inherit the shares of the line; open,
-- partial or closed comes from the refunds.

create table public.contacts (
  id uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households (id),
  owner_member_id uuid not null references public.members (id),
  name text not null
    constraint contacts_name_not_empty check (char_length(btrim(name)) > 0),
  archived_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.contacts is 'Personal address book of a member: people outside the household.';

create index contacts_owner_member_id on public.contacts (owner_member_id);

create trigger contacts_touch_row
  before update on public.contacts
  for each row execute function public.touch_row();

create table public.advances (
  id uuid primary key default gen_random_uuid(),
  -- The line a third person will give back.
  line_id uuid not null unique references public.transaction_lines (id),
  contact_id uuid not null references public.contacts (id),
  -- Copied, so the other members involved in the line see it.
  contact_name text not null,
  expected_cents bigint not null
    constraint advances_expected_positive check (expected_cents > 0),
  -- Became a normal expense.
  written_off_at timestamptz,
  version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.advances is 'Lines a third person will give back, with who and how much.';

create index advances_contact_id on public.advances (contact_id);

create trigger advances_touch_row
  before update on public.advances
  for each row execute function public.touch_row();

create table public.advance_repayments (
  advance_id uuid not null references public.advances (id),
  -- The line of the refund.
  line_id uuid not null references public.transaction_lines (id),
  amount_cents bigint not null
    constraint advance_repayments_amount_positive check (amount_cents > 0),
  primary key (advance_id, line_id)
);

comment on table public.advance_repayments is 'Refunds of an advance: line and amount.';

create index advance_repayments_line_id on public.advance_repayments (line_id);

-- The owner of a contact is an active member of its household.
create function public.check_contact()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.check_active_member(new.owner_member_id, new.household_id);
  return new;
end;
$$;

create trigger contacts_check
  before insert or update of household_id, owner_member_id on public.contacts
  for each row execute function public.check_contact();

-- The name of the contact is copied; the contact is of the household of the
-- line.
create function public.prepare_advance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_contact public.contacts%rowtype;
begin
  select c.* into v_contact from public.contacts c where c.id = new.contact_id;
  if v_contact.household_id is distinct from (
    select l.household_id from public.transaction_lines l where l.id = new.line_id
  ) then
    raise exception 'the contact is of the household of the line'
      using errcode = 'check_violation';
  end if;
  new.contact_name := v_contact.name;
  return new;
end;
$$;

create trigger advances_prepare
  before insert or update of contact_id, line_id on public.advances
  for each row execute function public.prepare_advance();

-- The refund inherits the shares of the line of the advance: same weights,
-- cents computed on the refund.
create function public.copy_advance_shares()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_refund public.transaction_lines%rowtype;
  v_weights jsonb;
begin
  select l.* into v_refund from public.transaction_lines l where l.id = new.line_id;

  select jsonb_agg(jsonb_build_object('member_id', s.member_id, 'weight', s.weight))
  into v_weights
  from public.advances a
  join public.line_shares s on s.line_id = a.line_id
  where a.id = new.advance_id;

  if v_refund.household_id is distinct from (
    select l.household_id
    from public.advances a
    join public.transaction_lines l on l.id = a.line_id
    where a.id = new.advance_id
  ) then
    raise exception 'the refund is of the household of the advance'
      using errcode = 'check_violation';
  end if;

  delete from public.line_shares s where s.line_id = v_refund.id;

  insert into public.line_shares (line_id, member_id, household_id, weight, amount_cents)
  select v_refund.id, c.member_id, v_refund.household_id, (w ->> 'weight')::numeric, c.amount_cents
  from public.split_cents(v_refund.amount_cents, v_weights, v_refund.paid_by_member_id) c
  join jsonb_array_elements(v_weights) as w on (w ->> 'member_id')::uuid = c.member_id;

  return null;
end;
$$;

create trigger advance_repayments_copy_shares
  after insert on public.advance_repayments
  for each row execute function public.copy_advance_shares();

revoke all on function public.check_contact() from public, anon, authenticated;
revoke all on function public.prepare_advance() from public, anon, authenticated;
revoke all on function public.copy_advance_shares() from public, anon, authenticated;

-- RLS

alter table public.contacts enable row level security;
alter table public.advances enable row level security;
alter table public.advance_repayments enable row level security;

revoke all on table public.contacts from anon, authenticated;
revoke all on table public.advances from anon, authenticated;
revoke all on table public.advance_repayments from anon, authenticated;

-- Contacts: personal, only the owner.
grant select on table public.contacts to authenticated;
grant insert (id, household_id, owner_member_id, name) on table public.contacts to authenticated;
grant update (name, archived_at) on table public.contacts to authenticated;

create policy contacts_select_own on public.contacts
  for select to authenticated
  using (owner_member_id = (select public.current_member_id()));

create policy contacts_insert_own on public.contacts
  for insert to authenticated
  with check (
    owner_member_id = (select public.current_member_id())
    and household_id = (select public.current_household_id())
  );

create policy contacts_update_own on public.contacts
  for update to authenticated
  using (owner_member_id = (select public.current_member_id()))
  with check (owner_member_id = (select public.current_member_id()));

-- Advances and refunds: as the line of the advance. Who links them can
-- change the lines involved, and links a contact of their own.
grant select on table public.advances to authenticated;
grant insert (id, line_id, contact_id, expected_cents) on table public.advances to authenticated;
grant update (expected_cents, written_off_at) on table public.advances to authenticated;

create policy advances_select_line on public.advances
  for select to authenticated
  using (public.can_see_line(line_id));

create policy advances_insert_line on public.advances
  for insert to authenticated
  with check (
    public.can_edit_line(line_id)
    and exists (select 1 from public.contacts c where c.id = contact_id)
  );

create policy advances_update_line on public.advances
  for update to authenticated
  using (public.can_edit_line(line_id))
  with check (public.can_edit_line(line_id));

grant select, insert, delete on table public.advance_repayments to authenticated;

create policy advance_repayments_select_line on public.advance_repayments
  for select to authenticated
  using (exists (select 1 from public.advances a where a.id = advance_id));

create policy advance_repayments_insert_line on public.advance_repayments
  for insert to authenticated
  with check (
    exists (select 1 from public.advances a where a.id = advance_id and public.can_edit_line(a.line_id))
    and public.can_edit_line(line_id)
  );

create policy advance_repayments_delete_line on public.advance_repayments
  for delete to authenticated
  using (exists (select 1 from public.advances a where a.id = advance_id and public.can_edit_line(a.line_id)));
