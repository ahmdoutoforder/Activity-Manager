# Production rollout plan — workspace assignments and private Storage

**Status:** Prepared only; not executed on production.  
**Production Supabase project:** pulokexhjdxrmsdpcmid  
**Isolated test Supabase project:** rigsjtbaoxkdbumwuhdn

## Current verified database state

- Production currently records `workspace_project_task_link` as its latest feature migration. It does not yet have the assignment tables or private assignment bucket.
- The isolated test project has the four assignment/storage migrations below applied in this exact order.
- The production assignment table count and assignment bucket count were previously verified as zero. No production assignment migration has been applied.
- The test project has the schema and RLS policies, but real binary upload/download testing is still pending. Existing SQL/RLS checks used synthetic Storage metadata and do not prove actual file transfer.

## Exact migration order

Apply each migration separately and stop if any step errors. The four files are in the repository root.

1. `workspace-assignments-storage-migration.sql` — creates the private bucket, assignment/resource/submission tables, triggers, indexes, RLS policies and Storage object policies.
2. `workspace-assignment-indexes-migration.sql` — adds supporting indexes for assignment-related foreign keys.
3. `workspace-assignment-submission-status-migration.sql` — reinforces that submissions and Storage uploads are allowed only while an assignment is open.
4. `workspace-storage-cleanup-migration.sql` — adds the authorized cleanup queue/trigger and permits the worker to remove private files after workspace deletion.

These correspond to the isolated test project's recorded migration names:

- `workspace_assignments_private_storage`
- `workspace_assignment_fk_indexes`
- `workspace_assignment_submission_status`
- `workspace_storage_cleanup_jobs`

## Required release gate before production

Do not apply these migrations to production until the complete redesigned product has been assembled and the user has completed the one-time acceptance pass on the final preview connected to the isolated test project.

That acceptance pass must include:

- Two approved accounts in the isolated test project.
- Creating a disposable workspace and assignment; uploading a real PDF resource.
- Downloading the original resource from the second account.
- Uploading multiple distinct submission versions from the second account.
- Downloading and verifying each version from the workspace owner account.
- Closing the assignment and confirming further submissions are blocked by both UI and database/Storage policies.
- Deleting the disposable workspace, refreshing Shared Study Workspaces, and confirming the private object prefix and cleanup job are removed.
- Repeating file picker, upload and download flows in iPhone Safari.

## Production application procedure (after the release gate)

1. Confirm the project ID shown in Supabase Dashboard is `pulokexhjdxrmsdpcmid` before running anything.
2. Export/backup the production database and preserve a copy of the current GitHub main commit.
3. Re-check the production migration history and verify that the four migration names are still absent.
4. Apply the four migrations in the order above, one at a time, recording each result. Do not rerun the historical root schema or unrelated SQL files.
5. Run the Security and Performance Advisors.
6. Verify the three assignment tables exist with RLS enabled, the private bucket exists, expected policies are present, and existing planner/workspace row counts are unchanged.
7. Deploy the approved frontend release and perform a short production smoke check with existing accounts.

## Failure handling

- If any migration errors, stop immediately and inspect the exact error and database state before retrying. Do not continue to later migrations.
- Do not delete or recreate the private bucket to recover from an error; it may contain user files after launch.
- Do not use SQL to delete Storage object bytes. The app cleanup worker uses the Storage API.
- Do not expose a service-role key in the frontend or use a service-role bypass for acceptance testing.
- No destructive rollback script is provided. These migrations are additive, but policy and trigger changes require a reviewed rollback plan if a production failure occurs.

## Current instruction

Keep production unchanged. Finish the redesign, publish a final isolated preview, and complete the desktop/two-account/iPhone acceptance pass before this production rollout is considered.