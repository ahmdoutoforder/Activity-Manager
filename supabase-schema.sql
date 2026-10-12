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
as $
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
$;
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
