-- An invite is revoked once (docs/spec/schema.md, 3): revoked_at goes from
-- null to a value and then never changes, nor goes back to null, for the
-- app and for the server alike.

create function public.check_invite_revocation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.revoked_at is not null and new.revoked_at is distinct from old.revoked_at then
    raise exception 'invite_revoked';
  end if;
  return new;
end;
$$;

revoke all on function public.check_invite_revocation()
  from public, anon, authenticated;

create trigger invites_check_revocation
  before update of revoked_at on public.invites
  for each row execute function public.check_invite_revocation();
