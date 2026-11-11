# UniPlanner — Phase 1 technical, security & reliability audit

**Audit date:** 11 November 2026  
**Repository:** `ahmdoutoforder/Activity-Manager`  
**Scope:** Production Supabase project, isolated Supabase test project, GitHub Pages source, Auth/Edge Function configuration, migration history, and available automated validation.

## Executive result

Phase 1 found and corrected over-broad database grants, aligned the test project’s workspace lifecycle RPCs with production, and tightened the production shared-task assignment policy. No personal planner or collaboration rows were changed or deleted by these fixes.

The production project reports `ACTIVE_HEALTHY` on PostgreSQL 17.11. All 15 public UniPlanner tables have RLS enabled. Production and test now match on the inspected table columns, constraints, indexes, triggers, RLS policies, and public function signatures. The remaining advisor warnings are documented below; they are not being hidden by removing RPC access the app requires.

## Changes applied and verified

### 1. Public table privileges

Before the fix, the `anon` and `authenticated` roles had unnecessary table-level privileges on many public application tables, including `TRUNCATE`. RLS does not protect against `TRUNCATE`, so this was a genuine least-privilege gap.

Applied first to the isolated test project, verified, then applied to production:

- Revoked all direct table privileges from `anon` on public-schema tables.
- Retained the normal `SELECT`, `INSERT`, `UPDATE`, and `DELETE` privileges required by authenticated application requests; RLS continues to determine which rows a user may access.
- Revoked `TRUNCATE`, `TRIGGER`, and `REFERENCES` from `authenticated`.
- Updated the PostgreSQL migration-owner default table privileges so future public tables follow the same restrictions.

Verification on both projects confirmed that `anon` has no direct table access and `authenticated` has no `TRUNCATE`, `TRIGGER`, or `REFERENCES` privilege on the app tables.

### 2. Default privileges for future public functions

New public-schema functions created by the PostgreSQL migration owner no longer grant `EXECUTE` to `PUBLIC`, `anon`, or `authenticated` by default. Existing application RPC grants were preserved. A new RPC must now explicitly grant execution to the role that needs it.

### 3. Shared-task assignment policy

Production’s `Members can update shared tasks` policy was weaker than the isolated test policy. Production now also requires that an assigned user is a member of the same workspace. The existing BEFORE trigger remains as a second integrity check.

### 4. Test-project lifecycle alignment

The isolated test project was missing the production `uniplanner_delete_workspace(uuid)` and `uniplanner_leave_workspace(uuid)` RPCs. Production-equivalent definitions and explicit grants were added to test. This was test-only; production already had the functions.

### 5. Data preservation

The production row counts checked before and after the grant/policy changes remained unchanged:

| Table | Rows |
|---|---:|
| `uniplanner_data` | 7 |
| `uniplanner_workspaces` | 2 |
| `uniplanner_workspace_members` | 5 |
| `uniplanner_shared_tasks` | 1 |
| `uniplanner_group_messages` | 2 |
| `uniplanner_task_comments` | 1 |
| `uniplanner_workspace_invitations` | 0 |
| `uniplanner_workspace_join_requests` | 0 |

These are database row counts, not a content inspection. No user payloads were read for this count check.

## Security review

### SECURITY DEFINER functions

The Security Advisor reports 18 authenticated-callable SECURITY DEFINER functions. This includes admin, approval, membership, workspace lifecycle, invitations, and join-request RPCs used by the application.

The function-by-function review confirmed:

- Admin listing, access-management, and admin member-removal RPCs check `uniplanner_is_admin()`.
- Workspace creation, invitation, deletion, leaving, discovery, join-request, invitation-response, and join-request-review RPCs check the caller’s identity and the relevant approval, ownership, membership, or invitation/request relationship.
- The SECURITY DEFINER functions have pinned `search_path` settings.
- The reviewed RPCs deny execution to `anon`; the app-required RPCs remain executable by `authenticated`.
- Internal trigger/event-trigger functions are not exposed as callable app RPCs.

