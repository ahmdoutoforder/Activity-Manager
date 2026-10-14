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

-- Optional shared workspaces for small study groups.
create table if not exists public.uniplanner_workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(trim(name)) between 1 and 80),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.uniplanner_workspace_members (
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check (role in ('owner','member')),
  joined_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);
create table if not exists public.uniplanner_shared_tasks (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 180),
  description text not null default '',
  due_date date not null,
  category text not null default 'Assignment',
  priority text not null default 'Medium' check (priority in ('High','Medium','Low')),
  completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists uniplanner_shared_tasks_workspace_due
  on public.uniplanner_shared_tasks(workspace_id, due_date);

-- SECURITY DEFINER helper avoids recursive membership-policy evaluation.
create or replace function public.uniplanner_is_workspace_member(target_workspace uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.uniplanner_workspace_members m
    where m.workspace_id = target_workspace and m.user_id = auth.uid()
  );
$$;
revoke all on function public.uniplanner_is_workspace_member(uuid) from public;
grant execute on function public.uniplanner_is_workspace_member(uuid) to authenticated;

alter table public.uniplanner_workspaces enable row level security;
alter table public.uniplanner_workspace_members enable row level security;
alter table public.uniplanner_shared_tasks enable row level security;

drop policy if exists "Members can read workspaces" on public.uniplanner_workspaces;
create policy "Members can read workspaces" on public.uniplanner_workspaces
  for select to authenticated using (public.uniplanner_is_workspace_member(id));
drop policy if exists "Users can create workspaces" on public.uniplanner_workspaces;
create policy "Users can create workspaces" on public.uniplanner_workspaces
  for insert to authenticated with check (created_by = auth.uid());
drop policy if exists "Owners can rename workspaces" on public.uniplanner_workspaces;
create policy "Owners can rename workspaces" on public.uniplanner_workspaces
  for update to authenticated using (
    exists (select 1 from public.uniplanner_workspace_members m
      where m.workspace_id = id and m.user_id = auth.uid() and m.role = 'owner')
  ) with check (public.uniplanner_is_workspace_member(id));
drop policy if exists "Owners can delete workspaces" on public.uniplanner_workspaces;
create policy "Owners can delete workspaces" on public.uniplanner_workspaces
  for delete to authenticated using (
    exists (select 1 from public.uniplanner_workspace_members m
      where m.workspace_id = id and m.user_id = auth.uid() and m.role = 'owner')
  );

