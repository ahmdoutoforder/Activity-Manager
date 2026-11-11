# Collaboration security workflows — test-only validation

**Target:** isolated UniPlanner test project only (project ref rigsjtbaoxkdbumwuhdn).  
**Never run this migration against production without a separately reviewed rollout plan.**

## What this migration changes
- Workspace invitations become pending invitations; they no longer add membership immediately.
- Owners review join requests through a server-side RPC that atomically creates membership and records the decision.
- Invitees accept or decline through a server-side RPC; acceptance atomically creates membership.
- Clients can no longer directly update invitation state or approve join requests.
- Requesters can only cancel their own pending requests.
- Project/resource deletion is limited to the creator or workspace owner.
- Client-side activity inserts are disabled; trusted workflows write activity rows.

## Preconditions
1. Verify the dashboard project URL is https://rigsjtbaoxkdbumwuhdn.supabase.co.
2. Confirm the base UniPlanner schema, workspace tables, and approved test accounts exist.
3. Export the test schema first if it contains anything worth retaining.
4. Apply this migration only to the test project.

## Two-account validation
Use two approved accounts, A (workspace owner) and B (classmate):
1. A invites B. Confirm B is not a member yet and the invitation row is pending.
2. B accepts the invitation via uniplanner_respond_workspace_invitation; confirm B becomes a member and invitation status becomes accepted.
3. Create a discoverable/request-to-join workspace. B submits a join request. A approves with uniplanner_review_workspace_join_request; confirm membership and request status change together.
4. Repeat with reject; confirm no membership is created.
5. Confirm B cannot review requests, accept another user's invitation, or directly update invitation/request status.
6. Confirm a requester can cancel only their own pending request.
7. Confirm a non-member cannot read workspace content; an unapproved account cannot use collaboration RPCs.
8. Confirm creators can delete their own projects/resources; other members cannot; workspace owners can.
9. Confirm the existing personal planner payload and existing workspace tasks, notes, comments, and messages remain unchanged.

## Important boundaries
- This migration does not modify uniplanner_data, auth approval state, existing workspace memberships, or production.
- Open joining remains disabled in the UI until a dedicated safe discovery/join flow is implemented.
