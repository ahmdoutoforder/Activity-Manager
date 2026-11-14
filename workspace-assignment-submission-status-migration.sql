-- UniPlanner: enforce that assignment submissions are only accepted while open.
-- The interface hides the upload controls for closed/archived assignments, but
-- Postgres also enforces this for direct API/Storage requests.

drop policy if exists "Members can submit their own work"
  on public.uniplanner_assignment_submissions;

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

drop policy if exists "Members can upload their own assignment submissions"
  on storage.objects;

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
