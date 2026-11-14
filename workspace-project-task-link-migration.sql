-- UniPlanner: link shared tasks to workspace projects.
-- Additive and data-preserving. Existing tasks remain unlinked (project_id NULL).
-- Deleting a project detaches its tasks; it does not delete them.
--
-- Applied first to the isolated "uniplanner test" Supabase project.
-- Production rollout is intentionally separate and must follow a reviewed test pass.

alter table public.uniplanner_shared_tasks
  add column if not exists project_id uuid;

do $migration$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'uniplanner_shared_tasks_project_id_fkey'
      and conrelid = 'public.uniplanner_shared_tasks'::regclass
  ) then
    alter table public.uniplanner_shared_tasks
      add constraint uniplanner_shared_tasks_project_id_fkey
      foreign key (project_id)
      references public.uniplanner_projects(id)
      on delete set null;
  end if;
end
$migration$;

create index if not exists uniplanner_shared_tasks_project_due
  on public.uniplanner_shared_tasks(workspace_id, project_id, due_date);

-- PostgreSQL needs an index whose leading column covers the project_id foreign key.
create index if not exists uniplanner_shared_tasks_project_link_idx
  on public.uniplanner_shared_tasks(project_id);

comment on column public.uniplanner_shared_tasks.project_id is
  'Optional project link. The task must belong to the same workspace as the linked project.';

create or replace function public.uniplanner_guard_shared_task_fields()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $function$
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

  if new.project_id is not null
     and not exists (
       select 1
       from public.uniplanner_projects p
       where p.id = new.project_id
         and p.workspace_id = new.workspace_id
     ) then
    raise exception 'The linked project must belong to the same workspace as the task';
  end if;

  return new;
end;
$function$;
