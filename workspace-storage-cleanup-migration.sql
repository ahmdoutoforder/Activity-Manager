-- UniPlanner: retain an authorized cleanup job when a workspace is deleted.
-- Storage objects are separate from Postgres rows. The AFTER DELETE trigger records
-- who may clean the private workspace file prefix after relational rows cascade away.
-- The job is inserted in the same transaction as workspace deletion.

create table if not exists public.uniplanner_workspace_storage_cleanup_jobs (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null,
  requested_by uuid,
  created_at timestamptz not null default now()
);

create index if not exists uniplanner_workspace_storage_cleanup_workspace
  on public.uniplanner_workspace_storage_cleanup_jobs(workspace_id);

create index if not exists uniplanner_workspace_storage_cleanup_requester
  on public.uniplanner_workspace_storage_cleanup_jobs(requested_by);

alter table public.uniplanner_workspace_storage_cleanup_jobs enable row level security;

revoke all on public.uniplanner_workspace_storage_cleanup_jobs from anon, public;
grant select, delete on public.uniplanner_workspace_storage_cleanup_jobs to authenticated;

drop policy if exists "Requesters and admins can read storage cleanup jobs"
  on public.uniplanner_workspace_storage_cleanup_jobs;
create policy "Requesters and admins can read storage cleanup jobs"
on public.uniplanner_workspace_storage_cleanup_jobs for select to authenticated
using (
  requested_by = (select auth.uid())
  or public.uniplanner_is_admin()
);

drop policy if exists "Requesters and admins can finish storage cleanup jobs"
  on public.uniplanner_workspace_storage_cleanup_jobs;
create policy "Requesters and admins can finish storage cleanup jobs"
on public.uniplanner_workspace_storage_cleanup_jobs for delete to authenticated
using (
  requested_by = (select auth.uid())
  or public.uniplanner_is_admin()
);

create or replace function public.uniplanner_capture_workspace_storage_cleanup()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  insert into public.uniplanner_workspace_storage_cleanup_jobs(workspace_id, requested_by)
  values (old.id, auth.uid());
  return old;
end;
$function$;

revoke all on function public.uniplanner_capture_workspace_storage_cleanup() from public, anon, authenticated;

drop trigger if exists uniplanner_workspace_storage_cleanup_capture on public.uniplanner_workspaces;
create trigger uniplanner_workspace_storage_cleanup_capture
after delete on public.uniplanner_workspaces
for each row execute function public.uniplanner_capture_workspace_storage_cleanup();

-- Preserve normal member downloads while the workspace exists, and let only the
-- recorded requester/site admin list the prefix after the workspace rows are gone.
drop policy if exists "Workspace members can download assignment files" on storage.objects;
create policy "Workspace members can download assignment files"
on storage.objects for select to authenticated
using (
  bucket_id = 'uniplanner-workspace-files'
  and array_length(storage.foldername(name), 1) >= 3
  and split_part(name, '/', 3) in ('resources', 'submissions')
  and (
    exists (
      select 1 from public.uniplanner_assignments a
      where a.id::text = split_part(name, '/', 2)
        and a.workspace_id::text = split_part(name, '/', 1)
        and public.uniplanner_is_approved()
        and public.uniplanner_is_workspace_member(a.workspace_id)
    )
    or exists (
      select 1 from public.uniplanner_workspace_storage_cleanup_jobs j
      where j.workspace_id::text = split_part(name, '/', 1)
        and (j.requested_by = (select auth.uid()) or public.uniplanner_is_admin())
    )
  )
);

drop policy if exists "Workspace owners can remove assignment resources" on storage.objects;
create policy "Workspace owners can remove assignment resources"
on storage.objects for delete to authenticated
using (
  bucket_id = 'uniplanner-workspace-files'
  and split_part(name, '/', 3) = 'resources'
  and (
    exists (
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
    or exists (
      select 1 from public.uniplanner_workspace_storage_cleanup_jobs j
      where j.workspace_id::text = split_part(name, '/', 1)
        and (j.requested_by = (select auth.uid()) or public.uniplanner_is_admin())
    )
  )
);

drop policy if exists "Submitters can remove their own assignment files" on storage.objects;
create policy "Submitters can remove their own assignment files"
on storage.objects for delete to authenticated
using (
  bucket_id = 'uniplanner-workspace-files'
  and split_part(name, '/', 3) = 'submissions'
  and (
    (
      split_part(name, '/', 4) = (select auth.uid())::text
      and exists (
        select 1 from public.uniplanner_assignments a
        where a.id::text = split_part(name, '/', 2)
          and a.workspace_id::text = split_part(name, '/', 1)
          and public.uniplanner_is_approved()
          and public.uniplanner_is_workspace_member(a.workspace_id)
      )
    )
    or exists (
      select 1 from public.uniplanner_workspace_storage_cleanup_jobs j
      where j.workspace_id::text = split_part(name, '/', 1)
        and (j.requested_by = (select auth.uid()) or public.uniplanner_is_admin())
    )
  )
);

comment on table public.uniplanner_workspace_storage_cleanup_jobs is
  'Temporary authorization records allowing the workspace deleter/admin to remove private Storage objects after workspace rows cascade away.';
