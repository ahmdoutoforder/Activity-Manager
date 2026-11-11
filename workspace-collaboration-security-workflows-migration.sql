-- UniPlanner collaboration security workflows
-- TEST PROJECT ONLY until a separately reviewed production rollout is approved.
-- Tightens direct table writes and adds atomic server-side invitation/join-request actions.
-- Existing personal planner data and existing workspace content are preserved.

begin;

create or replace function public.uniplanner_invite_member(target_workspace uuid, invite_email text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $fn$
declare
  caller_id uuid := auth.uid();
  normalized_email text := lower(trim(invite_email));
  invited_user uuid;
begin
  if caller_id is null then raise exception 'Sign in before inviting a member'; end if;
  if not coalesce(public.uniplanner_is_approved(), false) then raise exception 'Your UniPlanner account is not approved'; end if;
  if normalized_email is null or char_length(normalized_email) < 3 or char_length(normalized_email) > 320 then
    raise exception 'Enter a valid account email';
  end if;

  perform 1 from public.uniplanner_workspaces w where w.id = target_workspace for update;
  if not found then raise exception 'Workspace not found'; end if;
  if not exists (
    select 1 from public.uniplanner_workspace_members m
    where m.workspace_id = target_workspace and m.user_id = caller_id and m.role = 'owner'
  ) then raise exception 'Only workspace owners can invite members'; end if;

  select u.id into invited_user from auth.users u where lower(u.email) = normalized_email limit 1;
  if invited_user is null then raise exception 'No registered account found for that email'; end if;
  if not exists (select 1 from public.uniplanner_access a where a.user_id = invited_user and a.status = 'approved') then
    raise exception 'This account has not been approved for UniPlanner';
  end if;
  if exists (select 1 from public.uniplanner_workspace_members m where m.workspace_id = target_workspace and m.user_id = invited_user) then
    raise exception 'This account is already a workspace member';
  end if;
  if exists (
    select 1 from public.uniplanner_workspace_invitations i
    where i.workspace_id = target_workspace and i.invited_user_id = invited_user
      and i.status = 'pending' and i.expires_at > now()
  ) then raise exception 'A pending invitation already exists for this account'; end if;

  insert into public.uniplanner_workspace_invitations
    (workspace_id, invited_email, invited_user_id, invited_by)
  values (target_workspace, normalized_email, invited_user, caller_id);
end;
$fn$;

create or replace function public.uniplanner_review_workspace_join_request(p_request_id uuid, p_decision text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $fn$
declare
  caller_id uuid := auth.uid();
  request_row public.uniplanner_workspace_join_requests%rowtype;
begin
  if caller_id is null then raise exception 'Sign in before reviewing requests'; end if;
  if not coalesce(public.uniplanner_is_approved(), false) then raise exception 'Approved access is required'; end if;
  if p_decision not in ('approve', 'reject') then raise exception 'Decision must be approve or reject'; end if;

  select * into request_row from public.uniplanner_workspace_join_requests
  where id = p_request_id for update;
  if not found then raise exception 'Join request not found'; end if;
  if not public.uniplanner_is_workspace_owner(request_row.workspace_id) then
    raise exception 'Only the workspace owner can review join requests';
  end if;
  if request_row.status <> 'pending' then raise exception 'This join request has already been handled'; end if;

  if p_decision = 'approve' then
    if not exists (select 1 from public.uniplanner_access a where a.user_id = request_row.user_id and a.status = 'approved') then
      raise exception 'This account is not approved for UniPlanner';
    end if;
    insert into public.uniplanner_workspace_members(workspace_id, user_id, role)
    values (request_row.workspace_id, request_row.user_id, 'member')
    on conflict (workspace_id, user_id) do nothing;
    update public.uniplanner_workspace_join_requests
    set status = 'approved', reviewed_at = now(), reviewed_by = caller_id
    where id = p_request_id;
    insert into public.uniplanner_workspace_activity
      (workspace_id, actor_id, event_type, entity_type, entity_id, summary)
    values (request_row.workspace_id, caller_id, 'member_joined', 'join_request', p_request_id::text, 'A join request was approved');
  else
    update public.uniplanner_workspace_join_requests
    set status = 'rejected', reviewed_at = now(), reviewed_by = caller_id
    where id = p_request_id;
  end if;
end;
$fn$;

create or replace function public.uniplanner_respond_workspace_invitation(p_invitation_id uuid, p_decision text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $fn$
declare
  caller_id uuid := auth.uid();
  invitation_row public.uniplanner_workspace_invitations%rowtype;
  caller_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
begin
  if caller_id is null then raise exception 'Sign in before responding to an invitation'; end if;
  if not coalesce(public.uniplanner_is_approved(), false) then raise exception 'Approved access is required'; end if;
  if p_decision not in ('accept', 'decline') then raise exception 'Decision must be accept or decline'; end if;

  select * into invitation_row from public.uniplanner_workspace_invitations
  where id = p_invitation_id for update;
  if not found then raise exception 'Invitation not found'; end if;
  if invitation_row.invited_user_id is distinct from caller_id
     and lower(invitation_row.invited_email) <> caller_email then
    raise exception 'This invitation belongs to another account';
  end if;
  if invitation_row.status <> 'pending' then raise exception 'This invitation is no longer pending'; end if;
  if invitation_row.expires_at <= now() then
    update public.uniplanner_workspace_invitations set status = 'expired' where id = p_invitation_id;
    raise exception 'This invitation has expired';
  end if;

  if p_decision = 'accept' then
    insert into public.uniplanner_workspace_members(workspace_id, user_id, role)
    values (invitation_row.workspace_id, caller_id, 'member')
    on conflict (workspace_id, user_id) do nothing;
    update public.uniplanner_workspace_invitations
    set status = 'accepted', responded_at = now(), invited_user_id = caller_id
    where id = p_invitation_id;
    insert into public.uniplanner_workspace_activity
      (workspace_id, actor_id, event_type, entity_type, entity_id, summary)
    values (invitation_row.workspace_id, caller_id, 'member_joined', 'invitation', p_invitation_id::text, 'A workspace invitation was accepted');
  else
    update public.uniplanner_workspace_invitations
    set status = 'declined', responded_at = now(), invited_user_id = caller_id
    where id = p_invitation_id;
  end if;
end;
$fn$;

revoke all on function public.uniplanner_invite_member(uuid, text) from public, anon;
grant execute on function public.uniplanner_invite_member(uuid, text) to authenticated;
revoke all on function public.uniplanner_review_workspace_join_request(uuid, text) from public, anon;
grant execute on function public.uniplanner_review_workspace_join_request(uuid, text) to authenticated;
revoke all on function public.uniplanner_respond_workspace_invitation(uuid, text) from public, anon;
grant execute on function public.uniplanner_respond_workspace_invitation(uuid, text) to authenticated;

drop policy if exists "Workspace owners can manage invitations" on public.uniplanner_workspace_invitations;

drop policy if exists "Requesters can cancel and owners can review join requests" on public.uniplanner_workspace_join_requests;
create policy "Requesters can cancel their own pending join requests"
  on public.uniplanner_workspace_join_requests for update to authenticated
  using (public.uniplanner_is_approved() and user_id = auth.uid() and status = 'pending')
  with check (public.uniplanner_is_approved() and user_id = auth.uid() and status = 'cancelled');

drop policy if exists "Workspace members can delete projects" on public.uniplanner_projects;
create policy "Creators or owners can delete projects"
  on public.uniplanner_projects for delete to authenticated
  using (public.uniplanner_is_approved() and
    (created_by = auth.uid() or public.uniplanner_is_workspace_owner(workspace_id)));

drop policy if exists "Workspace members can delete resources" on public.uniplanner_workspace_resources;
create policy "Creators or owners can delete resources"
  on public.uniplanner_workspace_resources for delete to authenticated
  using (public.uniplanner_is_approved() and
    (created_by = auth.uid() or public.uniplanner_is_workspace_owner(workspace_id)));

drop policy if exists "Workspace members can create activity" on public.uniplanner_workspace_activity;

commit;
