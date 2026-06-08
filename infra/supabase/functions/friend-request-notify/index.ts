// Edge Function: friend-request-notify
//
// US-023 / FRD-022: send an APNs push to the recipient of a friend request.
// Called by the client right after `FriendService.sendRequest` persists a new
// pending row, so the recipient gets a "new friend request" banner even when
// the app is backgrounded (Realtime only fires while the inbox is subscribed).
//
// Request:  POST { requestId } + Authorization: Bearer <JWT>
// Response: 200 { delivered: <int>, total: <int> }  — APNs accepted N of M tokens
//           400 { error: ... }                       — missing/invalid body
//           401 { error: ... }                       — missing/invalid JWT
//           403 { error: ... }                       — caller is not the requester
//           404 { error: "not found" }               — unknown request id
//           500 { error: ... }                       — lookup / APNs config failure
//
// APNs payload (aps.alert + custom keys):
//   { type: "friend_request", requesterHandle, requesterEmoji, requestId }
// The device's NotificationService routes `type == friend_request` → deep link
// to the friend-request inbox.
//
// Security:
//   - Verifies the caller's Supabase JWT (must be signed in).
//   - Re-checks ownership: the caller MUST be the request's `requester_id`.
//     A client cannot fire a push on behalf of someone else's request.
//   - Service role is used ONLY to read the recipient's push tokens
//     (device_push_tokens has a self-only SELECT policy — the requester cannot
//     read the recipient's tokens under RLS). Tokens never leave this function.
//
// Deploy:  `supabase functions deploy friend-request-notify`
// Secrets (token-based APNs, .p8 auth):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   (auto-injected by Supabase)
//   APNS_KEY_P8     — contents of the AuthKey_XXXX.p8 (PEM, incl. BEGIN/END)
//   APNS_KEY_ID     — the 10-char Key ID for that .p8
//   APNS_TEAM_ID    — the 10-char Apple Developer Team ID
//   APNS_TOPIC      — the app bundle id (e.g. com.solocompass.app)
//   APNS_HOST       — "api.push.apple.com" (prod) | "api.sandbox.push.apple.com" (dev)
//                     defaults to the sandbox host when unset.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

interface NotifyResult {
  delivered: number;
  total: number;
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

  // 2. Parse the request id.
  let body: { requestId?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json body" }, 400);
  }
  const requestId = typeof body.requestId === "string" ? body.requestId.trim() : "";
  if (!requestId) return json({ error: "requestId is required" }, 400);

  // 3. Service-role client — read the request row + recipient tokens (RLS would
  //    otherwise hide the recipient's tokens from the requester).
  const svc = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const { data: reqRow, error: reqErr } = await svc
    .from("friend_requests")
    .select("requester_id, recipient_id, status")
    .eq("id", requestId)
    .maybeSingle();

  if (reqErr) return json({ error: "lookup failed" }, 500);
  if (!reqRow) return json({ error: "not found" }, 404);

  // 4. Ownership: only the requester may trigger this push.
  if (reqRow.requester_id !== callerId) {
    return json({ error: "forbidden" }, 403);
  }

  const recipientId = reqRow.recipient_id as string;

  // 5. Resolve the requester's public preview (handle + emoji) for the banner.
  //    avatar_emoji lives on companion_profiles; the display handle is in the
  //    requester's auth metadata (same convention as redeem-friend-code).
  const { data: profile } = await svc
    .from("companion_profiles")
    .select("avatar_emoji")
    .eq("user_id", callerId)
    .maybeSingle();
  const requesterEmoji = (profile?.avatar_emoji as string | undefined) ?? "🧭";

  let requesterHandle = "";
  const { data: requesterUser } = await svc.auth.admin.getUserById(callerId);
  const meta = requesterUser?.user?.user_metadata as
    | { display_handle?: unknown; displayHandle?: unknown }
    | undefined;
  if (typeof meta?.display_handle === "string") requesterHandle = meta.display_handle;
  else if (typeof meta?.displayHandle === "string") requesterHandle = meta.displayHandle;
  if (!requesterHandle) requesterHandle = requesterEmoji; // never empty.

