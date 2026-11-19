-- Extensions of the bank sync (docs/spec/sincronizzazione.md, 1 and 10).
--
-- pg_cron runs the scheduled jobs and pg_net makes their HTTP calls to the
-- Edge Functions; the jobs come with their own migration. Schemas as in the
-- Supabase docs: pg_cron in pg_catalog, with its objects in the cron schema
-- (https://supabase.com/docs/guides/cron/install); pg_net in extensions,
-- with its objects in the net schema
-- (https://supabase.com/docs/guides/database/extensions/pg_net).
--
-- Supabase Vault, which keeps the private keys and the secret of the jobs,
-- is already installed on Supabase, also locally: it is not created here.

create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

create extension if not exists pg_net with schema extensions;
