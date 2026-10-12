-- UniPlanner owner-approved access control (additive migration)
-- Safe to run on an existing UniPlanner database. Does not delete or rewrite planner records.
-- Existing Auth users are grandfathered as approved; new users must be approved manually.

create table if not exists public.uniplanner_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null check (status in ('approved', 'revoked')),
  approved_at timestamptz,
  approved_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.uniplanner_access enable row level security;
revoke all on table public.uniplanner_access from public, anon, authenticated;
grant select on table public.uniplanner_access to authenticated;
drop policy if exists "Users can read their own access status" on public.uniplanner_access;
create policy "Users can read their own access status"
  on public.uniplanner_access for select to authenticated
  using (user_id = auth.uid());

-- Existing accounts keep working. New accounts have no row and are denied until approved.
insert into public.uniplanner_access (user_id, status, approved_at, approved_by, updated_at)
select id, 'approved', now(), null, now()
from auth.users
on conflict (user_id) do nothing;

create or replace function public.uniplanner_is_approved()
returns boolean
language sql stable security definer set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.uniplanner_access a
    where a.user_id = auth.uid() and a.status = 'approved'
  );
$$;
revoke all on function public.uniplanner_is_approved() from public, anon;
grant execute on function public.uniplanner_is_approved() to authenticated;

-- Restrictive policies combine with existing per-user/workspace policies using AND.
-- This gates direct API access as well as the website UI.
drop policy if exists "Approved users only" on public.uniplanner_data;
create policy "Approved users only" on public.uniplanner_data
  as restrictive for all to authenticated
  using (public.uniplanner_is_approved())
  with check (public.uniplanner_is_approved());

drop policy if exists "Approved users only" on public.uniplanner_workspaces;
create policy "Approved users only" on public.uniplanner_workspaces
  as restrictive for all to authenticated
  using (public.uniplanner_is_approved())
  with check (public.uniplanner_is_approved());

drop policy if exists "Approved users only" on public.uniplanner_workspace_members;
create policy "Approved users only" on public.uniplanner_workspace_members
  as restrictive for all to authenticated
  using (public.uniplanner_is_approved())
  with check (public.uniplanner_is_approved());

drop policy if exists "Approved users only" on public.uniplanner_shared_tasks;
create policy "Approved users only" on public.uniplanner_shared_tasks
  as restrictive for all to authenticated
  using (public.uniplanner_is_approved())
  with check (public.uniplanner_is_approved());

drop policy if exists "Approved users only" on public.uniplanner_workspace_notes;
create policy "Approved users only" on public.uniplanner_workspace_notes
  as restrictive for all to authenticated
  using (public.uniplanner_is_approved())
  with check (public.uniplanner_is_approved());

drop policy if exists "Approved users only" on public.uniplanner_task_comments;
create policy "Approved users only" on public.uniplanner_task_comments
  as restrictive for all to authenticated
  using (public.uniplanner_is_approved())
  with check (public.uniplanner_is_approved());

drop policy if exists "Approved users only" on public.uniplanner_group_messages;
create policy "Approved users only" on public.uniplanner_group_messages
  as restrictive for all to authenticated
  using (public.uniplanner_is_approved())
  with check (public.uniplanner_is_approved());

drop policy if exists "Approved users only" on public.uniplanner_profiles;
create policy "Approved users only" on public.uniplanner_profiles
  as restrictive for all to authenticated
  using (public.uniplanner_is_approved())
  with check (public.uniplanner_is_approved());

-- Secure SECURITY DEFINER collaboration helpers too (they bypass table RLS).
create or replace function public.uniplanner_is_workspace_member(target_workspace uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select public.uniplanner_is_approved() and exists (
    select 1 from public.uniplanner_workspace_members m
    where m.workspace_id = target_workspace and m.user_id = auth.uid()
  );
$$;
revoke all on function public.uniplanner_is_workspace_member(uuid) from public, anon;
grant execute on function public.uniplanner_is_workspace_member(uuid) to authenticated;

create or replace function public.uniplanner_create_workspace(workspace_name text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare new_workspace uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in before creating a workspace';
  end if;
  if not public.uniplanner_is_approved() then
    raise exception 'Your UniPlanner account is not approved';
  end if;
  if char_length(trim(workspace_name)) < 1 or char_length(trim(workspace_name)) > 80 then
    raise exception 'Workspace name must be between 1 and 80 characters';
  end if;
  insert into public.uniplanner_workspaces(name, created_by)
    values (trim(workspace_name), auth.uid()) returning id into new_workspace;
  insert into public.uniplanner_workspace_members(workspace_id, user_id, role)
    values (new_workspace, auth.uid(), 'owner');
  return new_workspace;
end;
$$;
revoke all on function public.uniplanner_create_workspace(text) from public, anon;
grant execute on function public.uniplanner_create_workspace(text) to authenticated;

create or replace function public.uniplanner_invite_member(target_workspace uuid, invite_email text)
returns void language plpgsql security definer set search_path = public
as $$
declare invited_user uuid;
begin
  if not public.uniplanner_is_approved() then
    raise exception 'Your UniPlanner account is not approved';
  end if;
  if not exists (
    select 1 from public.uniplanner_workspace_members m
    where m.workspace_id = target_workspace and m.user_id = auth.uid() and m.role = 'owner'
  ) then
    raise exception 'Only workspace owners can invite members';
  end if;
  select u.id into invited_user from auth.users u
    where lower(u.email) = lower(trim(invite_email)) limit 1;
  if invited_user is null then
    raise exception 'No registered account found for that email. Ask the owner to invite them first.';
  end if;
  if not exists (select 1 from public.uniplanner_access a where a.user_id = invited_user and a.status = 'approved') then
    raise exception 'This account has not been approved for UniPlanner by the owner yet';
  end if;
  insert into public.uniplanner_workspace_members(workspace_id, user_id, role)
    values (target_workspace, invited_user, 'member')
    on conflict (workspace_id, user_id) do nothing;
end;
$$;
revoke all on function public.uniplanner_invite_member(uuid,text) from public, anon;
grant execute on function public.uniplanner_invite_member(uuid,text) to authenticated;

-- OWNER WORKFLOWS (run manually in Supabase SQL Editor):
-- Approve an invited account:
-- insert into public.uniplanner_access (user_id, status, approved_at, approved_by, updated_at)
-- select id, 'approved', now(), null, now() from auth.users where lower(email)=lower('person@example.com')
-- on conflict (user_id) do update set status='approved', approved_at=now(), approved_by=null, updated_at=now();
--
-- Revoke website access without deleting the account or its data:
-- update public.uniplanner_access a set status='revoked', updated_at=now()
-- where a.user_id=(select id from auth.users where lower(email)=lower('person@example.com'));
--
-- Re-approve later by running the approve query again.
