# UniPlanner v2 — approved product and implementation blueprint

**Status:** Approved product direction; implementation starts on an isolated branch  
**Baseline:** `main` at `2b4a914accb12c5510c3b8abec5592e730999a44` (11 November 2026)  
**Work branch:** `rebuild/uniplanner-v2-foundation-2026-11`  
**Hosting:** GitHub Pages, repository root  
**Frontend:** Static HTML/CSS/JavaScript  
**Backend:** Existing Supabase Auth, PostgreSQL, RLS, RPCs and Realtime

## 1. Product direction

UniPlanner is a small, private university planner for the user and classmates. The redesign prioritizes three areas, in this order:

1. **Shared Study Workspace** — the primary product and the most important collaboration experience.
2. **Attendance** — timetable-based session tracking, with independent lecture and lab records.
3. **Tasks & Deadlines** — personal responsibilities plus shared workspace tasks, connected without duplicates.

The Overview gives a balanced snapshot of today's classes/attendance, upcoming work and meaningful workspace activity. The product should stay practical, quick and lightweight. Avoid turning it into a general-purpose LMS, gradebook, social network or enterprise collaboration suite.

## 2. Navigation and page structure

Keep the previously agreed hybrid navigation: a left sidebar for primary sections and a context-aware top bar for page title, relevant actions, search/notifications/profile. Entering a workspace reveals its own internal navigation; workspace tools should not all be permanently exposed in the global sidebar.

Primary sections:

- Overview
- Shared Study Workspaces
- Attendance
- Tasks & Deadlines
- Timetable
- Settings & Sync

The workspace switcher sits at the top of the sidebar. Admin controls remain owner-only and separate from ordinary navigation.

The old Grades/GPA, Faculty, Focus Timer and standalone Quick Notes views are outside the new primary navigation. Do not delete their stored data during this redesign. Shared notes remain a core workspace feature. Existing data should remain recoverable through backup/export, and legacy views/data can be revisited separately if needed.

## 3. Overview

The Overview should stay balanced rather than become a dense analytics dashboard. Its primary content is:

- Today's scheduled classes and their attendance state.
- Upcoming personal and assigned workspace tasks, sorted by due date.
- A small indicator/preview for meaningful new workspace activity.
- A compact path into the active shared workspace.

Do not restore GPA, grade analytics, faculty statistics, semester-performance scores or decorative metrics as dashboard priorities.

## 4. Shared Study Workspaces

This is the highest-priority feature. Reuse the existing workspace, membership, task, notes, comments and message foundations wherever they satisfy the approved workflows.

### Workspace areas

- **Home:** workspace summary, recent meaningful activity, pinned items and upcoming shared work.
- **Materials:** shared files/resources, organized by subject or topic.
- **Notes:** shared and collaborative study notes with clear authorship and safe editing/history.
- **Tasks:** shared tasks, owners, assignees, due dates, completion and comments.
- **Projects:** group projects with description, members, milestones/sections and linked tasks.
- **Chat:** retain the existing group chat requirement for workspace conversations.
- **Members:** membership list, role and owner-managed member actions.

Task comments and activity are attached to the relevant task/work item. Do not create redundant communication surfaces merely to duplicate comments or chat.

### Membership and permissions

- Workspaces are private by default. A workspace may opt into the discoverable directory.
- Direct invitations require the invited account to accept.
- Join requests require an owner to approve.
- Invitation links are revocable and have a clear expiry. They must not bypass the workspace's configured access model.
- Owners manage workspace settings, invitations and membership. Members collaborate within the workspace.
- Preserve the existing site-wide owner approval gate and admin panel. Workspace membership does not grant site access.
- A member may leave without deleting shared content. Owner-leave/ownership-transfer and owner-only deletion rules already implemented must remain intact.
- All workspace members may view and download every member's assignment submission. Each submission stays separately attributable to its submitter and timestamp; one member must not overwrite another member's file.
- Keep RLS and server-side authorization as the actual security boundary. Frontend visibility alone is not authorization.

### Materials and storage

The current repository documents no dedicated workspace Storage bucket. Materials uploads therefore require a separately designed Storage bucket, object-path convention, upload/download limits, retention and Storage policies. Do not add this to production as part of a visual/UI commit. Design and test Storage changes against the isolated Supabase project first.

### Activity and notifications

Notify for meaningful events across workspace activity, including new materials, notes or project updates, task assignment/completion/comment activity, invitations/join requests and chat messages. Avoid duplicate/noisy notifications for inconsequential edits and actions performed by the current user. Provide a notification centre and clear per-event context.

The current app's Realtime notifications are only reliable while the signed-in page is active. Do not promise background Web Push or reliable iPhone background delivery until a real Web Push sender, subscription lifecycle and service-worker push handler are built and tested.

## 5. Attendance

Attendance is based on the active M1 timetable and the subject catalogue. A class can be marked or corrected at any time. The daily view shows all scheduled sessions together, with a detailed session view for edits.

Track lecture and lab attendance independently. Do not combine their percentages.

### Session states

- **Present:** attended; included in the numerator and denominator.
- **Absent:** missed; included in the denominator only.
- **Approved Leave:** recorded separately and excluded from the percentage.
- **Cancelled:** class did not take place; excluded from the percentage.
- **Not Marked:** a UI state for an unresolved scheduled session, not an attendance outcome. Never silently convert it to Absent. When relevant past sessions remain unmarked, label the percentage provisional/incomplete so it is not presented as a complete record.

