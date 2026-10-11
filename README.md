# UniPlanner v2

A clean, local-first university planner designed for GitHub Pages. The rebuild starts with empty data and includes tasks/deadlines, a month calendar, weekly timetable, course grade-point tracker, faculty directory, focus timer, scratchpad and saved notes, JSON backup/import, and optional Supabase account sync.

## Deploy to GitHub Pages

1. Review the rebuild branch before publishing: [rebuild/uniplanner-v2](https://github.com/ahmdoutoforder/Activity-Manager/tree/rebuild/uniplanner-v2).
2. Merge the branch into `main` when you're satisfied with the review.
3. In repository **Settings → Pages**, publish from the `main` branch and root folder (if Pages isn't already configured).
4. Open the published site and hard-refresh it. The new app uses the `uniplanner_v2_data` local-storage key and starts with an empty planner; the older app's `uni_events` data is not imported.

## Local data and backups

- Tasks, timetable, grades, faculty, notes and preferences save in the current browser profile.
- Use **Export backup** regularly. Keep the JSON file somewhere safe.
- Importing a backup replaces the current device data only after confirmation.
- Browser data can be removed by clearing site data, using another browser/profile, or using another device. Local storage alone is not cross-device sync.
- Browser notifications are **off by default**. If enabled, the app requests permission and records each task's reminder ID so a due-today task is not repeatedly announced. The website must be open, and browser notification support/permission must be available.

## Optional cross-device sync (Supabase)

GitHub Pages is static hosting; shared data needs a separate backend. This app uses Supabase Auth plus a per-user JSON payload table.

1. Create a Supabase project.
2. Open **SQL Editor** and run the contents of [supabase-schema.sql](./supabase-schema.sql).
3. In Supabase project settings, copy the project URL and the **anon/publishable** client key. Never place a service-role key in browser code.
4. Open UniPlanner → **Settings & sync**, enter the project URL and anon key, then save preferences.
5. Enter an email and password and select **Sign in / create account**. If email confirmation is enabled, confirm the message before signing in.
6. Test on one device first, then sign in to the same account on another device.

### Sync behavior and limitations

- Row-level security restricts each authenticated account to its own row.
- Local edits are timestamped; cloud data newer than the local copy prompts before replacing it. Export a backup before resolving a conflict.
- This is a single-user-per-account snapshot sync, not live multi-user collaboration. For group projects with shared team workspaces, invitations, roles, activity history and real-time merges, a backend with dedicated shared-workspace tables and conflict resolution is still needed.
- The app never claims local-only storage is cross-device sync. A failed cloud request leaves the local copy available and reports a sync error.
- Avoid editing the same account simultaneously on multiple devices while a conflict is pending; choose the intended copy deliberately.

## Notes

- GPA is a weighted estimate from the grade points and credit hours you enter. Confirm the official scale with your university.
- Focus timer runs while this page is open and does not depend on desktop notifications.
- The page loads Google Fonts and the Supabase JavaScript client from CDNs; those external resources need internet access.
- No software can honestly guarantee zero bugs. Verify the main workflows and keep backups before relying on it for critical deadlines.
