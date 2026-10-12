-- UniPlanner Owner Admin Panel (additive migration)
-- Preserves existing planner records and account identities. Safe to run after access-control-migration.sql.

alter table public.uniplanner_access
  add column if not exists email text;

alter table public.uniplanner_access
  drop constraint if exists uniplanner_access_status_check;
alter table public.uniplanner_access
  add constraint uniplanner_access_status_check
  check (status in ('pending', 'approved', 'revoked'));

-- Existing accounts keep their current statuses; new Auth accounts become pending automatically.
update public.uniplanner_access a
set email = u.email
from auth.users u
where u.id = a.user_id and a.email is distinct from u.email;

insert into public.uniplanner_access (user_id, email, status, approved_at, updated_at)
select u.id, u.email, 'pending', null, now()
from auth.users u
where not exists (select 1 from public.uniplanner_access a where a.user_id = u.id)
on conflict (user_id) do update set email = excluded.email;

create or replace function public.uniplanner_sync_access_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.uniplanner_access (user_id, email, status, approved_at, updated_at)
  values (new.id, new.email, 'pending', null, now())
  on conflict (user_id) do update set email = excluded.email, updated_at = now();
  return new;
end;
$$;

drop trigger if exists uniplanner_auth_user_access_sync on auth.users;
create trigger uniplanner_auth_user_access_sync
after insert or update of email on auth.users
for each row execute function public.uniplanner_sync_access_user();

create table if not exists public.uniplanner_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.uniplanner_admins enable row level security;
revoke all on table public.uniplanner_admins from public, anon, authenticated;

create or replace function public.uniplanner_is_admin()
returns boolean language sql stable security definer set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1 from public.uniplanner_admins a where a.user_id = auth.uid()
  );
$$;
revoke all on function public.uniplanner_is_admin() from public, anon;
grant execute on function public.uniplanner_is_admin() to authenticated;

create or replace function public.uniplanner_admin_list_users()
returns table(user_id uuid, email text, status text, created_at timestamptz, display_name text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.uniplanner_is_admin() then raise exception 'Owner permission required'; end if;
  return query
    select u.id, u.email::text, coalesce(a.status, 'pending'), u.created_at, p.display_name
    from auth.users u
    left join public.uniplanner_access a on a.user_id = u.id
    left join public.uniplanner_profiles p on p.user_id = u.id
    order by u.created_at desc;
end;
$$;
revoke all on function public.uniplanner_admin_list_users() from public, anon;
grant execute on function public.uniplanner_admin_list_users() to authenticated;

create or replace function public.uniplanner_admin_set_access(p_user_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.uniplanner_is_admin() then raise exception 'Owner permission required'; end if;
  if p_status not in ('approved', 'revoked') then raise exception 'Status must be approved or revoked'; end if;
  if p_user_id = auth.uid() and p_status = 'revoked' then raise exception 'You cannot revoke your own owner access'; end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then raise exception 'Account not found'; end if;
  insert into public.uniplanner_access (user_id, email, status, approved_at, approved_by, updated_at)
  select u.id, u.email, p_status, case when p_status = 'approved' then now() else null end, auth.uid(), now()
  from auth.users u where u.id = p_user_id
  on conflict (user_id) do update set
    email = excluded.email,
    status = excluded.status,
    approved_at = case when excluded.status = 'approved' then now() else null end,
    approved_by = auth.uid(),
    updated_at = now();
end;
$$;
revoke all on function public.uniplanner_admin_set_access(uuid, text) from public, anon;
grant execute on function public.uniplanner_admin_set_access(uuid, text) to authenticated;

create or replace function public.uniplanner_admin_list_memberships()
returns table(workspace_id uuid, workspace_name text, user_id uuid, email text, member_role text)
language plpgsql stable security definer set search_path = public
as $$
begin
  if not public.uniplanner_is_admin() then raise exception 'Owner permission required'; end if;
  return query
    select m.workspace_id, w.name, m.user_id, u.email::text, m.role::text
    from public.uniplanner_workspace_members m
    join public.uniplanner_workspaces w on w.id = m.workspace_id
    left join auth.users u on u.id = m.user_id
    order by w.name, m.role, u.email;
end;
$$;
revoke all on function public.uniplanner_admin_list_memberships() from public, anon;
grant execute on function public.uniplanner_admin_list_memberships() to authenticated;

create or replace function public.uniplanner_admin_remove_workspace_member(p_workspace_id uuid, p_user_id uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.uniplanner_is_admin() then raise exception 'Owner permission required'; end if;
  if exists (
    select 1 from public.uniplanner_workspace_members
    where workspace_id = p_workspace_id and user_id = p_user_id and role = 'owner'
  ) then raise exception 'Workspace owners cannot be removed here. Transfer ownership first.'; end if;
  delete from public.uniplanner_workspace_members
  where workspace_id = p_workspace_id and user_id = p_user_id;
  if not found then raise exception 'Workspace membership not found'; end if;
end;
$$;
revoke all on function public.uniplanner_admin_remove_workspace_member(uuid, uuid) from public, anon;
grant execute on function public.uniplanner_admin_remove_workspace_member(uuid, uuid) to authenticated;

-- ONE-TIME OWNER BOOTSTRAP:
-- After running this migration, uncomment the statement below, replace with your exact
-- existing owner account email, run it once, then keep it commented.
-- insert into public.uniplanner_admins(user_id)
-- select id from auth.users where lower(email) = lower('YOUR_OWNER_EMAIL_HERE')
-- on conflict (user_id) do nothing;

-- No planner data is deleted or reset by this migration.
