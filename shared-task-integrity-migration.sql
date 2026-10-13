-- UniPlanner shared-task integrity hardening
-- Additive migration: no existing rows are deleted or rewritten.
-- Review this file before running it in the Supabase SQL Editor.

create or replace function public.uniplanner_guard_shared_task_fields()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' then
    if new.created_by is distinct from old.created_by then
      raise exception 'A shared task creator cannot be changed';
    end if;
    if new.workspace_id is distinct from old.workspace_id then
      raise exception 'A shared task cannot be moved to another workspace';
    end if;
  end if;

  if new.assigned_to is not null and not exists (
    select 1
    from public.uniplanner_workspace_members m
    where m.workspace_id = new.workspace_id
      and m.user_id = new.assigned_to
  ) then
    raise exception 'The assignee must be a member of the task workspace';
  end if;

  return new;
end;
$$;

revoke all on function public.uniplanner_guard_shared_task_fields() from public, anon, authenticated;

drop trigger if exists uniplanner_shared_task_field_guard
  on public.uniplanner_shared_tasks;

create trigger uniplanner_shared_task_field_guard
before insert or update on public.uniplanner_shared_tasks
for each row
execute function public.uniplanner_guard_shared_task_fields();

-- Defense in depth: enforce assignee membership in the UPDATE policy too.
-- The trigger remains the authoritative check for both INSERT and UPDATE.
drop policy if exists "Members can update shared tasks" on public.uniplanner_shared_tasks;
create policy "Members can update shared tasks"
  on public.uniplanner_shared_tasks
  for update to authenticated
  using (
    public.uniplanner_is_approved()
    and public.uniplanner_is_workspace_member(workspace_id)
  )
  with check (
    public.uniplanner_is_approved()
    and public.uniplanner_is_workspace_member(workspace_id)
    and (
      assigned_to is null
      or exists (
        select 1
        from public.uniplanner_workspace_members assignee
        where assignee.workspace_id = uniplanner_shared_tasks.workspace_id
          and assignee.user_id = uniplanner_shared_tasks.assigned_to
      )
    )
  );

-- Notes:
-- * created_by and workspace_id are immutable after task creation.
-- * assigned_to must be null or a current member of the same workspace.
-- * existing tasks are not changed by this migration.
-- * run in a test project first; this file is not applied automatically.
