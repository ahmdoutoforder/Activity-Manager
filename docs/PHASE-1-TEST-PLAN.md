# Phase 1 hardening verification plan

Run this only against the isolated test Supabase project first. Production rollout requires a reviewed migration and a fresh data-count snapshot.

## Permission checks

- [ ] `anon` has no direct SELECT/INSERT/UPDATE/DELETE/TRUNCATE privilege on public UniPlanner tables.
- [ ] `authenticated` retains only the table CRUD privileges required by the app.
- [ ] `authenticated` has no TRUNCATE, TRIGGER, or REFERENCES privilege on public app tables.
- [ ] `anon` and `authenticated` have no direct privileges on public identity sequences.
- [ ] New public tables created by the PostgreSQL migration owner inherit the restricted table defaults.
- [ ] New public functions created by the PostgreSQL migration owner do not grant EXECUTE to PUBLIC, anon, or authenticated by default.
- [ ] New public sequences created by the PostgreSQL migration owner do not grant sequence privileges to anon or authenticated by default.
- [ ] Required RPCs retain explicit authenticated EXECUTE; anon cannot execute them.

## Workspace integrity and authorization

- [ ] Owner creates a workspace; owner is inserted as the first member.
- [ ] Approved member can join through a valid invitation or owner-approved join request.
- [ ] Unapproved/revoked account cannot read or mutate protected workspace data.
- [ ] Non-member cannot read workspace tasks, notes, resources, comments, messages, or activity.
- [ ] Member can update a shared task but cannot move it to another workspace or change its creator.
- [ ] Assigning a task to a same-workspace member succeeds.
- [ ] Assigning to a non-member or cross-workspace user fails.
- [ ] Only the workspace owner/site admin can delete a workspace.
- [ ] When an owner leaves a multi-member workspace, ownership transfers to the next member; the departing owner is removed.
- [ ] Owner cannot leave as the only member without deleting the workspace or inviting a successor.
- [ ] A member can leave without deleting shared workspace content.

## Personal planner and sync

- [ ] Two approved accounts can read/write only their own personal `uniplanner_data` row.
- [ ] Export and import preserve tasks, classes, grades, attendance, faculty, notes, preferences, and focus-session state.
- [ ] Cloud-newer and local-newer cases both display the intended confirmation/status.
- [ ] A failed cloud request does not erase the local copy.
- [ ] Simultaneous edits are treated as a last-write-wins limitation, not assumed to merge.

## Notifications and devices

- [ ] Desktop browser task reminders work with permission granted.
- [ ] Study Group Realtime alerts work while the signed-in page is open.
- [ ] Realtime is enabled for group messages, task comments, and shared tasks.
- [ ] Test iPhone browser and installed-PWA behavior separately; do not claim background delivery without a Web Push sender and service-worker push handler.

## Post-migration verification

- [ ] Rerun Supabase Security, Performance, and Health Advisors.
- [ ] Confirm all 15 public app tables have RLS enabled.
- [ ] Compare production/test columns, constraints, indexes, triggers, policies, and RPC signatures.
- [ ] Confirm production row counts match the pre-migration snapshot.
- [ ] Record migration version and source SQL file in the audit.
