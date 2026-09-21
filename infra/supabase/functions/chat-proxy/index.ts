// Edge Function: chat-proxy
// Pro-tier proxy for DeepSeek /chat/completions so the iOS bundle
// never contains the DeepSeek API key. Mirrors the auth + entitlement
// gate from synthesize-experiences (Epic E US-030).
//
// Flow:
//   1. Verify Supabase JWT from Authorization header → user_id.
//   2. Look up profiles.entitlement_tier; free / pro_expired → 402.
//   3. Rate-limit: per-day call count in sc_function_calls (kind-specific).
//   4. Forward the body to DeepSeek's OpenAI-compatible endpoint.
//      Stream responses (body.stream === true) are piped through unchanged
//      so the iOS AIService can consume the same SSE format it already
//      handles for direct calls.
//   5. Non-streaming responses are read once and returned as-is.
//
// Deploy:  `supabase functions deploy chat-proxy`
// Secrets: DEEPSEEK_API_KEY, DEEPSEEK_BASE_URL (optional, defaults to
//          https://api.deepseek.com/v1), SUPABASE_URL,
//          SUPABASE_SERVICE_ROLE_KEY.
//
// Request body (OpenAI-compatible — the iOS AIService already builds
// this shape):
//   {
//     model:    string,              // ignored; server forces deepseek-flash
//     messages: ChatMessage[],
//     tools?:   ToolSpec[],
//     tool_choice?: "auto" | "none" | { ... },
//     parallel_tool_calls?: boolean,
//     stream?:  boolean,
//     max_tokens?: number,
//     temperature?: number,
//     // Solo Compass extension — picks the daily quota bucket:
//     kind?: "voice" | "explanation" | "synthesis"
//   }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { DEFAULT_DEEPSEEK_MODEL, deepSeekBaseUrl } from "../_shared/deepseek.ts";

// Daily caps mirror AIService.dailySynthesisQuota / dailyExplanationQuota
// so the server-side limit lines up with the on-device estimate.
const QUOTA: Record<string, number> = {
  voice: 30,
  synthesis: 30,
  explanation: 60,
};

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  // 1. Auth
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer /i, "");
  if (!jwt) return json({ error: "missing bearer token" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const deepseekKey = Deno.env.get("DEEPSEEK_API_KEY");
  const deepseekBase = deepSeekBaseUrl(Deno.env.get("DEEPSEEK_BASE_URL"));
  if (!deepseekKey) return json({ error: "server misconfigured" }, 500);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData.user) return json({ error: "invalid jwt" }, 401);
  const userId = userData.user.id;

  // 2. Entitlement gate.
  const { data: profile } = await admin
    .from("profiles")
    .select("entitlement_tier")
    .eq("user_id", userId)
    .maybeSingle();
  const tier = profile?.entitlement_tier ?? "free";
  if (tier === "free" || tier === "pro_expired") {
    return json({ error: "subscription required" }, 402);
  }

  // 3. Parse body.
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  if (!Array.isArray(body.messages) || (body.messages as unknown[]).length === 0) {
    return json({ error: "messages required" }, 400);
  }

  const kind = typeof body.kind === "string" ? body.kind : "voice";
  const dailyCap = QUOTA[kind] ?? QUOTA.voice;
  const functionName = `chat-proxy:${kind}`;

  // 3a. Rate-limit per (user, kind, UTC day).
  const dayStart = new Date();
  dayStart.setUTCHours(0, 0, 0, 0);
  const { count } = await admin
    .from("sc_function_calls")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("function_name", functionName)
    .gte("called_at", dayStart.toISOString());
  if ((count ?? 0) >= dailyCap) {
    return json({ error: "daily quota exceeded", quota: dailyCap, kind }, 429);
  }

  // 4. Forward to DeepSeek. This proxy is service-paid and DeepSeek-only, so
  //    the server OWNS model + thinking: we drop the client's `kind`
  //    accounting field and force `model=deepseek-flash` with top-level
  //    `thinking:{"type":"disabled"}` regardless of what an older (or
  //    malicious) client sent. Explicit OpenAI/custom provider support lives
  //    on configured direct client paths, not here.
  const forwardBody: Record<string, unknown> = {
    ...body,
    model: DEFAULT_DEEPSEEK_MODEL,
    thinking: { type: "disabled" },
  };
  delete forwardBody.kind;

  const upstreamResp = await fetch(`${deepseekBase}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${deepseekKey}`,
      "Content-Type": "application/json",
      Accept: body.stream === true ? "text/event-stream" : "application/json",
    },
    body: JSON.stringify(forwardBody),
  });

  // Record the call regardless of success — DeepSeek bills us on attempt,
  // not on success only. Best-effort: failure to insert must not block the
  // response.
  admin
    .from("sc_function_calls")
    .insert({ user_id: userId, function_name: functionName })
    .then(
      () => {},
      () => {},
    );

  // 5. Stream-through. For SSE responses we pipe the body straight back to
  //    the iOS client so the existing AsyncThrowingStream<StreamEvent>
  //    parser in AIService.sendAgentMessageStreaming sees the same lines
  //    it would see from a direct call.
  const respHeaders = new Headers({
    "content-type": upstreamResp.headers.get("content-type") ?? "application/json",
  });
  return new Response(upstreamResp.body, {
    status: upstreamResp.status,
    headers: respHeaders,
  });
});

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}