For each lecture/lab category:

`Attendance % = Present / (Present + Absent) × 100`

75% is the default warning threshold, configurable by the user in Settings. Provide safe/warning/below-minimum indicators. Allow the user to correct records at any time and keep a lightweight change history (old status, new status, timestamp). The daily marking view and detailed session history are both required. Do not add a separate monthly attendance calendar.

Provide PDF and Excel exports. Export subject/session identity, date, session type, status, calculation summary, approved leave and cancelled counts. Exporting must not alter stored records.

### Migration constraint

Today, attendance records in the personal JSON payload are associated with the legacy `grades` array. The new design removes the Grades interface, but must first introduce a standalone subject catalogue and migrate attendance references without losing any attendance or subject records. Keep legacy grades/assessment fields in backups and do not delete them as a side effect of hiding old UI.

## 6. Tasks & Deadlines

There are personal tasks and shared workspace tasks. Use one consistent task experience, but do not create duplicate database records:

- A task created personally is private to the user.
- A shared task belongs to a workspace.
- If a workspace task is assigned to the current user, show a reference to that same task in the user's personal task view. Do not copy it into a second task record.
- Assignments and projects remain their own content types and can contain/link to actionable tasks.

Task views: deadline-focused list (default), Kanban board, and calendar. The list is sorted by due date and highlights overdue, due-today, due-soon and upcoming items.

Task details are flexible: title, optional subject, due date/time, description, optional attachments, reminders, completion state and a simple checklist. Do not add priority labels or recurring tasks. Reminder controls provide useful presets and custom date/time. Completed tasks leave the active list and remain accessible in a Completed history; users can reopen them.

Personal tasks and workspace tasks must retain appropriate visibility boundaries. Workspace tasks remain visible only to workspace members under RLS.

## 7. Timetable and subject catalogue

The current M1 timetable is the active timetable until the user supplies an update. Preserve its class/session timing and distinguish lectures from labs. The owner maintains the subject catalogue and timetable; do not infer a new course list from the older semester booklet. Attendance uses this timetable to surface today's sessions.

A subject is a course identity independent of grades. It must have a stable ID and enough timetable metadata to associate lecture/lab sessions and attendance. Do not use the Grades page as the permanent subject store.

## 8. Existing data, account and sync preservation

Non-negotiable preservation requirements:

- Do not reset or delete personal planner records, shared workspaces, memberships, notes, comments, messages, tasks, invitations or user accounts.
- Preserve Supabase authentication, owner approval/revocation, RLS, required RPCs and cross-device sync.
- Preserve localStorage key/schema compatibility or provide an explicit, reversible migration with backup and idempotency.
- Keep Supabase publishable credentials in the browser only; never expose service-role/secret keys.
- Never weaken RLS or replace server-side permission checks with UI-only controls.
- The current personal sync is timestamp-based last-write-wins and does not merge concurrent edits. Do not claim conflict-free merging. Preserve the existing warning/backup behavior until a tested conflict-resolution approach exists.

## 9. Technical baseline and implementation constraints

The current production source is a static single-page app with a large `index.html`, `semester-upgrade.js`, `sw.js` and a GitHub Actions validation workflow. Supabase holds personal JSON payloads in `uniplanner_data` and normalized workspace data in relational tables protected by RLS.

The Phase 1 audit recorded 15 public tables with RLS enabled, production/test schema alignment on inspected structures, and 7 personal-data rows plus existing workspace records. It also documents incomplete historical migration history. These are audit snapshots, not permission to replay old SQL.

- Do not run the historical `supabase-schema.sql` or all root SQL files as a bootstrap/upgrade.
- Do not modify production Supabase during frontend foundation work.
- Any future database change must be an additive, reviewed migration: inspect current live schema, apply to the isolated test project, verify RLS/grants/RPCs/data preservation and two-account workflows, then present the exact production migration and rollback plan before production rollout.
- Verify current Supabase documentation before implementing any Supabase-specific change.
- Keep each phase small, reviewable and testable. Use feature branches and pull requests; do not push redesign changes directly to `main`.

## 10. Delivery phases

1. **Foundation:** record the approved specification; establish the visual system and responsive app shell; preserve current page behavior and account gate.
2. **Workspace experience:** redesign workspace home/internal navigation and member flows, then materials, notes, tasks/projects and chat while retaining current collaboration data and permissions.
3. **Attendance foundation:** introduce the standalone subject catalogue, migrate legacy attendance references safely, connect M1 timetable sessions, add approved leave and lecture/lab separation, then exports.
4. **Tasks & Deadlines:** improve personal/shared task linking, list/Kanban/calendar views, checklists, reminder controls and completed history.
5. **Overview and cleanup:** deliver the balanced overview, remove out-of-scope sections from primary navigation without deleting legacy data, and apply responsive/violet theme consistently.
6. **Verification and rollout:** automated validation, two-account test workflows, desktop/mobile testing, backup/restore checks, isolated Supabase tests, then a separately reviewed production rollout.

## 11. Definition of done

A phase is not complete merely because it renders. It must preserve existing data/auth/sync, pass its available automated checks, pass relevant manual workflows with at least two approved test accounts, behave on desktop and mobile, and document any limitation honestly. No production database migration or merge to `main` occurs without a clear review point.
