-- UniPlanner: align security-definer permissions and finish RLS init-plan optimization.
-- The public RPCs remain callable by authenticated users where the application requires them.
-- Internal event-trigger functions are not exposed as RPC endpoints.

REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;

-- Pin every SECURITY DEFINER function that exists in this project. The isolated
-- test project may intentionally lag production in a small number of RPCs.
DO $hardening$
DECLARE
  signature text;
  signatures text[] := ARRAY[
    'public.uniplanner_is_workspace_member(uuid)',
    'public.uniplanner_create_workspace(text)',
    'public.uniplanner_invite_member(uuid, text)',
    'public.uniplanner_is_approved()',
    'public.uniplanner_sync_access_user()',
    'public.uniplanner_is_admin()',
    'public.uniplanner_admin_list_users()',
    'public.uniplanner_admin_set_access(uuid, text)',
    'public.uniplanner_admin_list_memberships()',
    'public.uniplanner_admin_remove_workspace_member(uuid, uuid)',
    'public.uniplanner_delete_workspace(uuid)',
    'public.uniplanner_leave_workspace(uuid)',
    'public.uniplanner_is_workspace_owner(uuid)',
    'public.uniplanner_workspace_accepts_join_request(uuid)',
    'public.uniplanner_guard_workspace_content_scope()',
    'public.uniplanner_review_workspace_join_request(uuid, text)',
    'public.uniplanner_respond_workspace_invitation(uuid, text)',
    'public.uniplanner_discover_workspaces(text)',
    'public.uniplanner_request_workspace_join(uuid, text)',
    'public.uniplanner_cancel_workspace_join_request(uuid)'
  ];
BEGIN
  FOREACH signature IN ARRAY signatures LOOP
    IF to_regprocedure(signature) IS NOT NULL THEN
      EXECUTE format('ALTER FUNCTION %s SET search_path = pg_catalog, public', signature);
    END IF;
  END LOOP;
END
$hardening$;

-- These predicates retain the same authorization logic; only statement-constant
-- auth context lookups are moved into scalar subqueries for init-plan evaluation.
ALTER POLICY "Creators or owners can delete shared tasks" ON public.uniplanner_shared_tasks
USING (((created_by = (select auth.uid())) OR (EXISTS (
  SELECT 1 FROM public.uniplanner_workspace_members m
  WHERE m.workspace_id = uniplanner_shared_tasks.workspace_id
    AND m.user_id = (select auth.uid()) AND m.role = 'owner'
))));
ALTER POLICY "Members can create shared tasks" ON public.uniplanner_shared_tasks
WITH CHECK ((created_by = (select auth.uid())) AND public.uniplanner_is_workspace_member(workspace_id));
ALTER POLICY "Workspace owners and invitees can read invitations" ON public.uniplanner_workspace_invitations
USING (public.uniplanner_is_approved()
  AND (public.uniplanner_is_workspace_owner(workspace_id)
    OR invited_user_id = (select auth.uid())
    OR lower(invited_email) = lower((select auth.jwt()) ->> 'email')));
ALTER POLICY "Workspace creators can add themselves" ON public.uniplanner_workspace_members
WITH CHECK (user_id = (select auth.uid()) AND role = 'owner' AND EXISTS (
  SELECT 1 FROM public.uniplanner_workspaces w
  WHERE w.id = uniplanner_workspace_members.workspace_id
    AND w.created_by = (select auth.uid())
));
ALTER POLICY "Owners can delete workspaces" ON public.uniplanner_workspaces
USING (EXISTS (
  SELECT 1 FROM public.uniplanner_workspace_members m
  WHERE m.workspace_id = uniplanner_workspaces.id
    AND m.user_id = (select auth.uid()) AND m.role = 'owner'
));
ALTER POLICY "Owners can rename workspaces" ON public.uniplanner_workspaces
USING (EXISTS (
  SELECT 1 FROM public.uniplanner_workspace_members m
  WHERE m.workspace_id = uniplanner_workspaces.id
    AND m.user_id = (select auth.uid()) AND m.role = 'owner'
));
ALTER POLICY "Users can create workspaces" ON public.uniplanner_workspaces
WITH CHECK (created_by = (select auth.uid()));
