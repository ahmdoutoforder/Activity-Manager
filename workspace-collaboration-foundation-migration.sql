-- UniPlanner collaboration foundation (additive; do not run on production without review)
-- Adds workspace classification and the first relational building blocks for projects,
-- resources, activity, invitations, and join requests. Existing rows/data are preserved.

begin;

alter table public.uniplanner_workspaces
  add column if not exists workspace_type text not null default 'study_group',
  add column if not exists visibility text not null default 'private',
  add column if not exists join_mode text not null default 'invite_only';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'uniplanner_workspaces_type_check') then
    alter table public.uniplanner_workspaces
      add constraint uniplanner_workspaces_type_check
      check (workspace_type in ('study_group', 'course'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'uniplanner_workspaces_visibility_check') then
    alter table public.uniplanner_workspaces
      add constraint uniplanner_workspaces_visibility_check
      check (visibility in ('private', 'discoverable'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'uniplanner_workspaces_join_mode_check') then
    alter table public.uniplanner_workspaces
      add constraint uniplanner_workspaces_join_mode_check
      check (join_mode in ('invite_only', 'request_to_join', 'open'));
  end if;
end $$;

-- Define the owner helper here as well so this migration does not depend on
-- the workspace lifecycle migration having created it first.
create or replace function public.uniplanner_is_workspace_owner(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public
as $
  select exists (
    select 1
    from public.uniplanner_workspace_members m
    where m.workspace_id = target_workspace
      and m.user_id = auth.uid()
      and m.role = 'owner'
  );
$;
revoke all on function public.uniplanner_is_workspace_owner(uuid) from public, anon;
grant execute on function public.uniplanner_is_workspace_owner(uuid) to authenticated;

create table if not exists public.uniplanner_workspace_invitations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  invited_email text not null check (char_length(trim(invited_email)) between 3 and 320),
  invited_user_id uuid references auth.users(id) on delete cascade,
  invited_by uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'revoked', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  responded_at timestamptz
);
create index if not exists uniplanner_workspace_invitations_workspace_status
  on public.uniplanner_workspace_invitations(workspace_id, status);
create index if not exists uniplanner_workspace_invitations_invitee
  on public.uniplanner_workspace_invitations(invited_user_id, status);

create table if not exists public.uniplanner_workspace_join_requests (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null default '' check (char_length(message) <= 1000),
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'cancelled')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  unique (workspace_id, user_id)
);
create index if not exists uniplanner_workspace_join_requests_workspace_status
  on public.uniplanner_workspace_join_requests(workspace_id, status);

create table if not exists public.uniplanner_projects (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 160),
  description text not null default '' check (char_length(description) <= 5000),
  status text not null default 'active' check (status in ('planned', 'active', 'completed', 'archived')),
  due_date date,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists uniplanner_projects_workspace_status
  on public.uniplanner_projects(workspace_id, status, created_at desc);

create table if not exists public.uniplanner_workspace_resources (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 180),
  description text not null default '' check (char_length(description) <= 3000),
  resource_url text check (resource_url is null or char_length(resource_url) <= 2048),
  resource_type text not null default 'link' check (resource_type in ('link', 'document', 'file_reference', 'reference')),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists uniplanner_workspace_resources_workspace_created
  on public.uniplanner_workspace_resources(workspace_id, created_at desc);

create table if not exists public.uniplanner_workspace_activity (
  id bigint generated always as identity primary key,
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  event_type text not null check (char_length(event_type) between 1 and 80),
  entity_type text not null check (char_length(entity_type) between 1 and 80),
  entity_id text,
  summary text not null check (char_length(summary) between 1 and 500),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists uniplanner_workspace_activity_recent
  on public.uniplanner_workspace_activity(workspace_id, created_at desc);

-- Keep project/resource ownership and workspace scope stable after creation.
create or replace function public.uniplanner_guard_workspace_content_scope()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $
begin
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'Workspace content cannot be moved to another workspace';
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'Content creator cannot be changed';
  end if;
  return new;
end;
$;
revoke all on function public.uniplanner_guard_workspace_content_scope() from public, anon, authenticated;

drop trigger if exists uniplanner_projects_scope_guard on public.uniplanner_projects;
create trigger uniplanner_projects_scope_guard
before update on public.uniplanner_projects
for each row execute function public.uniplanner_guard_workspace_content_scope();

drop trigger if exists uniplanner_resources_scope_guard on public.uniplanner_workspace_resources;
create trigger uniplanner_resources_scope_guard
before update on public.uniplanner_workspace_resources
for each row execute function public.uniplanner_guard_workspace_content_scope();

alter table public.uniplanner_workspace_invitations enable row level security;
alter table public.uniplanner_workspace_join_requests enable row level security;
alter table public.uniplanner_projects enable row level security;
alter table public.uniplanner_workspace_resources enable row level security;
alter table public.uniplanner_workspace_activity enable row level security;

-- Invitation details are visible only to the workspace owner and the intended account.
drop policy if exists "Workspace owners and invitees can read invitations" on public.uniplanner_workspace_invitations;
create policy "Workspace owners and invitees can read invitations"
  on public.uniplanner_workspace_invitations for select to authenticated
  using (
    public.uniplanner_is_approved()
    and (
      public.uniplanner_is_workspace_owner(workspace_id)
      or invited_user_id = auth.uid()
      or lower(invited_email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    )
  );

drop policy if exists "Workspace owners can create invitations" on public.uniplanner_workspace_invitations;
create policy "Workspace owners can create invitations"
  on public.uniplanner_workspace_invitations for insert to authenticated
  with check (
    public.uniplanner_is_approved()
    and invited_by = auth.uid()
    and public.uniplanner_is_workspace_owner(workspace_id)
  );

drop policy if exists "Workspace owners can manage invitations" on public.uniplanner_workspace_invitations;
create policy "Workspace owners can manage invitations"
  on public.uniplanner_workspace_invitations for update to authenticated
  using (public.uniplanner_is_approved() and public.uniplanner_is_workspace_owner(workspace_id))
  with check (public.uniplanner_is_approved() and public.uniplanner_is_workspace_owner(workspace_id));

-- A user can view their own requests; workspace owners can review requests for their workspace.
drop policy if exists "Requesters and owners can read join requests" on public.uniplanner_workspace_join_requests;
create policy "Requesters and owners can read join requests"
  on public.uniplanner_workspace_join_requests for select to authenticated
  using (
    public.uniplanner_is_approved()
    and (user_id = auth.uid() or public.uniplanner_is_workspace_owner(workspace_id))
  );

drop policy if exists "Approved users can request to join" on public.uniplanner_workspace_join_requests;
create policy "Approved users can request to join"
  on public.uniplanner_workspace_join_requests for insert to authenticated
  with check (
    public.uniplanner_is_approved()
    and user_id = auth.uid()
    and exists (
      select 1 from public.uniplanner_workspaces w
      where w.id = workspace_id
        and w.visibility = 'discoverable'
        and w.join_mode = 'request_to_join'
    )
    and not public.uniplanner_is_workspace_member(workspace_id)
  );

drop policy if exists "Requesters can cancel and owners can review join requests" on public.uniplanner_workspace_join_requests;
create policy "Requesters can cancel and owners can review join requests"
  on public.uniplanner_workspace_join_requests for update to authenticated
  using (
    public.uniplanner_is_approved()
    and (user_id = auth.uid() or public.uniplanner_is_workspace_owner(workspace_id))
  )
  with check (
    public.uniplanner_is_approved()
    and (
      (user_id = auth.uid() and status = 'cancelled')
      or public.uniplanner_is_workspace_owner(workspace_id)
    )
  );

-- Projects/resources are workspace-member content. Inserts must identify the current user.
drop policy if exists "Workspace members can read projects" on public.uniplanner_projects;
create policy "Workspace members can read projects"
  on public.uniplanner_projects for select to authenticated
  using (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Workspace members can create projects" on public.uniplanner_projects;
create policy "Workspace members can create projects"
  on public.uniplanner_projects for insert to authenticated
  with check (public.uniplanner_is_approved() and created_by = auth.uid() and public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Workspace members can update projects" on public.uniplanner_projects;
create policy "Workspace members can update projects"
  on public.uniplanner_projects for update to authenticated
  using (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id))
  with check (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Workspace members can delete projects" on public.uniplanner_projects;
create policy "Workspace members can delete projects"
  on public.uniplanner_projects for delete to authenticated
  using (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id));

drop policy if exists "Workspace members can read resources" on public.uniplanner_workspace_resources;
create policy "Workspace members can read resources"
  on public.uniplanner_workspace_resources for select to authenticated
  using (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Workspace members can create resources" on public.uniplanner_workspace_resources;
create policy "Workspace members can create resources"
  on public.uniplanner_workspace_resources for insert to authenticated
  with check (public.uniplanner_is_approved() and created_by = auth.uid() and public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Workspace members can update resources" on public.uniplanner_workspace_resources;
create policy "Workspace members can update resources"
  on public.uniplanner_workspace_resources for update to authenticated
  using (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id))
  with check (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Workspace members can delete resources" on public.uniplanner_workspace_resources;
create policy "Workspace members can delete resources"
  on public.uniplanner_workspace_resources for delete to authenticated
  using (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id));

drop policy if exists "Workspace members can read activity" on public.uniplanner_workspace_activity;
create policy "Workspace members can read activity"
  on public.uniplanner_workspace_activity for select to authenticated
  using (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id));
drop policy if exists "Workspace members can create activity" on public.uniplanner_workspace_activity;
create policy "Workspace members can create activity"
  on public.uniplanner_workspace_activity for insert to authenticated
  with check (public.uniplanner_is_approved() and actor_id = auth.uid() and public.uniplanner_is_workspace_member(workspace_id));

commit;

-- Deliberately not wired into the UI yet. The next implementation step adds safe RPCs
-- for invitation acceptance, join-request review, and workspace role/settings changes.
-- Test this migration on the isolated Supabase test project first. Never apply to production
-- until its policies and workflows have been verified with two test accounts.
