-- UniPlanner workspace and shared-task integrity hardening
-- Additive and data-preserving. Apply to test first, then production after verification.

begin;

-- Invitations must be created through the checked SECURITY DEFINER RPC.
-- Direct inserts could otherwise bypass its duplicate/account validation.
drop policy if exists "Workspace owners can create invitations"
  on public.uniplanner_workspace_invitations;

-- Keep task identity and workspace scope immutable. A task can only be assigned
-- to a current member when its assignee is changed or the task is first created.
create or replace function public.uniplanner_guard_shared_task_fields()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $fn$
begin
  if tg_op = 'UPDATE' then
    if new.id is distinct from old.id then
      raise exception 'A shared task ID cannot be changed';
    end if;
    if new.created_by is distinct from old.created_by then
      raise exception 'A shared task creator cannot be changed';
    end if;
    if new.workspace_id is distinct from old.workspace_id then
      raise exception 'A shared task cannot be moved to another workspace';
    end if;
    if new.created_at is distinct from old.created_at then
      raise exception 'A shared task creation time cannot be changed';
    end if;
  end if;

  if new.assigned_to is not null
     and (tg_op = 'INSERT' or new.assigned_to is distinct from old.assigned_to)
     and not exists (
       select 1
       from public.uniplanner_workspace_members m
       where m.workspace_id = new.workspace_id
         and m.user_id = new.assigned_to
     ) then
    raise exception 'The assignee must be a member of the task workspace';
  end if;

  return new;
end;
$fn$;
revoke all on function public.uniplanner_guard_shared_task_fields() from public, anon, authenticated;

drop trigger if exists uniplanner_shared_task_field_guard
  on public.uniplanner_shared_tasks;
create trigger uniplanner_shared_task_field_guard
before insert or update on public.uniplanner_shared_tasks
for each row execute function public.uniplanner_guard_shared_task_fields();

-- Workspace ID, creator and creation timestamp are immutable. Owners can still
-- rename the workspace and edit the approved classification/join settings.
create or replace function public.uniplanner_guard_workspace_identity()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $fn$
begin
  if new.id is distinct from old.id then
    raise exception 'A workspace ID cannot be changed';
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'A workspace creator cannot be changed';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'A workspace creation time cannot be changed';
  end if;
  return new;
end;
$fn$;
revoke all on function public.uniplanner_guard_workspace_identity() from public, anon, authenticated;

drop trigger if exists uniplanner_workspace_identity_guard
  on public.uniplanner_workspaces;
create trigger uniplanner_workspace_identity_guard
before update on public.uniplanner_workspaces
for each row execute function public.uniplanner_guard_workspace_identity();

commit;
