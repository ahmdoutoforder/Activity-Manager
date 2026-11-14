# UniPlanner workspace assignments and private Storage — test record

**Status:** Assignment UI and schema are merged to `main`. The client-side workspace Storage cleanup worker is now implemented and covered by mocked pagination/failure tests. Production rollout is still pending a real signed-in browser upload/download smoke test (desktop and iPhone Safari) and an isolated authenticated Storage API test.

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
4. `workspace-storage-cleanup-migration.sql` — records a requester-scoped cleanup job in the same transaction as workspace deletion, then permits only that requester or a site admin to list/delete the deleted workspace's private Storage objects.

All four migrations have been applied and recorded only in the isolated Supabase project `uniplanner test` under migration names:
- `workspace_assignments_private_storage`
- `workspace_assignment_fk_indexes`
- `workspace_assignment_submission_status`
- `workspace_storage_cleanup_jobs`

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
- The client cleanup worker runs before the workspace list is loaded after sign-in/open. It reads only cleanup jobs visible to the current requester/admin, recursively lists the workspace prefix (100 entries per page), validates every object path against the assignment-resource/submission layout, removes files through the Storage API in batches of at most 1,000, and deletes the queue row only after all removals succeed. If listing/removal fails, or an unexpected object path is found, the row remains queued for a later retry. The worker does not use a service-role key and does not delete rows from `storage.objects` with SQL.
- When an upload succeeds but its metadata insert fails, the client checks the returned Storage removal error instead of swallowing it. If that compensating removal also fails, the UI reports the error and exact private object path for owner cleanup. This one-off upload rollback is not a separate durable queue; the workspace-deletion queue handles the full workspace lifecycle.
- Before production rollout, verify the cleanup worker against actual Storage API objects (not just `storage.objects` metadata rows) using an authenticated browser session.
- Only after those checks should the same two migrations be reviewed for production application.

## Security design notes

The private bucket's Storage policies are separate from the public-table RLS policies. The object download rule resolves the workspace and assignment IDs from the object path and requires current approved membership. Assignment/submission metadata RLS independently enforces membership and submitter identity. No Storage public URL is generated; clients use authenticated `download(path)` calls.


## Workspace Storage cleanup worker

The worker is invoked when the signed-in app loads the Shared Study Workspaces list. It is safe to retry: a failed Storage listing/removal leaves the queue job intact, while successfully removed objects can be encountered again if another tab is processing the same job. The worker follows the current private bucket layout only:
- `workspace_id/assignment_id/resources/file`
- `workspace_id/assignment_id/submissions/user_id/file`

It rejects unknown object layouts instead of deleting files outside those expected paths. The Supabase Storage API's documented `remove` maximum is 1,000 objects per request; the worker respects that batch size. See the [Supabase Storage delete-objects guide](https://supabase.com/docs/guides/storage/management/delete-objects).

### Additional verification still required

- In the test project, delete a disposable workspace that has both an original resource and at least two member submissions. Confirm the trigger creates one cleanup job and that the requester can list and remove every nested file after the workspace rows cascade away.
- Confirm a different ordinary member cannot read the cleanup job or list/delete those same orphaned object paths; confirm a site admin can complete a stuck job.
- Exercise pagination with more than 100 objects and deletion batching with more than 1,000 objects. The automated unit test uses mocked Storage responses for these paths.
- Force a Storage list/remove error. Confirm the cleanup row remains and the next workspace-list load retries it.
- Use two signed-in browser accounts to upload a real PDF, submit two versions, download the other member's version, then delete the disposable workspace and verify the real files disappear from the private bucket.
- Repeat the real file-picker/upload/download smoke test in iPhone Safari. SQL policy fixtures and mocked unit tests do not replace these checks.
