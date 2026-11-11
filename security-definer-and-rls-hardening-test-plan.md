# Security-definer and RLS hardening test plan

Run after `security-definer-and-rls-hardening-migration.sql` on the isolated test project and production.

- Confirm `anon` and `authenticated` cannot execute `public.rls_auto_enable()`.
- Confirm all public SECURITY DEFINER functions have `search_path = pg_catalog, public` (event-trigger function remains `pg_catalog`).
- Confirm the seven affected RLS policy predicates still encode the same ownership, membership, identity, and invitee conditions.
- Run Supabase Security and Performance Advisors; the anonymous event-trigger warning and RLS init-plan warnings should clear.
- Authenticated SECURITY DEFINER warnings for application RPCs are expected only where a verified caller check is present.
- Confirm row counts and access-state rows are unchanged.
- Do not change the leaked-password setting as part of this SQL migration; enable it separately in Auth settings after reviewing the current password policy.
