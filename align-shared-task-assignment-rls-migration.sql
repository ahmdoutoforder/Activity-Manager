-- Keep shared-task updates constrained to current workspace members and valid assignees.
-- The BEFORE trigger remains a second independent guard for assignment integrity.
ALTER POLICY "Members can update shared tasks"
ON public.uniplanner_shared_tasks
USING (public.uniplanner_is_approved() AND public.uniplanner_is_workspace_member(workspace_id))
WITH CHECK (
  public.uniplanner_is_approved()
  AND public.uniplanner_is_workspace_member(workspace_id)
  AND (
    assigned_to IS NULL
    OR EXISTS (
      SELECT 1
      FROM public.uniplanner_workspace_members assignee
      WHERE assignee.workspace_id = uniplanner_shared_tasks.workspace_id
        AND assignee.user_id = uniplanner_shared_tasks.assigned_to
    )
  )
);
