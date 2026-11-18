-- Common trigger of the tables the app changes (docs/spec/schema.md, 1).
--
-- Every update bumps version and sets updated_at. The app updates with the
-- filter version = <version read>: when no row changes, the row was changed
-- elsewhere, and the app reads it again.

create function public.touch_row()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.version := old.version + 1;
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.touch_row() is
  'Before update: version + 1 and updated_at = now().';

-- Only triggers call it.
revoke all on function public.touch_row() from public, anon, authenticated;
