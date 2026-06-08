// Edge Function: redeem-friend-code
//
// US-022 / FRD-026 / FR-20: Resolve a typed/scanned friend code to a public
// profile preview so the caller can decide to send a friend request.
//
// Request:  POST { code: "SOLO-XXXX-XXXX" } + Authorization: Bearer <JWT>
// Response: 200 { userId, handle, avatarEmoji }  — resolved profile
//           404 { error: "not found" }            — unknown / revoked code
//           400 { error: ... }                    — missing/invalid body
//           401 { error: ... }                    — missing/invalid JWT
//
// Security:
//   - Verifies the caller's Supabase JWT (must be signed in).
//   - Uses the service role to bypass RLS for the REDEEM path only: the
//     friend_codes table has NO public SELECT policy, so codes cannot be
//     enumerated by clients. This function is the single resolve gateway.
//   - Anti-enumeration: revoked codes and unknown codes return the SAME 404
//     ("not found"), so a caller cannot distinguish "never existed" from
//     "revoked" — and the response never leaks the code itself back.
//   - Self-redeem (your own code) returns 404 too: you can't friend yourself.
//
// Deploy: `supabase functions deploy redeem-friend-code`
// Secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Friend code shape: SOLO-XXXX-XXXX (case-insensitive on input; stored upper).
const CODE_PATTERN = /^SOLO-[A-Z0-9]{4}-[A-Z0-9]{4}$/;

interface RedeemResult {
  userId: string;
  handle: string;
  avatarEmoji: string;
}

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
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  // 1. Verify JWT — caller must be signed in.
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

  // 2. Parse + normalize the code.
  let body: { code?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json body" }, 400);
  }
  const rawCode = typeof body.code === "string" ? body.code.trim().toUpperCase() : "";
  if (!rawCode) return json({ error: "code is required" }, 400);
  if (!CODE_PATTERN.test(rawCode)) {
    // Malformed input — distinct from "valid-but-unknown" (which is 404).
    return json({ error: "invalid code format" }, 400);
  }

  // 3. Service-role client — bypass RLS for the redeem path only.
  const svc = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  // 4. Resolve the code → user_id. A live code has revoked_at IS NULL.
  //    Unknown OR revoked codes both fall through to the SAME 404 below
  //    (anti-enumeration: no information leak about which case occurred).
  const { data: codeRow, error: codeErr } = await svc
    .from("friend_codes")
    .select("user_id, revoked_at")
    .eq("code", rawCode)
    .maybeSingle();

  if (codeErr) return json({ error: "lookup failed" }, 500);

  if (!codeRow || codeRow.revoked_at !== null) {
    return json({ error: "not found" }, 404);
  }

  const targetId = codeRow.user_id as string;

  // 5. Self-redeem is not allowed — you can't add yourself.
  //    Same 404 so the code's owner identity is never confirmed.
  if (targetId === callerId) {
    return json({ error: "not found" }, 404);
  }

  // 6. Load the target's public profile preview.
  //    avatar_emoji lives on companion_profiles; the display handle is stored
  //    in the user's auth metadata (raw_user_meta_data.display_handle, written
  //    by the profile sync). Both have safe fallbacks so a code always resolves
  //    to a usable preview once it points at a real user.
  const { data: profile } = await svc
    .from("companion_profiles")
    .select("avatar_emoji")
    .eq("user_id", targetId)
    .maybeSingle();

  const avatarEmoji = (profile?.avatar_emoji as string | undefined) ?? "🧭";

  let handle = "";
  const { data: targetUser } = await svc.auth.admin.getUserById(targetId);
  const meta = targetUser?.user?.user_metadata as
    | { display_handle?: unknown; displayHandle?: unknown }
    | undefined;
  if (typeof meta?.display_handle === "string") handle = meta.display_handle;
  else if (typeof meta?.displayHandle === "string") handle = meta.displayHandle;
  if (!handle) handle = avatarEmoji; // last-resort label — never empty.

  const result: RedeemResult = { userId: targetId, handle, avatarEmoji };
  return json(result, 200);
});

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
