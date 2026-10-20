# Collaboration foundation — test-only validation

**Target:** the isolated UniPlanner test Supabase project only.  
**Never run this file's migration against production without a separately reviewed rollout plan.**

## Before applying the migration
1. Open the Supabase dashboard and verify the project URL is `https://rigsjtbaoxkdbumwuhdn.supabase.co`.
2. Confirm the project already has the current UniPlanner base schema, access-control tables/functions, and workspace tables.
3. Export/back up the test project's schema and data if it contains anything worth keeping.
4. Open `workspace-collaboration-foundation-migration.sql` from this branch and review the complete file.
5. Run it in the **test project's** SQL Editor only. It is additive, but it still creates tables, policies, functions, and constraints.

## Validation
- Confirm existing workspaces remain and default to `workspace_type=study_group`, `visibility=private`, `join_mode=invite_only`.
- Confirm existing personal planner rows and shared task rows have unchanged counts and contents.
- Create a workspace and verify the owner can read it; verify a non-member cannot read its project/resource/activity rows.
- With two approved test accounts, verify a member cannot read another workspace's projects, resources, or activity.
- Verify a non-approved account cannot read or write collaboration tables.
- Verify a join request insert is rejected for a private/invite-only workspace and permitted only for a discoverable/request-to-join workspace.
- Verify a member cannot change a project's or resource's `workspace_id` or `created_by`.
- Verify an invitation cannot be created by a non-owner.
- Inspect Supabase Logs for SQL errors and verify RLS is enabled on all five new tables.

## Not implemented by this migration yet
The UI and secure RPC workflows for accepting/revoking invitations, reviewing join requests, changing workspace settings, and presenting projects/resources/activity have not been wired up. Do not treat this migration alone as a finished collaboration feature.

## If anything fails
Stop. Do not try the migration on production or disable RLS to make tests pass. Capture the exact error and identify the missing prerequisite or policy issue first.
