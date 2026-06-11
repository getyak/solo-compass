// Edge Function: moderate-action
//
// Platform moderation gateway. Lets a signed-in moderator/admin take actions
// that clients are NOT allowed to perform directly (the companion_profiles
// guard trigger blocks role/ban writes from anyone but the service role).
//
// Request:  POST + Authorization: Bearer <JWT>
//   { action: "ban",          targetUserId }                — moderator | admin
//   { action: "unban",        targetUserId }                — moderator | admin
//   { action: "resolveReport", reportId }                   — moderator | admin
//   { action: "setRole",      targetUserId, role }          — admin only
//
// Response: 200 { ok: true, ... }
//           400 { error } invalid body
//           401 { error } missing/invalid JWT
//           403 { error } caller lacks the required role
//           404 { error } target/report not found
//
// Security:
//   - Verifies the caller's Supabase JWT.
//   - Looks up the caller's role via the service role (bypassing RLS) and
//     enforces it server-side — never trusts a client-sent role.
//   - All writes go through the service role so the privilege guard trigger
//     permits the role/ban change.
//   - A moderator/admin cannot ban or demote themselves through this path
//     (prevents self-lockout / accidental privilege loss).
//
// Deploy: `supabase functions deploy moderate-action`
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Action = "ban" | "unban" | "resolveReport" | "setRole";
type Role = "user" | "moderator" | "admin";

const VALID_ROLES: ReadonlySet<string> = new Set(["user", "moderator", "admin"]);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  // 1. Verify the caller's JWT.
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer /i, "");
  if (!jwt) return json({ error: "missing bearer token" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const userClient = createClient(supabaseUrl, jwt, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
    auth: { persistSession: false },
  });
  const {
    data: { user },
    error: authError,
  } = await userClient.auth.getUser();
  if (authError || !user) return json({ error: "unauthorized" }, 401);
  const callerId = user.id;

  // 2. Parse the body.
  let body: { action?: unknown; targetUserId?: unknown; reportId?: unknown; role?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json body" }, 400);
  }
  const action = body.action as Action | undefined;
  if (!action || !["ban", "unban", "resolveReport", "setRole"].includes(action)) {
    return json({ error: "unknown action" }, 400);
  }

  // 3. Service-role client + caller role lookup (enforced server-side).
  const svc = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const callerRole = await roleOf(svc, callerId);
  if (callerRole !== "moderator" && callerRole !== "admin") {
    return json({ error: "forbidden" }, 403);
  }

  // 4. Dispatch.
  switch (action) {
    case "ban":
    case "unban": {
      const targetUserId = strOrNull(body.targetUserId);
      if (!targetUserId) return json({ error: "targetUserId is required" }, 400);
      if (targetUserId === callerId) {
        return json({ error: "cannot ban yourself" }, 400);
      }
      // A moderator may not ban an admin; only an admin can touch an admin.
      const targetRole = await roleOf(svc, targetUserId);
      if (targetRole === "admin" && callerRole !== "admin") {
        return json({ error: "forbidden" }, 403);
      }
      const { error } = await svc
        .from("companion_profiles")
        .update({ is_banned: action === "ban", updated_at: new Date().toISOString() })
        .eq("user_id", targetUserId);
      if (error) return json({ error: error.message }, 500);
      return json({ ok: true, action, targetUserId });
    }

    case "resolveReport": {
      const reportId = strOrNull(body.reportId);
      if (!reportId) return json({ error: "reportId is required" }, 400);
      const { data, error } = await svc
        .from("companion_reports")
        .update({ resolved_at: new Date().toISOString(), resolved_by: callerId })
        .eq("id", reportId)
        .select("id")
        .maybeSingle();
      if (error) return json({ error: error.message }, 500);
      if (!data) return json({ error: "not found" }, 404);
      return json({ ok: true, action, reportId });
    }

    case "setRole": {
      // Role changes are admin-only.
      if (callerRole !== "admin") return json({ error: "forbidden" }, 403);
      const targetUserId = strOrNull(body.targetUserId);
      const role = strOrNull(body.role);
      if (!targetUserId) return json({ error: "targetUserId is required" }, 400);
      if (!role || !VALID_ROLES.has(role)) return json({ error: "invalid role" }, 400);
      if (targetUserId === callerId) {
        // Guard against an admin demoting themselves and losing access.
        return json({ error: "cannot change your own role" }, 400);
      }
      const { error } = await svc
        .from("companion_profiles")
        .update({ role: role as Role, updated_at: new Date().toISOString() })
        .eq("user_id", targetUserId);
      if (error) return json({ error: error.message }, 500);
      return json({ ok: true, action, targetUserId, role });
    }

    default:
      return json({ error: "unknown action" }, 400);
  }
});

/** Resolve a user's platform role via the service role. Defaults to "user". */
async function roleOf(svc: ReturnType<typeof createClient>, userId: string): Promise<Role> {
  const { data } = await svc
    .from("companion_profiles")
    .select("role, is_banned")
    .eq("user_id", userId)
    .maybeSingle();
  // A banned account is treated as having no privileges.
  if (data?.is_banned) return "user";
  const r = data?.role as string | undefined;
  return r === "admin" || r === "moderator" ? r : "user";
}

function strOrNull(v: unknown): string | null {
  return typeof v === "string" && v.trim().length > 0 ? v.trim() : null;
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
