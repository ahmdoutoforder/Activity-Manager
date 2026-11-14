-- UniPlanner: assignments, immutable submission versions, and private workspace file storage.
-- Additive migration. Existing workspace/task/note/chat data is not changed.
-- Bucket policy:
--   * private bucket, 20 MiB per file
--   * allow PDF, common Office files, plain text/CSV/JSON, ZIP, PNG and JPEG
--   * all workspace members can read/download assignment resources and submissions
--   * only assignment creators/workspace owners can upload original assignment resources
--   * members can upload submissions only into their own user-specific path
--   * uploads use unique object paths (upsert=false); there is no object UPDATE policy
--   * each submission upload creates a separate metadata row, retaining resubmission history

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'uniplanner-workspace-files',
  'uniplanner-workspace-files',
  false,
  20971520,
  array[
    'application/pdf',
    'application/msword',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'application/vnd.ms-powerpoint',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'application/vnd.ms-excel',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'text/plain',
    'text/csv',
    'application/json',
    'application/zip',
    'application/x-zip-compressed',
    'image/png',
    'image/jpeg'
  ]
)
on conflict (id) do nothing;

create table if not exists public.uniplanner_assignments (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  project_id uuid references public.uniplanner_projects(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete restrict,
  title text not null check (char_length(trim(title)) between 1 and 160),
  instructions text not null default '' check (char_length(instructions) <= 10000),
  due_at timestamptz,
  status text not null default 'open' check (status in ('open','closed','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists uniplanner_assignments_workspace_due
  on public.uniplanner_assignments(workspace_id, due_at);

create index if not exists uniplanner_assignments_project
  on public.uniplanner_assignments(project_id);

create table if not exists public.uniplanner_assignment_resources (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  assignment_id uuid not null references public.uniplanner_assignments(id) on delete cascade,
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  storage_path text not null unique,
  original_file_name text not null check (char_length(trim(original_file_name)) between 1 and 255),
  mime_type text not null,
  file_size_bytes bigint not null check (file_size_bytes between 1 and 20971520),
  created_at timestamptz not null default now()
);

create index if not exists uniplanner_assignment_resources_assignment
  on public.uniplanner_assignment_resources(workspace_id, assignment_id, created_at desc);

create table if not exists public.uniplanner_assignment_submissions (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.uniplanner_workspaces(id) on delete cascade,
  assignment_id uuid not null references public.uniplanner_assignments(id) on delete cascade,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  storage_path text not null unique,
  original_file_name text not null check (char_length(trim(original_file_name)) between 1 and 255),
  mime_type text not null,
  file_size_bytes bigint not null check (file_size_bytes between 1 and 20971520),
  note text not null default '' check (char_length(note) <= 3000),
  submitted_at timestamptz not null default now()
);

create index if not exists uniplanner_assignment_submissions_recent
  on public.uniplanner_assignment_submissions(workspace_id, assignment_id, submitted_at desc);

create index if not exists uniplanner_assignment_submissions_author
  on public.uniplanner_assignment_submissions(submitted_by, submitted_at desc);

create or replace function public.uniplanner_guard_assignment_scope()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $function$
begin
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id then
      raise exception 'An assignment ID cannot be changed';
    end if;
    if new.workspace_id is distinct from old.workspace_id then
      raise exception 'An assignment cannot be moved to another workspace';
    end if;
    if new.created_by is distinct from old.created_by then
      raise exception 'An assignment creator cannot be changed';
    end if;
    if new.created_at is distinct from old.created_at then
      raise exception 'An assignment creation time cannot be changed';
    end if;
  end if;

  if new.project_id is not null and not exists (
    select 1 from public.uniplanner_projects p
    where p.id = new.project_id and p.workspace_id = new.workspace_id
  ) then
    raise exception 'The assignment project must belong to the same workspace';
  end if;

  return new;
end;
$function$;

drop trigger if exists uniplanner_assignment_scope_guard on public.uniplanner_assignments;
create trigger uniplanner_assignment_scope_guard
before insert or update on public.uniplanner_assignments
for each row execute function public.uniplanner_guard_assignment_scope();

create or replace function public.uniplanner_guard_assignment_file_metadata()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $function$
declare expected_prefix text;
begin
  if not exists (
    select 1 from public.uniplanner_assignments a
    where a.id = new.assignment_id and a.workspace_id = new.workspace_id
  ) then
    raise exception 'The file assignment and workspace do not match';
  end if;

  if tg_table_name = 'uniplanner_assignment_resources' then
    expected_prefix := new.workspace_id::text || '/' || new.assignment_id::text || '/resources/';
    if left(new.storage_path, char_length(expected_prefix)) <> expected_prefix then
      raise exception 'Assignment resource path is not in the correct workspace folder';
    end if;
  else
    expected_prefix := new.workspace_id::text || '/' || new.assignment_id::text || '/submissions/' || new.submitted_by::text || '/';
    if left(new.storage_path, char_length(expected_prefix)) <> expected_prefix then
      raise exception 'Submission path must be inside the submitter-specific folder';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists uniplanner_assignment_resource_scope_guard on public.uniplanner_assignment_resources;
create trigger uniplanner_assignment_resource_scope_guard
before insert on public.uniplanner_assignment_resources
for each row execute function public.uniplanner_guard_assignment_file_metadata();

drop trigger if exists uniplanner_assignment_submission_scope_guard on public.uniplanner_assignment_submissions;
create trigger uniplanner_assignment_submission_scope_guard
before insert on public.uniplanner_assignment_submissions
for each row execute function public.uniplanner_guard_assignment_file_metadata();

alter table public.uniplanner_assignments enable row level security;
alter table public.uniplanner_assignment_resources enable row level security;
alter table public.uniplanner_assignment_submissions enable row level security;

revoke all on public.uniplanner_assignments from anon, public;
revoke all on public.uniplanner_assignment_resources from anon, public;
revoke all on public.uniplanner_assignment_submissions from anon, public;
grant select, insert, update on public.uniplanner_assignments to authenticated;
grant select, insert, delete on public.uniplanner_assignment_resources to authenticated;
grant select, insert, delete on public.uniplanner_assignment_submissions to authenticated;

drop policy if exists "Approved workspace members can read assignments" on public.uniplanner_assignments;
create policy "Approved workspace members can read assignments"
on public.uniplanner_assignments for select to authenticated
using (public.uniplanner_is_approved() and public.uniplanner_is_workspace_member(workspace_id));

drop policy if exists "Workspace members can create assignments" on public.uniplanner_assignments;
create policy "Workspace members can create assignments"
on public.uniplanner_assignments for insert to authenticated
with check (
  created_by = (select auth.uid())
  and public.uniplanner_is_approved()
  and public.uniplanner_is_workspace_member(workspace_id)
);

drop policy if exists "Assignment creators or workspace owners can update" on public.uniplanner_assignments;
create policy "Assignment creators or workspace owners can update"
on public.uniplanner_assignments for update to authenticated
using (
  public.uniplanner_is_approved()
  and public.uniplanner_is_workspace_member(workspace_id)
  and (created_by = (select auth.uid()) or public.uniplanner_is_workspace_owner(workspace_id))
)
with check (
  public.uniplanner_is_approved()
  and public.uniplanner_is_workspace_member(workspace_id)
  and (created_by = (select auth.uid()) or public.uniplanner_is_workspace_owner(workspace_id))
);

drop policy if exists "Workspace members can read assignment resources" on public.uniplanner_assignment_resources;
create policy "Workspace members can read assignment resources"
on public.uniplanner_assignment_resources for select to authenticated
using (
  public.uniplanner_is_approved()
  and public.uniplanner_is_workspace_member(workspace_id)
);

drop policy if exists "Assignment creators or owners can add resources" on public.uniplanner_assignment_resources;
create policy "Assignment creators or owners can add resources"
on public.uniplanner_assignment_resources for insert to authenticated
with check (
  uploaded_by = (select auth.uid())
  and public.uniplanner_is_approved()
  and public.uniplanner_is_workspace_member(workspace_id)
  and exists (
    select 1 from public.uniplanner_assignments a
    where a.id = assignment_id
      and a.workspace_id = uniplanner_assignment_resources.workspace_id
      and (a.created_by = (select auth.uid()) or public.uniplanner_is_workspace_owner(a.workspace_id))
  )
);

drop policy if exists "Resource uploaders or owners can remove resources" on public.uniplanner_assignment_resources;
create policy "Resource uploaders or owners can remove resources"
on public.uniplanner_assignment_resources for delete to authenticated
using (
  public.uniplanner_is_approved()
  and public.uniplanner_is_workspace_member(workspace_id)
  and (
    uploaded_by = (select auth.uid())
    or public.uniplanner_is_workspace_owner(workspace_id)
    or exists (
      select 1 from public.uniplanner_assignments a
      where a.id = assignment_id
        and a.workspace_id = uniplanner_assignment_resources.workspace_id
        and a.created_by = (select auth.uid())
    )
  )
);

drop policy if exists "Workspace members can read all assignment submissions" on public.uniplanner_assignment_submissions;
create policy "Workspace members can read all assignment submissions"
on public.uniplanner_assignment_submissions for select to authenticated
using (
  public.uniplanner_is_approved()
  and public.uniplanner_is_workspace_member(workspace_id)
);

drop policy if exists "Members can submit their own work" on public.uniplanner_assignment_submissions;
create policy "Members can submit their own work"
on public.uniplanner_assignment_submissions for insert to authenticated
with check (
  submitted_by = (select auth.uid())
  and public.uniplanner_is_approved()
  and public.uniplanner_is_workspace_member(workspace_id)
  and exists (
    select 1 from public.uniplanner_assignments a
    where a.id = assignment_id
      and a.workspace_id = uniplanner_assignment_submissions.workspace_id
      and a.status = 'open'
  )
);

drop policy if exists "Submitters can remove their own submissions" on public.uniplanner_assignment_submissions;
create policy "Submitters can remove their own submissions"
on public.uniplanner_assignment_submissions for delete to authenticated
using (
  public.uniplanner_is_approved()
  and public.uniplanner_is_workspace_member(workspace_id)
  and submitted_by = (select auth.uid())
);

-- All assignment and submission files live in a private bucket.
-- Members can download files for assignments in workspaces they belong to.
drop policy if exists "Workspace members can download assignment files" on storage.objects;
create policy "Workspace members can download assignment files"
on storage.objects for select to authenticated
using (
  bucket_id = 'uniplanner-workspace-files'
  and array_length(storage.foldername(name), 1) >= 3
  and split_part(name, '/', 3) in ('resources', 'submissions')
  and exists (
    select 1 from public.uniplanner_assignments a
    where a.id::text = split_part(name, '/', 2)
      and a.workspace_id::text = split_part(name, '/', 1)
      and public.uniplanner_is_approved()
      and public.uniplanner_is_workspace_member(a.workspace_id)
  )
);

drop policy if exists "Assignment creators and owners can upload resources" on storage.objects;
create policy "Assignment creators and owners can upload resources"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'uniplanner-workspace-files'
  and array_length(storage.foldername(name), 1) = 3
  and split_part(name, '/', 3) = 'resources'
  and split_part(name, '/', 4) <> ''
  and exists (
    select 1 from public.uniplanner_assignments a
    where a.id::text = split_part(name, '/', 2)
      and a.workspace_id::text = split_part(name, '/', 1)
      and public.uniplanner_is_approved()
      and public.uniplanner_is_workspace_member(a.workspace_id)
      and (a.created_by = (select auth.uid()) or public.uniplanner_is_workspace_owner(a.workspace_id))
  )
);

drop policy if exists "Members can upload their own assignment submissions" on storage.objects;
create policy "Members can upload their own assignment submissions"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'uniplanner-workspace-files'
  and array_length(storage.foldername(name), 1) = 4
  and split_part(name, '/', 3) = 'submissions'
  and split_part(name, '/', 4) = (select auth.uid())::text
  and split_part(name, '/', 5) <> ''
  and exists (
    select 1 from public.uniplanner_assignments a
    where a.id::text = split_part(name, '/', 2)
      and a.workspace_id::text = split_part(name, '/', 1)
      and public.uniplanner_is_approved()
      and public.uniplanner_is_workspace_member(a.workspace_id)
      and a.status = 'open'
  )
);

drop policy if exists "Workspace owners can remove assignment resources" on storage.objects;
create policy "Workspace owners can remove assignment resources"
on storage.objects for delete to authenticated
using (
  bucket_id = 'uniplanner-workspace-files'
  and split_part(name, '/', 3) = 'resources'
  and exists (
    select 1 from public.uniplanner_assignments a
    where a.id::text = split_part(name, '/', 2)
      and a.workspace_id::text = split_part(name, '/', 1)
      and public.uniplanner_is_approved()
      and public.uniplanner_is_workspace_member(a.workspace_id)
      and (
        a.created_by = (select auth.uid())
        or public.uniplanner_is_workspace_owner(a.workspace_id)
      )
  )
);

drop policy if exists "Submitters can remove their own assignment files" on storage.objects;
create policy "Submitters can remove their own assignment files"
on storage.objects for delete to authenticated
using (
  bucket_id = 'uniplanner-workspace-files'
  and split_part(name, '/', 3) = 'submissions'
  and split_part(name, '/', 4) = (select auth.uid())::text
  and exists (
    select 1 from public.uniplanner_assignments a
    where a.id::text = split_part(name, '/', 2)
      and a.workspace_id::text = split_part(name, '/', 1)
      and public.uniplanner_is_approved()
      and public.uniplanner_is_workspace_member(a.workspace_id)
  )
);

comment on table public.uniplanner_assignments is
  'Workspace assignments with instructions, due date and optional project link.';
comment on table public.uniplanner_assignment_resources is
  'Original assignment resource files stored in the private workspace bucket.';
comment on table public.uniplanner_assignment_submissions is
  'Append-only upload history. Each resubmission is a separate file/version visible to all workspace members.';