  // 6. Look up the recipient's device tokens. No tokens → nothing to deliver
  //    (recipient never enabled push or has no registered device). 200 with 0.
  const { data: tokens, error: tokensErr } = await svc
    .from("device_push_tokens")
    .select("token")
    .eq("user_id", recipientId);

  if (tokensErr) return json({ error: "token lookup failed" }, 500);
  const deviceTokens = (tokens ?? [])
    .map((r) => (typeof r.token === "string" ? r.token : ""))
    .filter((t) => t.length > 0);

  if (deviceTokens.length === 0) {
    const empty: NotifyResult = { delivered: 0, total: 0 };
    return json(empty, 200);
  }

  // 7. Build the APNs provider JWT (token-based auth, ES256 over the .p8 key).
  let apnsJwt: string;
  let topic: string;
  let apnsHost: string;
  try {
    const cfg = readApnsConfig();
    topic = cfg.topic;
    apnsHost = cfg.host;
    apnsJwt = await buildApnsJwt(cfg);
  } catch (e) {
    return json({ error: `apns config error: ${(e as Error).message}` }, 500);
  }

  // 8. Send to every registered device. APNs is one request per token.
  const apsPayload = JSON.stringify({
    aps: {
      alert: {
        title: requesterHandle,
        body: "sent you a friend request",
      },
      sound: "default",
    },
    type: "friend_request",
    requesterHandle,
    requesterEmoji,
    requestId,
  });

  let delivered = 0;
  await Promise.all(
    deviceTokens.map(async (deviceToken) => {
      try {
        const resp = await fetch(`https://${apnsHost}/3/device/${deviceToken}`, {
          method: "POST",
          headers: {
            "authorization": `bearer ${apnsJwt}`,
            "apns-topic": topic,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "content-type": "application/json",
          },
          body: apsPayload,
        });
        if (resp.status === 200) {
          delivered += 1;
        } else if (resp.status === 410) {
          // Token is no longer valid — prune it so we stop retrying.
          await svc.from("device_push_tokens").delete().eq("token", deviceToken);
        }
        // Other statuses (400/403/429/5xx) are left for the next attempt.
      } catch {
        // Network error to APNs — counted as not delivered; client may retry.
      }
    }),
  );

  const result: NotifyResult = { delivered, total: deviceTokens.length };
  return json(result, 200);
});

// ── APNs token-based auth ─────────────────────────────────────────────────────

interface ApnsConfig {
  keyId: string;
  teamId: string;
  topic: string;
  host: string;
  p8: string;
}

function readApnsConfig(): ApnsConfig {
  const p8 = Deno.env.get("APNS_KEY_P8") ?? "";
  const keyId = Deno.env.get("APNS_KEY_ID") ?? "";
  const teamId = Deno.env.get("APNS_TEAM_ID") ?? "";
  const topic = Deno.env.get("APNS_TOPIC") ?? "";
  const host = Deno.env.get("APNS_HOST") ?? "api.sandbox.push.apple.com";
  if (!p8 || !keyId || !teamId || !topic) {
    throw new Error("missing APNS_KEY_P8 / APNS_KEY_ID / APNS_TEAM_ID / APNS_TOPIC");
  }
  return { keyId, teamId, topic, host, p8 };
}

/// Build a short-lived APNs provider JWT signed with the .p8 ES256 key.
async function buildApnsJwt(cfg: ApnsConfig): Promise<string> {
  const privateKey = await importP8Key(cfg.p8);
  return await create(
    { alg: "ES256", kid: cfg.keyId, typ: "JWT" },
    { iss: cfg.teamId, iat: getNumericDate(0) },
    privateKey,
  );
}

/// Import a PKCS#8 .p8 PEM private key as a WebCrypto ES256 signing key.
async function importP8Key(pem: string): Promise<CryptoKey> {
  const der = pemToDer(pem);
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

/// Strip PEM armor + whitespace and base64-decode to the DER bytes.
function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
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
