# UniPlanner

UniPlanner is a static GitHub Pages university planner with a Supabase-backed account and shared study-workspace layer.

## What is included

### Personal planner
- Overview with upcoming work, calendar and shared-workspace entry point
- Independent attendance tracking for lectures and labs, including approved leave
- Tasks and deadlines, including shared tasks assigned to the signed-in user
- Calendar and weekly timetable
- JSON backup export and import
- Legacy Grades/GPA, faculty, notes and focus modules remain in the codebase for compatibility but are not part of the primary navigation direction

### Shared study workspaces
- Workspace creation and membership
- Shared projects and tasks, including member assignment
- Shared notes and resources
- Task discussions and group chat
- Member directory and owner-managed membership
- Invitations and discoverable workspaces with join requests
- Workspace activity data

### Accounts and access
- Supabase email/password authentication
- Owner approval gate for UniPlanner access
- Owner admin panel for approval/revocation and membership management
- Cross-device personal planner sync
- Server-side Edge Function for owner invitations

## Architecture

- Hosting: GitHub Pages (static site).
- Frontend: `index.html` plus `semester-upgrade.js`.
- PWA assets: `manifest.webmanifest`, `sw.js`, and `notification-icon.svg`.
- Backend: Supabase Auth and PostgreSQL.
- Personal planner data is stored as a per-user JSON payload in `uniplanner_data`.
- Shared workspace content is stored in relational tables protected by RLS.
- Attendance classes and records are part of the personal planner payload; attendance is independent from Grades/GPA and distinguishes Lecture from Lab. Approved Leave and Cancelled sessions do not count as absences or attended sessions.
- The browser uses a Supabase publishable key. Never place a Supabase service-role/secret key in frontend code.
- The `admin-invite-user` Edge Function uses its service-role secret server-side and requires a verified caller token plus the owner/admin check.

## Sync, backups, and notifications

- Local planner changes are saved in the current browser profile.
- Cloud sync is per account and can be used across devices.
- Sync is timestamp-based last-write-wins with a confirmation before replacing local data when the cloud copy is newer. It does not merge simultaneous edits. Export a backup before resolving a conflict or importing a file.
- Browser task reminders require notification permission and the site to be open.
- Study Group alerts use a live Supabase Realtime connection while the signed-in page is active. The current service worker handles notification clicks; it does not implement background Web Push delivery. Do not rely on background notifications on iPhone.

## Deployment

The production website is published from the `main` branch at the repository root through GitHub Pages.

The GitHub Actions validation workflow checks inline JavaScript syntax and a small set of required UI markers. It is not a browser end-to-end test suite. Real desktop, Android, and iPhone checks are still required before relying on every workflow.

## Supabase setup and migration safety

This repository contains historical schema and feature migration SQL files. **There is not yet one complete, verified, ordered bootstrap sequence for a brand-new Supabase project.**

- Do not run every SQL file in the repository in arbitrary order.
- Do not rerun the historical `supabase-schema.sql` against the existing production project as a reset or upgrade.
- The existing production project contains later collaboration, access-control, and hardening changes, some of which were originally applied manually and are not fully represented in migration history.
- See [the Phase 1 technical audit](docs/PHASE-1-TECHNICAL-AUDIT.md) for the verified current state, applied hardening, outstanding warnings, and remaining regression work.
- Test database changes in the isolated test project first. Review the exact migration and its rollback implications before applying schema changes to production.

## Security notes

- Every public UniPlanner table must have RLS enabled.
- Admin data is intentionally not directly readable or writable by browser roles; protected functions perform the owner checks.
- Required authenticated SECURITY DEFINER RPCs must retain their caller/approval/ownership checks and pinned `search_path`. Do not revoke them indiscriminately.
- New public RPCs must receive explicit `EXECUTE` grants for only the intended roles.
- Supabase leaked-password protection is a dashboard Auth setting. See the Phase 1 audit for the current finding and setup path.

## Development

No frontend build step is currently required. The app is a static site. Keep changes scoped, preserve existing local-storage formats and Supabase row structures, and add regression coverage before changing sync, authentication, access control, or workspace behavior.