The 18 warnings remain because Supabase’s advisor flags any authenticated-callable SECURITY DEFINER function. Removing authenticated execution indiscriminately would break the app. The warnings should be revisited whenever an RPC is changed or added.

### Other current Security Advisor findings

- **Leaked password protection disabled — WARN.** This is an Auth dashboard setting, not a SQL issue. Supabase documents the feature as available on Pro plan and above. Enable it in Authentication → Sign In / Providers → Email → “Prevent use of leaked passwords”, then rerun the Security Advisor. If the control is unavailable on the project’s plan, record the limitation rather than attempting a database workaround.
- **`uniplanner_admins` has RLS enabled and no policies — INFO.** Direct table access is intentionally denied; the protected admin helper reads it. Do not add a broad policy merely to clear this informational finding.
- **18 unused-index findings — INFO.** These indexes are retained. Advisor usage counters alone are not sufficient reason to drop them; observe a representative workload first.

## Frontend, Auth, and Edge Function review

- The public frontend uses a Supabase publishable key (`sb_publishable_…`), not a service-role key. A publishable key is expected in a browser client; RLS is the security boundary.
- No `service_role` key was found in the checked frontend source.
- The `admin-invite-user` Edge Function is active with JWT verification enabled. It validates the caller’s user token, checks the caller through `uniplanner_is_admin()`, and reads the service-role key from server-side Edge Function secrets. The service-role key is not returned to the browser.
- The approval gate is enforced in the UI and database policies/RPCs. The access table remains protected from direct client writes.
- All 15 public UniPlanner tables have RLS enabled.

## App and deployment review

- The app remains a static GitHub Pages app, with `index.html`, `semester-upgrade.js`, `sw.js`, and `manifest.webmanifest`.
- Inline JavaScript syntax parsing passed for both inline scripts; `semester-upgrade.js` also parsed successfully.
- The latest GitHub Actions validation workflow and GitHub Pages deployment for the audited `main` commit completed successfully.
- This is source-level and deployment-workflow validation, not a real-browser or real-device end-to-end test.

## Reliability limitations still open

1. **Personal cloud sync is last-write-wins.** The app compares local and cloud timestamps and asks before replacing local data when cloud data is newer. It does not merge simultaneous edits or provide a conflict-resolution history. Export a JSON backup before major imports or conflict decisions.
2. **Study Group alerts are live-session notifications.** The app listens to Supabase Realtime inserts while the signed-in page is active. The service worker handles notification clicks but has no Push API event handler or server-side push sender. This is not background Web Push; iPhone background delivery must not be promised.
3. **Real two-account and device tests remain necessary.** The isolated test project has no production user data. Automated source checks cannot prove real account isolation, sync conflict behavior, iOS behavior, or every owner/member workflow.
4. **Migration history is incomplete.** The two projects now record the latest hardening/alignment migrations, but older SQL was applied manually and is not represented as a complete ordered migration history. Do not mark the current root SQL files as a clean bootstrap sequence or replay them blindly. A reviewed, reproducible baseline is still required before future schema work.
5. **The app is still largely a single-file frontend.** It has no comprehensive browser automation suite. The existing GitHub workflow checks inline JavaScript syntax and a small set of required UI markers only.

## Required manual action

In the production Supabase Dashboard:

1. Open **Authentication → Sign In / Providers**.
2. Open the **Email** provider.
3. Enable **Prevent use of leaked passwords** and save, if the project plan exposes the setting.
4. Rerun the Security Advisor and confirm whether the warning clears.

Supabase documentation: https://supabase.com/docs/guides/auth/password-security

## Next work after Phase 1

- Complete a real two-account regression pass for approval/revocation, personal sync, workspace membership, task assignment, notes, comments, chat, invitation acceptance, join-request review, owner transfer, and deletion.
- Test desktop, Android, and iPhone behavior; treat background push as a separate feature requiring a real Web Push architecture.
- Reconcile historical manual migrations into a reviewed baseline without replaying them against production.
- Only after this technical baseline is accepted, prepare the complete UniPlanner redesign blueprint. No redesign was performed during this audit.
