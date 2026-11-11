# Workspace integrity hardening — validation record

**Migration:** `workspace-integrity-hardening-migration.sql`

## Changes
- Invitation rows can only be created through `uniplanner_invite_member`; direct client inserts are removed.
- Shared-task ID, workspace, creator and creation timestamp are immutable.
- New or changed task assignees must belong to the task's workspace.
- Workspace ID, creator and creation timestamp are immutable; owners retain the existing ability to rename and change workspace settings.

## Validation completed
- Applied this migration successfully to the isolated test project and production project.
- In both projects, the owner invited a second approved account through the RPC; direct invitation insertion was rejected by RLS; the invitee accepted and became a member.
- Confirmed a member can be assigned to a task in the workspace.
- Confirmed task creator/workspace reassignment and assignment to a non-member are rejected by the trigger.
- Confirmed owners can rename workspaces and update workspace classification/join settings.
- Confirmed attempts to change workspace creator or ID are rejected.
- All workflow tests ran inside transactions and were rolled back; no test records were retained.

## Validation checklist
- Existing personal planner data, workspaces, memberships, tasks, notes, messages and comments retain their row counts.
- Owners can invite approved accounts through the RPC; direct invitation inserts are denied.
- Workspace owners can rename workspaces and update classification/join settings.
- Attempts to change workspace identity fields are rejected.
- Shared-task updates that change ID, workspace, creator or creation time are rejected.
- A task cannot be newly assigned to a non-member.
- Existing task assignments to former members are not blocked when unrelated fields are edited.