drop policy if exists "Members can read membership" on public.uniplanner_workspace_members;
create policy "Members can read membership" on public.uniplanner_workspace_members
  for select to authenticated using (public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Workspace creators can add themselves" on public.uniplanner_workspace_members;
create policy "Workspace creators can add themselves" on public.uniplanner_workspace_members
  for insert to authenticated with check (
    user_id = auth.uid() and role = 'owner' and exists (
      select 1 from public.uniplanner_workspaces w
      where w.id = workspace_id and w.created_by = auth.uid()
    )
  );
drop policy if exists "Members can leave or owners can remove members" on public.uniplanner_workspace_members;
create policy "Members can leave or owners can remove members" on public.uniplanner_workspace_members
  for delete to authenticated using (
    user_id = auth.uid() or exists (
      select 1 from public.uniplanner_workspace_members m
      where m.workspace_id = uniplanner_workspace_members.workspace_id and m.user_id = auth.uid() and m.role = 'owner'
    )
  );

create or replace function public.uniplanner_create_workspace(workspace_name text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare new_workspace uuid;
begin
  if auth.uid() is null then
    raise exception 'Sign in before creating a workspace';
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
revoke all on function public.uniplanner_create_workspace(text) from public;
grant execute on function public.uniplanner_create_workspace(text) to authenticated;

create or replace function public.uniplanner_invite_member(target_workspace uuid, invite_email text)
returns void language plpgsql security definer set search_path = public
as $$
declare invited_user uuid;
begin
  if not exists (
    select 1 from public.uniplanner_workspace_members m
    where m.workspace_id = target_workspace and m.user_id = auth.uid() and m.role = 'owner'
  ) then
    raise exception 'Only workspace owners can invite members';
  end if;
  select u.id into invited_user from auth.users u
    where lower(u.email) = lower(trim(invite_email)) limit 1;
  if invited_user is null then
    raise exception 'No registered account found for that email. Ask them to sign up first.';
  end if;
  insert into public.uniplanner_workspace_members(workspace_id, user_id, role)
    values (target_workspace, invited_user, 'member')
    on conflict (workspace_id, user_id) do nothing;
end;
$$;
revoke all on function public.uniplanner_invite_member(uuid,text) from public;
grant execute on function public.uniplanner_invite_member(uuid,text) to authenticated;

drop policy if exists "Members can read shared tasks" on public.uniplanner_shared_tasks;
create policy "Members can read shared tasks" on public.uniplanner_shared_tasks
  for select to authenticated using (public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Members can create shared tasks" on public.uniplanner_shared_tasks;
create policy "Members can create shared tasks" on public.uniplanner_shared_tasks
  for insert to authenticated with check (
    created_by = auth.uid() and public.uniplanner_is_workspace_member(workspace_id)
  );
drop policy if exists "Members can update shared tasks" on public.uniplanner_shared_tasks;
create policy "Members can update shared tasks" on public.uniplanner_shared_tasks
  for update to authenticated using (public.uniplanner_is_workspace_member(workspace_id))
  with check (public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Creators or owners can delete shared tasks" on public.uniplanner_shared_tasks;
create policy "Creators or owners can delete shared tasks" on public.uniplanner_shared_tasks
  for delete to authenticated using (
    created_by = auth.uid() or exists (
      select 1 from public.uniplanner_workspace_members m
      where m.workspace_id = uniplanner_shared_tasks.workspace_id and m.user_id = auth.uid() and m.role = 'owner'
    )
  );


-- Safe upgrade for group task assignment (existing tasks remain unassigned).
alter table public.uniplanner_shared_tasks
  add column if not exists assigned_to uuid references auth.users(id) on delete set null;
create index if not exists uniplanner_shared_tasks_assignee
  on public.uniplanner_shared_tasks(assigned_to);


-- Shared study notes, task discussions, and workspace chat.
-- Additive migration: existing personal data and shared tasks are untouched.
create table if not exists public.uniplanner_workspace_notes (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 120),
  body text not null check (char_length(trim(body)) between 1 and 10000),
  created_at timestamptz not null default now()
);
create index if not exists uniplanner_workspace_notes_recent
  on public.uniplanner_workspace_notes(workspace_id, created_at desc);

create table if not exists public.uniplanner_task_comments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  task_id uuid not null references public.uniplanner_shared_tasks(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 3000),
  created_at timestamptz not null default now()
);
create index if not exists uniplanner_task_comments_task_recent
  on public.uniplanner_task_comments(workspace_id, task_id, created_at);

create table if not exists public.uniplanner_group_messages (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 3000),
  created_at timestamptz not null default now()
);
create index if not exists uniplanner_group_messages_recent
  on public.uniplanner_group_messages(workspace_id, created_at);

alter table public.uniplanner_workspace_notes enable row level security;
alter table public.uniplanner_task_comments enable row level security;
alter table public.uniplanner_group_messages enable row level security;

drop policy if exists "Members can read shared notes" on public.uniplanner_workspace_notes;
create policy "Members can read shared notes" on public.uniplanner_workspace_notes
  for select to authenticated using (public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Members can add shared notes" on public.uniplanner_workspace_notes;
create policy "Members can add shared notes" on public.uniplanner_workspace_notes
  for insert to authenticated with check (
    created_by = auth.uid() and public.uniplanner_is_workspace_member(workspace_id)
  );
drop policy if exists "Authors or owners can delete shared notes" on public.uniplanner_workspace_notes;
create policy "Authors or owners can delete shared notes" on public.uniplanner_workspace_notes
  for delete to authenticated using (
    created_by = auth.uid() or exists (
      select 1 from public.uniplanner_workspace_members m
      where m.workspace_id = uniplanner_workspace_notes.workspace_id
        and m.user_id = auth.uid() and m.role = 'owner'
    )
  );

drop policy if exists "Members can read task comments" on public.uniplanner_task_comments;
create policy "Members can read task comments" on public.uniplanner_task_comments
  for select to authenticated using (
    public.uniplanner_is_workspace_member(workspace_id)
    and exists (select 1 from public.uniplanner_shared_tasks t
      where t.id = task_id and t.workspace_id = uniplanner_task_comments.workspace_id)
  );
drop policy if exists "Members can add task comments" on public.uniplanner_task_comments;
create policy "Members can add task comments" on public.uniplanner_task_comments
  for insert to authenticated with check (
    created_by = auth.uid() and public.uniplanner_is_workspace_member(workspace_id)
    and exists (select 1 from public.uniplanner_shared_tasks t
      where t.id = task_id and t.workspace_id = uniplanner_task_comments.workspace_id)
  );
drop policy if exists "Authors or owners can delete task comments" on public.uniplanner_task_comments;
create policy "Authors or owners can delete task comments" on public.uniplanner_task_comments
  for delete to authenticated using (
    created_by = auth.uid() or exists (
      select 1 from public.uniplanner_workspace_members m
      where m.workspace_id = uniplanner_task_comments.workspace_id
        and m.user_id = auth.uid() and m.role = 'owner'
    )
  );

drop policy if exists "Members can read group messages" on public.uniplanner_group_messages;
create policy "Members can read group messages" on public.uniplanner_group_messages
  for select to authenticated using (public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Members can send group messages" on public.uniplanner_group_messages;
create policy "Members can send group messages" on public.uniplanner_group_messages
  for insert to authenticated with check (
    created_by = auth.uid() and public.uniplanner_is_workspace_member(workspace_id)
  );
drop policy if exists "Authors or owners can delete group messages" on public.uniplanner_group_messages;
create policy "Authors or owners can delete group messages" on public.uniplanner_group_messages
  for delete to authenticated using (
    created_by = auth.uid() or exists (
      select 1 from public.uniplanner_workspace_members m
      where m.workspace_id = uniplanner_group_messages.workspace_id
        and m.user_id = auth.uid() and m.role = 'owner'
    )
  );


-- Workspace member display names.
-- Additive migration: does not modify personal planner data or existing collaboration records.
create table if not exists public.uniplanner_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 40),
  updated_at timestamptz not null default now()
);

alter table public.uniplanner_profiles enable row level security;

drop policy if exists "Users can read their own profile and workspace peers" on public.uniplanner_profiles;
create policy "Users can read their own profile and workspace peers"
  on public.uniplanner_profiles for select to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1
      from public.uniplanner_workspace_members mine
      join public.uniplanner_workspace_members peer
        on peer.workspace_id = mine.workspace_id
      where mine.user_id = auth.uid()
        and peer.user_id = uniplanner_profiles.user_id
    )
  );

