-- UniPlanner workspace lifecycle controls
-- Additive migration: no existing workspace or personal data is changed by applying this file.
-- Workspace deletion cascades only through rows owned by that workspace.
-- Personal planner data (uniplanner_data) is not referenced or modified.

create or replace function public.uniplanner_delete_workspace(target_workspace uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_id uuid := auth.uid();
  is_site_admin boolean := coalesce(public.uniplanner_is_admin(), false);
begin
  if caller_id is null then
    raise exception 'Sign in before deleting a workspace';
  end if;
  if not coalesce(public.uniplanner_is_approved(), false) and not is_site_admin then
    raise exception 'Approved access is required';
  end if;

  perform 1
  from public.uniplanner_workspaces w
  where w.id = target_workspace
  for update;

  if not found then
    raise exception 'Workspace not found or already deleted';
  end if;

  if not is_site_admin and not exists (
    select 1
    from public.uniplanner_workspace_members m
    where m.workspace_id = target_workspace
      and m.user_id = caller_id
      and m.role = 'owner'
  ) then
    raise exception 'Only the workspace owner or a site admin can delete this workspace';
  end if;

  delete from public.uniplanner_workspaces where id = target_workspace;
end;
$$;

revoke all on function public.uniplanner_delete_workspace(uuid) from public, anon;
grant execute on function public.uniplanner_delete_workspace(uuid) to authenticated;


create or replace function public.uniplanner_leave_workspace(target_workspace uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  caller_id uuid := auth.uid();
  caller_role text;
  successor_id uuid;
begin
  if caller_id is null then
    raise exception 'Sign in before leaving a workspace';
  end if;
  if not coalesce(public.uniplanner_is_approved(), false) then
    raise exception 'Approved access is required';
  end if;

  -- Serialize leave/transfer/delete operations for this workspace.
  perform 1
  from public.uniplanner_workspaces w
  where w.id = target_workspace
  for update;

  if not found then
    raise exception 'Workspace not found or already deleted';
  end if;

  select m.role into caller_role
  from public.uniplanner_workspace_members m
  where m.workspace_id = target_workspace
    and m.user_id = caller_id
  for update;

  if not found then
    raise exception 'You are not a member of this workspace';
  end if;

  if caller_role = 'owner' then
    select m.user_id into successor_id
    from public.uniplanner_workspace_members m
    where m.workspace_id = target_workspace
      and m.user_id <> caller_id
    order by m.joined_at asc, m.user_id asc
    limit 1
    for update;

    if successor_id is null then
      raise exception 'You are the only member. Delete the workspace or invite another member before leaving';
    end if;

    update public.uniplanner_workspace_members
    set role = 'member'
    where workspace_id = target_workspace and user_id = caller_id;

    update public.uniplanner_workspace_members
    set role = 'owner'
    where workspace_id = target_workspace and user_id = successor_id;
  end if;

  delete from public.uniplanner_workspace_members
  where workspace_id = target_workspace and user_id = caller_id;
end;
$$;

revoke all on function public.uniplanner_leave_workspace(uuid) from public, anon;
grant execute on function public.uniplanner_leave_workspace(uuid) to authenticated;

-- SECURITY DEFINER helper avoids recursive RLS evaluation in membership policies.
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

-- Prevent a workspace owner from bypassing ownership transfer by deleting their
-- own membership row directly. Non-owners can leave; owners can remove other members.
drop policy if exists "Members can leave or owners can remove members"
  on public.uniplanner_workspace_members;
create policy "Members can leave or owners can remove members"
  on public.uniplanner_workspace_members
  for delete to authenticated
  using (
    (user_id = auth.uid() and role <> 'owner')
    or (
      user_id <> auth.uid()
      and public.uniplanner_is_workspace_owner(workspace_id)
    )
  );
