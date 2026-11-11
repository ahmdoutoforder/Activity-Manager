# UniPlanner RLS and foreign-key performance hardening test plan

## Scope
- Adds 14 ordinary B-tree indexes to cover foreign-key columns that lacked a leading index.
- Rewrites statement-constant `auth.uid()` / `auth.jwt()` policy calls as scalar subqueries so Postgres can evaluate them once per statement.
- Revokes RPC execution on the internal `rls_auto_enable()` event-trigger function.
- Pins SECURITY DEFINER routines to `search_path = pg_catalog, public`.
- Does not alter row data, ownership rules, workspace membership rules, or user access status.

## Validation
1. Apply the index/RLS migration to the isolated test project.
2. Apply the follow-up function/policy migration to the isolated test project.
3. Confirm all 14 expected indexes exist.
4. Confirm no unwrapped statement-constant `auth.uid()` / `auth.jwt()` calls remain in the affected policies.
5. Confirm `anon` and `authenticated` cannot execute `public.rls_auto_enable()`.
6. Confirm every SECURITY DEFINER routine has an explicit trusted search path.
7. Run Supabase Security and Performance Advisors; distinguish intentional authenticated RPC warnings from accidental anonymous exposure.
8. Verify existing row counts are unchanged.
9. Repeat the migrations on production only after test validation; repeat advisor and row-count checks.

## Expected advisor outcomes
- No missing foreign-key index warnings for the 14 covered constraints.
- No RLS init-plan warnings for the rewritten policies.
- No anonymous EXECUTE warning for `rls_auto_enable()`.
- Authenticated SECURITY DEFINER warnings may remain for application RPCs. Each one must retain its explicit caller authorization checks; do not revoke them indiscriminately.
- Leaked-password protection remains a dashboard Auth setting and is not changed by these SQL migrations.
