# UniPlanner safe upgrade — audit notes

## Scope
Review of the existing single-file GitHub Pages app before making changes. This is a source-level audit, not a claim that browser/Supabase end-to-end tests were run.

## Changes in this branch
- Added a compact dashboard insight row: task completion this week, upcoming open deadlines over the next seven days, and overall completion percentage.
- Added shared-workspace task assignment to a workspace member and group-level totals for total, completed, and overdue tasks.
- Added a backward-compatible `assigned_to` UUID column to the SQL setup using `ADD COLUMN IF NOT EXISTS`; existing shared tasks remain unassigned.
- Hardened JSON restore: 10 MB file limit, required planner collections, basic record-shape checks, confirmation with item counts, and refreshing the scratchpad/session display after restore.
- Made export object-URL cleanup slightly more defensive.

## Findings / risks observed
1. **Restore used to accept incomplete payloads.** It only required `tasks` and `classes`, then merged everything else over defaults. This could accept an unrelated or incomplete JSON file. Validation is now stricter, though it is still client-side validation and cannot prove every record is semantically correct.
2. **Task completion handlers are registered twice in `renderTasks()`.** The second listener replaces the first handler for each element, so this appears redundant rather than two separate completion actions. It should be simplified in a future isolated cleanup.
3. **Cloud sync is last-write-wins, not conflict-aware.** The current timestamp comparison can ask the user before replacing local data, but simultaneous edits across devices are not merged. Keep exporting backups before risky imports or major changes.
4. **Workspace assignment requires the SQL upgrade.** Re-run the updated `supabase-schema.sql` in Supabase SQL Editor before using the assignment dropdown. Existing tables are upgraded with an idempotent column addition.
5. **Manual browser testing is still required.** The GitHub connector does not run the app in a real browser, so mobile layout, Supabase RLS behavior, and real cross-account assignment need testing on the deployed site.

## Suggested regression checklist
- Export a JSON backup; import it into a test browser profile; verify tasks, classes, grades, faculty, notes, scratchpad, and focus-session count.
- Try malformed JSON, a file over 10 MB, and a backup missing a required collection; verify the app refuses it without replacing local data.
- Check dashboard insights with no tasks, overdue tasks, due-today tasks, and completed tasks.
- Re-run the updated SQL in Supabase, then create a workspace, invite a second account, assign a task, and verify both members see the same assignment and completion state.
- Verify existing personal sync and unrelated sections (calendar, grades, timetable, notes, focus timer) after deployment.
