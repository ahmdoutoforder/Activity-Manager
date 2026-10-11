-- UniPlanner v2 Supabase schema
-- Run this in Supabase SQL Editor before enabling cross-device sync.
create table if not exists public.uniplanner_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  payload jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.uniplanner_data enable row level security;
drop policy if exists "Users can read their own UniPlanner data" on public.uniplanner_data;
create policy "Users can read their own UniPlanner data"
  on public.uniplanner_data for select to authenticated
  using (auth.uid() = user_id);
drop policy if exists "Users can insert their own UniPlanner data" on public.uniplanner_data;
create policy "Users can insert their own UniPlanner data"
  on public.uniplanner_data for insert to authenticated
  with check (auth.uid() = user_id);
drop policy if exists "Users can update their own UniPlanner data" on public.uniplanner_data;
create policy "Users can update their own UniPlanner data"
  on public.uniplanner_data for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists "Users can delete their own UniPlanner data" on public.uniplanner_data;
create policy "Users can delete their own UniPlanner data"
  on public.uniplanner_data for delete to authenticated
  using (auth.uid() = user_id);
