# Add-user invitations — deployment guide

This feature adds an invitation form to the existing Owner Admin panel. It uses a Supabase Edge Function so the Supabase service-role key is never shipped to the browser.

## Files in this change

- `index.html`: owner-only invitation form.
- `supabase/functions/admin-invite-user/index.ts`: verifies the signed-in caller with Supabase Auth, checks `uniplanner_is_admin()`, then sends an invitation using the server-side Admin API.
- `set-password.html`: invitation landing page where the invitee chooses and confirms their own password.
- No database migration is needed. The existing Auth-user trigger from `owner-admin-panel-migration.sql` creates a `pending` access row.

## One-time deployment

1. Install and sign in to the Supabase CLI, then link the existing project:
   ```sh
   supabase login
   supabase link --project-ref pulokexhjdxrmsdpcmid
   ```
2. In Supabase Dashboard → Project Settings → API, ensure the Edge Function runtime has its standard `SUPABASE_URL`, `SUPABASE_ANON_KEY` (or `SUPABASE_PUBLISHABLE_KEY`) and `SUPABASE_SERVICE_ROLE_KEY` environment values. If your project does not provide these automatically, configure them as Edge Function secrets in the dashboard. Never put the service-role/secret key in GitHub, HTML, or any browser setting.
3. Set the app URL secret and deploy:
   ```sh
   supabase secrets set APP_SITE_URL=https://ahmdoutoforder.github.io/Activity-Manager
   supabase functions deploy admin-invite-user
   ```
4. In Supabase Dashboard → Authentication → URL Configuration, add this exact Redirect URL:
   `https://ahmdoutoforder.github.io/Activity-Manager/set-password.html`
   Keep the project's Site URL configured appropriately. The invite redirect must be allowed or Supabase may reject it or redirect elsewhere.
5. Confirm Supabase email delivery is configured (custom SMTP is recommended for reliable delivery). Test with an email you control first.

## How to test after merge/deploy

1. Sign in to UniPlanner as an approved owner.
2. Open Owner admin → Invite a user and enter an email you control that is not already registered.
3. Send the invitation. The invitee should receive an email and open its link.
4. On the password page, choose a password of at least 8 characters. They should then land on UniPlanner and see the access-pending message.
5. As owner, refresh the admin account list and approve the new user. The invitee can then sign in with their email and chosen password.

## Security and behavior

- The Edge Function requires a valid authenticated session and checks the existing owner RPC on every request.
- It validates the email and restricts browser Origin to the GitHub Pages origin.
- The invitation is sent by the Supabase Admin API using a server-side secret only.
- The function never approves access automatically; it relies on the existing Auth-user trigger and owner approval RPC.
- Existing tables, user identities, workspace memberships, and planner data are not reset or deleted.
- The email address mentioned in the feature request is not hardcoded and no invitation is sent merely by deploying this code.
