-- UniPlanner: enable Realtime INSERT events used by Study Group notifications.
-- Safe/idempotent: this does not alter rows, table schemas, auth, or RLS policies.
-- Run in the Supabase SQL Editor for the production project only after reviewing.
do $$
declare
  t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'Publication supabase_realtime does not exist in this project.';
  end if;

  foreach t in array array[
    'uniplanner_group_messages',
    'uniplanner_task_comments',
    'uniplanner_shared_tasks'
  ] loop
    if to_regclass('public.' || t) is null then
      raise notice 'Skipping missing table public.%', t;
    elsif not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
      raise notice 'Added public.% to supabase_realtime', t;
    else
      raise notice 'public.% already enabled for Realtime', t;
    end if;
  end loop;
end $$;
