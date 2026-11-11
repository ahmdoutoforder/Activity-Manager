-- UniPlanner discoverable workspace and join-request flow
-- Adds a limited discovery surface for approved accounts and safe request creation.

begin;

-- Allow a user to re-request after an earlier request was rejected or cancelled,
-- while still guaranteeing at most one pending request per user/workspace.
alter table public.uniplanner_workspace_join_requests
  drop constraint if exists uniplanner_workspace_join_requests_workspace_id_user_id_key;
create unique index if not exists uniplanner_workspace_join_requests_pending_unique
  on public.uniplanner_workspace_join_requests(workspace_id, user_id)
  where status = 'pending';

-- Requests must go through the validated RPC; no direct client insert path.
drop policy if exists "Approved users can request to join"
  on public.uniplanner_workspace_join_requests;

create or replace function public.uniplanner_discover_workspaces(p_search text default null)
returns table(
  workspace_id uuid,
  workspace_name text,
  workspace_type text,
  created_at timestamptz,
  member_count bigint,
  request_status text
)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $fn$
declare
  caller_id uuid := auth.uid();
  search_value text := nullif(trim(coalesce(p_search, '')), '');
begin
  if caller_id is null then raise exception 'Sign in to discover study workspaces'; end if;
  if not coalesce(public.uniplanner_is_approved(), false) then
    raise exception 'Approved UniPlanner access is required';
  end if;
  if search_value is not null and char_length(search_value) > 80 then
    raise exception 'Search text is too long';
  end if;

  return query
  select w.id,
         w.name,
         w.workspace_type,
         w.created_at,
         count(m.user_id)::bigint,
         recent.status
  from public.uniplanner_workspaces w
  left join public.uniplanner_workspace_members m
    on m.workspace_id = w.id
  left join lateral (
    select jr.status
    from public.uniplanner_workspace_join_requests jr
    where jr.workspace_id = w.id and jr.user_id = caller_id
    order by jr.created_at desc
    limit 1
  ) recent on true
  where w.visibility = 'discoverable'
    and w.join_mode = 'request_to_join'
    and (search_value is null or w.name ilike '%' || search_value || '%')
    and not exists (
      select 1 from public.uniplanner_workspace_members mine
      where mine.workspace_id = w.id and mine.user_id = caller_id
    )
  group by w.id, w.name, w.workspace_type, w.created_at, recent.status
  order by w.created_at desc
  limit 50;
end;
$fn$;

create or replace function public.uniplanner_request_workspace_join(
  target_workspace uuid,
  request_message text default ''
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $fn$
declare
  caller_id uuid := auth.uid();
  request_id uuid;
  clean_message text := coalesce(trim(request_message), '');
begin
  if caller_id is null then raise exception 'Sign in before requesting to join'; end if;
  if not coalesce(public.uniplanner_is_approved(), false) then
    raise exception 'Approved UniPlanner access is required';
  end if;
  if char_length(clean_message) > 1000 then
    raise exception 'Join request message is too long';
  end if;

  perform 1 from public.uniplanner_workspaces w
  where w.id = target_workspace
    and w.visibility = 'discoverable'
    and w.join_mode = 'request_to_join'
  for update;
  if not found then raise exception 'This workspace is not accepting join requests'; end if;

  if public.uniplanner_is_workspace_member(target_workspace) then
    raise exception 'You are already a member of this workspace';
  end if;

  insert into public.uniplanner_workspace_join_requests(workspace_id, user_id, message, status)
  values(target_workspace, caller_id, clean_message, 'pending')
  returning id into request_id;

  return request_id;
exception
  when unique_violation then
    raise exception 'You already have a pending request for this workspace';
end;
$fn$;

revoke all on function public.uniplanner_discover_workspaces(text) from public, anon;
grant execute on function public.uniplanner_discover_workspaces(text) to authenticated;
revoke all on function public.uniplanner_request_workspace_join(uuid, text) from public, anon;
grant execute on function public.uniplanner_request_workspace_join(uuid, text) to authenticated;

commit;
