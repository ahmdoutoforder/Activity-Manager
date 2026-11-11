# UniPlanner production reconciliation audit

Audit date: 2026-11-11
Target: Xo's Project (`pulokexhjdxrmsdpcmid`)
Repository baseline: `main` at `cf3c5651c64a37e295476cd56f3779e31af4f8af`

## Safety boundary

This audit used read-only Supabase metadata/schema queries. No production rows, policies, functions, tables, or settings were changed. This document is prepared on a feature branch and does not deploy to GitHub Pages.

## Confirmed production state

- Supabase project status: `ACTIVE_HEALTHY`.
- PostgreSQL 17.11.
- Ten UniPlanner public tables exist: `uniplanner_access`, `uniplanner_admins`, `uniplanner_data`, `uniplanner_group_messages`, `uniplanner_profiles`, `uniplanner_shared_tasks`, `uniplanner_task_comments`, `uniplanner_workspace_members`, `uniplanner_workspace_notes`, `uniplanner_workspaces`.
- RLS is enabled on those tables.
- The auth trigger `uniplanner_auth_user_access_sync` exists on `auth.users`.
- Core workspace/access functions exist, including create/delete/leave, invite, admin access, and membership helpers.
- Edge Function `admin-invite-user` is deployed (version 2).
- Supabase migration metadata returned no recorded migrations.

## Frontend/database mismatch — high priority

The merged `main` frontend (`index.html`, 154 KB) directly queries:
- `uniplanner_projects`
- `uniplanner_workspace_resources`

Neither table exists in production.

The frontend also includes the newer workspace collaboration tabs. The migration file `workspace-collaboration-foundation-migration.sql` (merged in PR #34) defines those two tables plus:
- `uniplanner_workspace_invitations`
- `uniplanner_workspace_join_requests`
- `uniplanner_workspace_activity`
- `workspace_type`, `visibility`, and `join_mode` columns on `uniplanner_workspaces`

None of those five tables or three workspace columns were present in the production schema at audit time. PR #34 explicitly labels its migration test-only; PR #35 merged the UI and notes that the migration must be separately reviewed before production rollout. Therefore the production UI and database are currently out of sync. The exact user-visible failure depends on which tab/action is opened.

## Security review findings

Supabase security advisor reported 14 warnings for SECURITY DEFINER functions, including two functions with broad default execute grants. Direct privilege inspection confirmed:
- `rls_auto_enable()` is executable by `anon` and `authenticated`.
- `uniplanner_sync_access_user()` is executable by `anon` and `authenticated`.

These are trigger/event-trigger support functions, so their execute grants should be narrowed after verifying PostgreSQL trigger invocation semantics and dependencies. Other SECURITY DEFINER RPCs are executable by authenticated users and perform internal role/approval checks; do not revoke these indiscriminately because the app depends on them.

Other advisor findings:
- Leaked-password protection disabled.
- Eight foreign keys without covering indexes.
- Fifteen RLS policies with opportunities for more efficient auth function evaluation.
- Five indexes reported unused.

These are review items, not authorization to make production changes. Index usage should be observed over a representative workload before dropping any index.

## Important migration review notes

The existing collaboration migration is additive and starts a transaction, but it must not be applied blindly:
- Its own test plan requires the isolated test project and two approved accounts.
- The test project currently reports `INACTIVE`, so the migration cannot be safely validated there yet.
- The migration deliberately does not implement secure invitation acceptance, join-request review, or workspace settings RPCs.
- The UI's join-request inbox cannot be considered complete until those secure server-side workflows exist and are tested.
- The migration's RLS policies and update guards need a focused review before any rollout.

## Safe next sequence

1. Restore the isolated test Supabase project; do not change production.
2. Compare test schema prerequisites and apply the collaboration migration to test only.
3. Run the migration test plan with two approved test accounts, including cross-workspace isolation and unauthorized-write attempts.
4. Implement and test missing secure RPC workflows before calling collaboration complete.
5. Prepare a production rollout migration and security grant patch on a reviewed branch.
6. Obtain explicit approval of the exact production SQL and backup/rollback plan before applying anything to Xo's Project.
7. Reconcile the frontend and add a single end-to-end test pass before merging/deploying.

## Protected invariants

Do not drop or rename existing tables/columns. Preserve all existing accounts, approvals, personal planner payloads, workspace IDs, memberships, shared tasks, notes, comments, messages, authentication, sync, and RLS protections.
