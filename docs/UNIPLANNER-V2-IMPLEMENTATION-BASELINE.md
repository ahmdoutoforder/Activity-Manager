# UniPlanner v2 — verified implementation baseline

**Read-only audit date:** 14 November 2026  
**Production project:** `pulokexhjdxrmsdpcmid` (Xo's Project)  
**Test project:** `rigsjtbaoxkdbumwuhdn` (uniplanner test)  
**Repository baseline:** `2b4a914accb12c5510c3b8abec5592e730999a44`

This is a technical mapping of the existing implementation, not a migration plan and not authorization to change the databases.

## 1. Frontend source map

The deployed application is a static GitHub Pages site. The primary UI and most application logic live in `index.html`; semester-specific additions are in `semester-upgrade.js`; notification-click handling is in `sw.js`.

The current UI contains separate page sections for Overview, Calendar, Tasks, Timetable, Grades, Attendance, Faculty, Study Groups, Focus Timer, Quick Notes, Settings and owner administration. The current main navigation exposes more sections than the approved v2 navigation.

The production application is not a component-framework build. Avoid a blind rewrite or a bulk replacement of the single-page app. Make changes in narrow, reversible slices and preserve the existing account gate, local data, sync, and workspace functions.

## 2. Personal data model and attendance dependency

The local planner object is stored under the existing `uniplanner_v2_data` key and synced to `public.uniplanner_data.payload` as JSON. The current payload includes arrays and settings such as tasks, classes, grades, assessments, attendance, faculty and notes.

The current timetable entries in `data.classes` use course, day, start, end, and optional room/teacher details. Keep the active M1 timetable and its entries unchanged unless the owner deliberately updates them.

Attendance currently lives in `data.attendance` and uses `subjectId` values pointing to entries in `data.grades`. The attendance renderer and statistics iterate over `data.grades`; this is a real code dependency, not just a navigation link. The existing status handling is Present, Absent and Cancelled; it does not yet support Approved Leave, a Not Marked interface state, lecture/lab session type, or per-edit history.

**Required migration approach:** introduce an independent subject catalogue using stable IDs. Map each existing grade/course entry to a subject without deleting its legacy grade record; keep existing attendance IDs/subject references resolvable during migration; preserve assessments and all legacy fields in backups. Make the conversion idempotent and versioned. Only after records are safely mapped may the Grades UI be removed from primary navigation. A subject must not disappear because a user stops viewing the old Grades screen.

Do not overwrite the existing M1 timetable from the hard-coded first-semester seed list. Treat the owner-confirmed timetable and subject catalogue as source data.

## 3. Existing workspace database

The live production schema currently has the following UniPlanner workspace-related structures (all 15 public UniPlanner tables in production and test were confirmed with RLS enabled):

- `uniplanner_workspaces`: workspace identity, type, visibility and join mode.
- `uniplanner_workspace_members`: membership and owner/member roles.
- `uniplanner_workspace_invitations`: invitation state, recipient, response and expiry. Existing default expiry is 14 days; preserve it unless the product owner explicitly chooses a different policy.
- `uniplanner_workspace_join_requests`: discoverable workspace requests and review state.
- `uniplanner_shared_tasks`: shared task records, assignee, completion, due date, category and a legacy priority column.
- `uniplanner_projects`: project title, description, status and due date.
- `uniplanner_workspace_resources`: resource title/description, URL and resource type; this currently supports links/references, not uploaded file objects.
- `uniplanner_workspace_notes`: shared notes.
- `uniplanner_task_comments`: task discussions/comments.
- `uniplanner_group_messages`: workspace group chat.
- `uniplanner_workspace_activity`: activity-event storage.
- `uniplanner_profiles`: member display names.
- `uniplanner_access` and `uniplanner_admins`: site-wide approval and administration.
- `uniplanner_data`: personal planner JSON payload.

The current frontend uses workspaces, membership/profiles, invitations, join requests, shared tasks, shared notes, task comments and group messages. The existing Projects, Workspace Resources and Workspace Activity tables are not yet fully integrated into the workspace UI. The projects table does not currently have a direct project-to-task relationship; that relationship needs a deliberate schema design before a project task list is represented as linked records.

Current policies enforce approved-user access and workspace membership; project/resource/content rules are protected by RLS and scope-guard triggers. Retain these database boundaries. Do not treat frontend hiding as authorization.

The `uniplanner_shared_tasks.priority` column exists and the current UI exposes it. The approved design removes user-facing task priority labels. Hide/remove the UI control and priority-based sort/filter from the redesign, but do not drop or rewrite the stored database column as a side effect.

## 4. Files, assignments and submissions

A read-only query of `storage.buckets` returned no buckets in either production or test. The current workspace resource table contains URL/reference records; there is no upload pipeline ready for workspace materials or assignment submissions.

The current public schema has no dedicated assignment or assignment-submission tables. Implementing the approved assignment submission workflow (all workspace members can view/download each separately attributed submission) will require a designed, additive schema for assignments/submissions, a private Storage bucket, safe object paths, and Storage RLS policies. Test this in the isolated Supabase project first. Do not create the bucket or run DDL in production as part of the frontend foundation.

Until that is implemented, the UI may present link/reference materials only; it must not pretend uploaded files or submissions are supported.

## 5. Realtime and notifications

The production and test projects each have a `supabase_realtime` publication, but read-only queries of `pg_publication_tables` returned no public UniPlanner tables in either project.

The existing frontend subscribes to INSERT events for group messages, task comments and shared tasks. The repository contains `notification-realtime-migration.sql`, which adds those three tables, but its presence in Git is not proof that it has been applied. The live publication state must be checked after any test migration.

The existing Workspace Activity table has no recorded rows in the current audit, and no trigger was found on the listed workspace content tables that writes to it. Its feed/event pipeline therefore needs to be designed, not assumed to work merely because the table exists.

The current service worker handles notification clicks; it does not implement a Web Push `push` event or a server-side push sender. Browser notifications while the signed-in page is active and background push are separate capabilities. Do not promise background notification delivery, especially on iPhone, without implementing and testing a real Web Push path.

## 6. Verified project-level guardrails

- Both Supabase environments are active and available: production remains the live app project; `uniplanner test` is the isolated test project.
- The inspected public UniPlanner tables have RLS enabled in both environments.
- Existing auth/access RPCs are SECURITY DEFINER functions with pinned search paths; preserve their grants and caller/owner/approval checks.
- Production and test each have a `supabase_realtime` publication, but no UniPlanner tables are currently included.
- Neither environment currently has a Storage bucket.
- Migration history is incomplete relative to the full lifetime of the app. Do not replay historical SQL or the root `supabase-schema.sql` file as an upgrade.
- The existing GitHub Actions workflow checks JavaScript syntax and a small number of required UI markers. It is not a browser/device end-to-end suite.
- Keep production `main` and the production Supabase project unchanged until an isolated test pass and explicit rollout review are complete.

## 7. Recommended implementation order

1. Finish the workspace shell and integrate the existing Projects/Resources UI using current tables only; keep uploads explicitly unsupported until Storage is designed.
2. Design the additive assignment/submission and private Storage model, test it in `uniplanner test`, and verify all-member read/download plus attribution.
3. Design the Workspace Activity event writers and add the needed Realtime publication tables in test; test two-account live updates.
4. Introduce the independent subject catalogue and idempotent attendance migration; preserve old grade/assessment records and connect M1 timetable sessions.
5. Connect personal and shared task views without duplicating assigned workspace task records; remove priority controls from UI while retaining legacy storage.
6. Add real two-account, browser and device test coverage before any production rollout.

No database write or schema change was made during this audit.
