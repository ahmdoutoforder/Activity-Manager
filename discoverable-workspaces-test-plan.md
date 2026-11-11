# Discoverable study workspaces — test plan

## Behavior
- Only approved, signed-in users can discover workspaces.
- Discovery returns only workspaces explicitly marked `discoverable` and `request_to_join`.
- Members are excluded from discovery results.
- Discovery exposes only workspace name/type/created date/member count and the caller's latest request status.
- Join requests are created through a SECURITY DEFINER RPC that verifies workspace mode, account approval and existing membership.
- Only one pending request per user/workspace is allowed. A rejected or cancelled request may be submitted again.
- Owners continue to approve/reject through `uniplanner_review_workspace_join_request`.
- Requesters can cancel their own pending request through `uniplanner_cancel_workspace_join_request`.

## Validation completed
- Applied the migration to both the isolated test project and production project after a successful rollback-only dry run against production.
- Ran transactional two-account tests in both environments.
- Confirmed discovery returns only discoverable/request-to-join workspaces and excludes private workspaces.
- Confirmed duplicate pending requests are rejected.
- Confirmed owners can approve/reject; approval creates membership atomically and removes the workspace from the member's discovery results.
- Confirmed requesters can cancel pending requests and submit a new request after cancellation or rejection.
- All temporary test workspaces, memberships and requests were rolled back; production row counts remain unchanged.

## Two-account validation
1. Owner creates a workspace and sets visibility to discoverable and join mode to request_to_join.
2. Approved non-member searches and sees only that workspace; private/invite-only workspaces are not returned.
3. Non-member submits a request; owner sees it in Join Requests.
4. Duplicate pending request is rejected.
5. Owner rejects; requester can submit a new request.
6. Owner approves; membership is created atomically and workspace disappears from discovery for that member.
7. Unapproved user and anonymous caller cannot discover or request.
8. Existing workspace rows and all planner/collaboration data remain unchanged.
