# UniPlanner workspace-first redesign

**Status:** Active implementation  
**Target:** Production repository ahmdoutoforder/Activity-Manager  
**Baseline:** PR #51 merged to `main` on 2026-11-14  
**Current phase:** Finish the workspace-first experience and final regression coverage

## Product hierarchy

1. **Shared Study Workspaces** — the central collaboration product for classmates: workspace home, projects, shared tasks, assignments and submissions, shared notes/resources, task discussion, group chat, members, join requests and workspace settings.
2. **Attendance** — an independent class register for lectures and labs. It must not depend on Grades/GPA. Present and Absent count toward the percentage; Approved Leave and Cancelled do not count as absences or attended sessions.
3. **Tasks & Deadlines** — personal task inbox, including shared tasks assigned to the signed-in user without duplicating the shared task record.
4. **Overview, Calendar and Timetable** — a daily planning surface that brings upcoming work and class schedule together.
5. **Settings & Sync** — authentication, owner approval, cloud sync, notifications, backup and account preferences.

## Preservation constraints

- Preserve the existing local planner storage key and JSON payload shape; extend the payload additively.
- Preserve Supabase authentication, owner approval/revocation, RLS, existing accounts and existing collaboration records.
- Preserve the existing uniplanner_data.payload records and cross-device sync behavior.
- Never put a Supabase service-role or secret key in the public frontend.
- Keep production schema/data changes separate from frontend work; apply new migrations to the isolated test project first and prepare a reviewed production migration plan.
- Do not run manual user acceptance tests until the redesigned product is assembled. Then perform the complete desktop, second-account and iPhone Safari pass as one coordinated release test.

## Current implementation in PR #51

- Reordered primary navigation around the workspace-first product hierarchy; legacy Grades/GPA, Faculty, Focus and Quick Notes pages remain in source but are not primary navigation.
- Reframed the dashboard and Shared Study Workspaces page; the shared-workspace entry point now appears before personal task attention, and the dashboard uses attendance metrics instead of GPA/credits/assessment tracking.
- Reworked the weekly timetable into day-grouped cards with clear time blocks and a current-day highlight; the dashboard also shows today's scheduled classes.
- Added a workspace-home activity feed that brings together existing RLS-protected chat, task discussion, shared-task creation, projects, notes and resources, plus assignment and submission events when the optional assignment tables are present.
- Removed attendance displays and controls from the legacy Grades module so attendance is managed only in its independent section.
- Added the obsidian/violet responsive shell and improved the workspace picker/content proportions.
- Added a separate attendanceCourses payload collection. Existing attendance records migrate in memory from existing grade courses while preserving their IDs; a one-time marker prevents removed attendance classes from being re-created.
- Added separate Lecture and Lab types, and an attendance snapshot on the dashboard.
- Added Approved Leave status; percentage and counted-session totals include only Present and Absent. Approved Leave remains visible in history and is not treated as an absence.
- Added automated tests for legacy attendance migration, independence from Grades, separate Lecture/Lab records, approved-leave math and intentionally empty class lists.
- Extended CI to parse semester-upgrade.js and run the attendance regression suite.

## Remaining implementation work

- Finish the workspace home experience and confirm each existing collaboration surface is represented coherently.
- Refine personal Tasks, Calendar and Timetable into one consistent planning flow.
- Finish responsive polish, accessible interaction states and empty/loading/error states.
- Review assignment and private Storage migrations as part of the final database rollout plan; production migrations remain unapplied.
- Run the complete automated suite and security/migration review before scheduling the one-time manual acceptance pass.

## Validation so far

- GitHub Actions inline JavaScript syntax check: passed.
- External semester-upgrade.js syntax check: passed.
- Attendance independence and approved-leave regression tests: passed.
- Workspace Storage cleanup worker tests: passed.
- Workspace activity feed now has dedicated regression coverage for aggregation, newest-first sorting, task-to-comment context, result limits, invalid timestamps and graceful handling when optional assignment tables are not installed.
- No production Supabase migration or data change was made by this redesign branch.
