# UniPlanner workspace assignments and private Storage — test record

**Status:** Implemented on feature branch; isolated Supabase schema and RLS tests passed. Production rollout is pending a signed-in browser upload/download smoke test and review of workspace-deletion file cleanup.

## Feature behavior

- Workspace members can create assignments with instructions, optional due date/time, and an optional project link.
- Assignment creators and workspace owners can attach original resource files.
- Every member can view/download original resources and every member's submission files.
- Members can upload only into their own submitter-specific folder.
- Every upload/resubmission creates a new, immutable file path and metadata row; prior submission versions remain visible until the submitter removes their own version.
- Assignment creator/workspace owner can close or reopen submissions. Closed assignments do not accept new submissions in the UI.
- Assignments are archived/closed rather than hard-deleted, protecting their history.
- Files are in the private `uniplanner-workspace-files` bucket. Public access is disabled.
- File size is capped at 20 MiB. Allowed MIME types: PDF, Word, PowerPoint, Excel, plain text, CSV, JSON, ZIP, PNG and JPEG.
- Storage uploads use unique names with `upsert: false`; the bucket has no object UPDATE policy.

## Migration order

1. `workspace-assignments-storage-migration.sql` — creates the private bucket, assignment/resource/submission tables, triggers, RLS policies and Storage object policies.
2. `workspace-assignment-indexes-migration.sql` — adds supporting indexes to every newly introduced foreign key.
3. `workspace-assignment-submission-status-migration.sql` — makes Postgres reject both Storage uploads and submission rows when an assignment is closed or archived.

All three migrations have been applied and recorded only in the isolated Supabase project `uniplanner test` under migration names:
- `workspace_assignments_private_storage`
- `workspace_assignment_fk_indexes`
- `workspace_assignment_submission_status`

No production Supabase schema, bucket, Storage object or user data was changed by this phase.

## Verified test-project facts

- Bucket exists and is private (`public = false`).
- Bucket file-size limit is 20,971,520 bytes (20 MiB).
- Allowed MIME list matches the UI allowlist.
- All three assignment tables have RLS enabled.
- Storage object RLS is enabled and policies exist for member download, creator/owner original-resource upload, submitter-owned submission upload, and scoped deletes.
- New foreign keys have supporting indexes; the Supabase Performance Advisor no longer reports unindexed foreign keys for these tables.
- Security Advisor findings remain the previously documented items: 18 intentional authenticated-callable SECURITY DEFINER functions, the intentionally policy-free RLS-protected `uniplanner_admins` table (INFO), and the existing leaked-password setting warning.

## Rolled-back two-account RLS fixture

A transaction using the two approved test accounts verified:

1. A workspace member can read the assignment and its original resource metadata.
2. A workspace member can download/read the original resource object through the object policy.
3. A regular member cannot upload an original assignment resource when they are not the assignment creator or workspace owner.
4. A member can upload a submission to their own user-specific folder and register its submission row.
5. A different member in the same workspace can read the submission metadata and file object.
6. A user cannot upload into another member's submission folder.
7. A user cannot read an assignment in a separate workspace where they are not a member.
8. A member cannot bypass a closed assignment by uploading a file directly to Storage.
9. A member cannot insert submission metadata directly for a closed assignment.

The closed-assignment tests confirmed both attempts were rejected by RLS, and no submission row was created.

The test used temporary `storage.objects` metadata rows to exercise RLS policies; it did **not** transfer real file bytes through the Storage HTTP API. The transaction was rolled back. The isolated test project returned to zero test workspaces, assignments, resources, submissions and Storage object rows.

## Required before production rollout

- Perform a signed-in browser test with both test accounts using the actual application: create an assignment, upload an original PDF, submit a file from account B, download account B's submission from account A, submit a second version and verify both versions remain available.
- Verify rejected file types and files larger than 20 MiB are blocked by both browser validation and the bucket configuration.
- Check iPhone Safari and desktop browser behavior for file picker, upload progress/errors, and download.
- Resolve storage-object cleanup for hard workspace deletion. Existing workspace deletion cascades relational rows, but Storage objects require deletion through the Storage API; they must not be deleted by directly deleting rows from `storage.objects`. Until a reviewed cleanup flow is in place, do not treat workspace deletion as deleting stored file bytes.
- Only after those checks should the same two migrations be reviewed for production application.

## Security design notes

The private bucket's Storage policies are separate from the public-table RLS policies. The object download rule resolves the workspace and assignment IDs from the object path and requires current approved membership. Assignment/submission metadata RLS independently enforces membership and submitter identity. No Storage public URL is generated; clients use authenticated `download(path)` calls.
