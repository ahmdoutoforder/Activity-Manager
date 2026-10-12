// Securely invite a UniPlanner user. The service-role key is used only inside this Edge Function.
// Deploy with: supabase functions deploy admin-invite-user
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const appOrigin = "https://ahmdoutoforder.github.io";
const corsHeaders = {
  "Access-Control-Allow-Origin": appOrigin,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.headers.get("origin") && req.headers.get("origin") !== appOrigin) {
    return json(403, { error: "Origin not allowed." });
  }
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json(405, { error: "Method not allowed." });

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return json(401, { error: "Sign in with an owner-approved account first." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const appSiteUrl = Deno.env.get("APP_SITE_URL") ?? "https://ahmdoutoforder.github.io/Activity-Manager";
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    console.error("Required Supabase Edge Function environment is missing.");
    return json(500, { error: "Invitation service is not configured. Ask the project owner to check Edge Function secrets." });
  }

  try {
    const token = authorization.slice("Bearer ".length);
    const caller = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const { data: userResult, error: userError } = await caller.auth.getUser(token);
    if (userError || !userResult.user) return json(401, { error: "Your session is invalid or expired. Sign in again." });

    const { data: isAdmin, error: adminError } = await caller.rpc("uniplanner_is_admin");
    if (adminError || isAdmin !== true) return json(403, { error: "Only a UniPlanner owner can send invitations." });

    let body: unknown;
    try { body = await req.json(); } catch { return json(400, { error: "Request body must be valid JSON." }); }
    const email = typeof body === "object" && body !== null && "email" in body
      ? String((body as { email: unknown }).email ?? "").trim().toLowerCase()
      : "";
    if (email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
      return json(400, { error: "Enter a valid email address." });
    }
    if (email === userResult.user.email?.toLowerCase()) {
      return json(400, { error: "You are already signed in with this email address." });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
    });
    const redirectTo = appSiteUrl.replace(/\/$/, "") + "/set-password.html";
    const { data, error } = await admin.auth.admin.inviteUserByEmail(email, { redirectTo });
    if (error) {
      console.error("Supabase invite failed:", error.message);
      const msg = /already|registered|exists/i.test(error.message)
        ? "An account may already exist for that email. Check the account list before inviting again."
        : "Supabase could not send the invitation. Check email delivery settings and Auth redirect URLs.";
      return json(400, { error: msg });
    }

    // The auth.users insert trigger from owner-admin-panel-migration.sql creates a pending
    // uniplanner_access row. Never grant access here; owner approval remains a separate action.
    return json(200, { ok: true, user_id: data.user?.id ?? null, email });
  } catch (error) {
    console.error("Unexpected invitation error:", error instanceof Error ? error.message : "unknown");
    return json(500, { error: "Unexpected invitation error. Check the Edge Function logs." });
  }
});