drop policy if exists "Users can create their own profile" on public.uniplanner_profiles;
create policy "Users can create their own profile"
  on public.uniplanner_profiles for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Users can update their own profile" on public.uniplanner_profiles;
create policy "Users can update their own profile"
  on public.uniplanner_profiles for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());


-- Owner-approved access control; standalone migration is also provided.
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


-- Owner admin panel additions (also available as owner-admin-panel-migration.sql).
-- UniPlanner Owner Admin Panel (additive migration)
-- Preserves existing planner records and account identities. Safe to run after access-control-migration.sql.

alter table public.uniplanner_access
  add column if not exists email text;

alter table public.uniplanner_access
  drop constraint if exists uniplanner_access_status_check;
alter table public.uniplanner_access
  add constraint uniplanner_access_status_check
  check (status in ('pending', 'approved', 'revoked'));

-- Existing accounts keep their current statuses; new Auth accounts become pending automatically.
update public.uniplanner_access a
set email = u.email
from auth.users u
where u.id = a.user_id and a.email is distinct from u.email;

insert into public.uniplanner_access (user_id, email, status, approved_at, updated_at)
select u.id, u.email, 'pending', null, now()
from auth.users u
where not exists (select 1 from public.uniplanner_access a where a.user_id = u.id)
on conflict (user_id) do update set email = excluded.email;

create or replace function public.uniplanner_sync_access_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.uniplanner_access (user_id, email, status, approved_at, updated_at)
  values (new.id, new.email, 'pending', null, now())
  on conflict (user_id) do update set email = excluded.email, updated_at = now();
  return new;
end;
$$;

