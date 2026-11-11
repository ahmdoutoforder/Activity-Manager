-- Test-project alignment migration.
-- Production already contains these exact authorization workflows. This installs the
-- production-equivalent RPCs in the isolated test project if they are missing or stale.

CREATE OR REPLACE FUNCTION public.uniplanner_delete_workspace(target_workspace uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  caller_id uuid := auth.uid();
  is_site_admin boolean := coalesce(public.uniplanner_is_admin(), false);
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'Sign in before deleting a workspace';
  END IF;
  IF NOT coalesce(public.uniplanner_is_approved(), false) AND NOT is_site_admin THEN
    RAISE EXCEPTION 'Approved access is required';
  END IF;

  PERFORM 1
  FROM public.uniplanner_workspaces w
  WHERE w.id = target_workspace
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workspace not found or already deleted';
  END IF;

  IF NOT is_site_admin AND NOT EXISTS (
    SELECT 1
    FROM public.uniplanner_workspace_members m
    WHERE m.workspace_id = target_workspace
      AND m.user_id = caller_id
      AND m.role = 'owner'
  ) THEN
    RAISE EXCEPTION 'Only the workspace owner or a site admin can delete this workspace';
  END IF;

  DELETE FROM public.uniplanner_workspaces WHERE id = target_workspace;
END;
$function$;
REVOKE ALL ON FUNCTION public.uniplanner_delete_workspace(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.uniplanner_delete_workspace(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.uniplanner_leave_workspace(target_workspace uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  caller_id uuid := auth.uid();
  caller_role text;
  successor_id uuid;
BEGIN
  IF caller_id IS NULL THEN
    RAISE EXCEPTION 'Sign in before leaving a workspace';
  END IF;
  IF NOT coalesce(public.uniplanner_is_approved(), false) THEN
    RAISE EXCEPTION 'Approved access is required';
  END IF;

  -- Serialize leave/transfer/delete operations for this workspace.
  PERFORM 1
  FROM public.uniplanner_workspaces w
  WHERE w.id = target_workspace
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Workspace not found or already deleted';
  END IF;

  SELECT m.role INTO caller_role
  FROM public.uniplanner_workspace_members m
  WHERE m.workspace_id = target_workspace
    AND m.user_id = caller_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'You are not a member of this workspace';
  END IF;

  IF caller_role = 'owner' THEN
    SELECT m.user_id INTO successor_id
    FROM public.uniplanner_workspace_members m
    WHERE m.workspace_id = target_workspace
      AND m.user_id <> caller_id
    ORDER BY m.joined_at ASC, m.user_id ASC
    LIMIT 1
    FOR UPDATE;

    IF successor_id IS NULL THEN
      RAISE EXCEPTION 'You are the only member. Delete the workspace or invite another member before leaving';
    END IF;

    UPDATE public.uniplanner_workspace_members
    SET role = 'member'
    WHERE workspace_id = target_workspace AND user_id = caller_id;

    UPDATE public.uniplanner_workspace_members
    SET role = 'owner'
    WHERE workspace_id = target_workspace AND user_id = successor_id;
  END IF;

  DELETE FROM public.uniplanner_workspace_members
  WHERE workspace_id = target_workspace AND user_id = caller_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.uniplanner_leave_workspace(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.uniplanner_leave_workspace(uuid) TO authenticated;
