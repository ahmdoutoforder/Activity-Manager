-- UniPlanner: supporting indexes for assignment-related foreign keys.
-- Additive and safe for existing assignment records.

create index if not exists uniplanner_assignment_resources_assignment_id_idx
  on public.uniplanner_assignment_resources(assignment_id);

create index if not exists uniplanner_assignment_resources_uploaded_by_idx
  on public.uniplanner_assignment_resources(uploaded_by);

create index if not exists uniplanner_assignment_submissions_assignment_id_idx
  on public.uniplanner_assignment_submissions(assignment_id);

create index if not exists uniplanner_assignments_created_by_idx
  on public.uniplanner_assignments(created_by);