drop trigger if exists uniplanner_auth_user_access_sync on auth.users;
create trigger uniplanner_auth_user_access_sync
after insert or update of email on auth.users
for each row execute function public.uniplanner_sync_access_user();

create table if not exists public.uniplanner_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.uniplanner_admins enable row level security;
revoke all on table public.uniplanner_admins from public, anon, authenticated;

create or replace function public.uniplanner_is_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.uniplanner_admins a where a.user_id = auth.uid()
  );
$$;
revoke all on function public.uniplanner_is_admin() from public, anon;
grant execute on function public.uniplanner_is_admin() to authenticated;

create or replace function public.uniplanner_admin_list_users()
returns table(user_id uuid, email text, status text, created_at timestamptz, display_name text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.uniplanner_is_admin() then raise exception 'Owner permission required'; end if;
  return query
    select u.id, u.email::text, coalesce(a.status, 'pending'), u.created_at, p.display_name
    from auth.users u
    left join public.uniplanner_access a on a.user_id = u.id
    left join public.uniplanner_profiles p on p.user_id = u.id
    order by u.created_at desc;
end;
$$;
revoke all on function public.uniplanner_admin_list_users() from public, anon;
grant execute on function public.uniplanner_admin_list_users() to authenticated;

create or replace function public.uniplanner_admin_set_access(p_user_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.uniplanner_is_admin() then raise exception 'Owner permission required'; end if;
  if p_status not in ('approved', 'revoked') then raise exception 'Status must be approved or revoked'; end if;
  if p_user_id = auth.uid() and p_status = 'revoked' then raise exception 'You cannot revoke your own owner access'; end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then raise exception 'Account not found'; end if;
  insert into public.uniplanner_access (user_id, email, status, approved_at, approved_by, updated_at)
  select u.id, u.email, p_status, case when p_status = 'approved' then now() else null end, auth.uid(), now()
  from auth.users u where u.id = p_user_id
  on conflict (user_id) do update set
    email = excluded.email,
    status = excluded.status,
    approved_at = case when excluded.status = 'approved' then now() else null end,
    approved_by = auth.uid(),
    updated_at = now();
end;
$$;
revoke all on function public.uniplanner_admin_set_access(uuid, text) from public, anon;
grant execute on function public.uniplanner_admin_set_access(uuid, text) to authenticated;

create or replace function public.uniplanner_admin_list_memberships()
returns table(workspace_id uuid, workspace_name text, user_id uuid, email text, member_role text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.uniplanner_is_admin() then raise exception 'Owner permission required'; end if;
  return query
    select m.workspace_id, w.name, m.user_id, u.email::text, m.role::text
    from public.uniplanner_workspace_members m
    join public.uniplanner_workspaces w on w.id = m.workspace_id
    left join auth.users u on u.id = m.user_id
    order by w.name, m.role, u.email;
end;
$$;
revoke all on function public.uniplanner_admin_list_memberships() from public, anon;
grant execute on function public.uniplanner_admin_list_memberships() to authenticated;

create or replace function public.uniplanner_admin_remove_workspace_member(p_workspace_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.uniplanner_is_admin() then raise exception 'Owner permission required'; end if;
  if exists (
    select 1 from public.uniplanner_workspace_members
    where workspace_id = p_workspace_id and user_id = p_user_id and role = 'owner'
  ) then raise exception 'Workspace owners cannot be removed here. Transfer ownership first.'; end if;
  delete from public.uniplanner_workspace_members
  where workspace_id = p_workspace_id and user_id = p_user_id;
  if not found then raise exception 'Workspace membership not found'; end if;
end;
$$;
revoke all on function public.uniplanner_admin_remove_workspace_member(uuid, uuid) from public, anon;
grant execute on function public.uniplanner_admin_remove_workspace_member(uuid, uuid) to authenticated;

-- ONE-TIME OWNER BOOTSTRAP:
-- After running this migration, uncomment the statement below, replace with your exact
-- existing owner account email, run it once, then keep it commented.
-- insert into public.uniplanner_admins(user_id)
-- select id from auth.users where lower(email) = lower('YOUR_OWNER_EMAIL_HERE')
-- on conflict (user_id) do nothing;

-- No planner data is deleted or reset by this migration.
