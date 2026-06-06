// Edge Function: enrich-user-experience
// Phase 2 (UGC) — AI-completes a user-created place.
//
// The user supplies only mechanical facts (name, category, coords, a free-form
// description). This function fills the trust-critical fields the user must NOT
// self-report — Solo Score, its breakdown, bestTimes, realInconveniences — and
// rewrites the description into a `whyItMatters` paragraph while preserving the
// user's intent. The result upgrades the row in `user_experiences`; promotion
// to the public `experiences` pool remains a separate curator/service step.
//
// Differs from `synthesize-experiences` (which batches anonymous OSM POIs):
// here the input is ONE place the user already characterized, so the prompt
// must respect their words rather than invent an entry from raw tags.
//
// Flow:
//   1. Verify Supabase JWT; extract user_id.
//   2. Entitlement check (Pro only, matching synthesize-experiences).
//   3. Rate-limit via sc_function_calls (shared daily quota).
//   4. Confirm the row belongs to the caller (RLS-safe ownership check).
//   5. Call Anthropic; validate; merge AI fields into the row payload.
//
// Deploy: `supabase functions deploy enrich-user-experience`
// Required secrets: DEEPSEEK_API_KEY (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY
// are auto-injected by the Edge runtime).
//
// Uses DeepSeek (OpenAI-compatible chat/completions) to match the rest of the
// app's AI stack (AIService / synthesize pipeline use DEEPSEEK_*).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const DEEPSEEK_URL = "https://api.deepseek.com/v1/chat/completions";
const MODEL = "deepseek-chat";
const DAILY_QUOTA_PRO = 30;
const FUNCTION_NAME = "enrich-user-experience";

interface RequestBody {
  experienceId: string; // exp_user_<uuid>, must already exist in user_experiences
  title: string;
  oneLiner: string;
  description: string;
  category: string;
  coordinates: [number, number]; // [lon, lat]
  cityCode: string;
  locale: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  // 1. Auth.
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer /i, "");
  if (!jwt) return json({ error: "missing bearer token" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const deepseekKey = Deno.env.get("DEEPSEEK_API_KEY");
  if (!deepseekKey) return json({ error: "server misconfigured" }, 500);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData.user) return json({ error: "invalid jwt" }, 401);
  const userId = userData.user.id;

  // 2. Entitlement check.
  const { data: profile } = await admin
    .from("profiles")
    .select("entitlement_tier")
    .eq("user_id", userId)
    .maybeSingle();
  const tier = profile?.entitlement_tier ?? "free";
  if (tier === "free" || tier === "pro_expired") {
    return json({ error: "subscription required" }, 402);
  }

  // 3. Rate-limit: today's call count (shared accounting table).
  const dayStart = new Date();
  dayStart.setUTCHours(0, 0, 0, 0);
  const { count } = await admin
    .from("sc_function_calls")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("function_name", FUNCTION_NAME)
    .gte("called_at", dayStart.toISOString());
  if ((count ?? 0) >= DAILY_QUOTA_PRO) {
    return json({ error: "daily quota exceeded", quota: DAILY_QUOTA_PRO }, 429);
  }

  // 4. Parse + ownership check.
  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  if (!body.experienceId || !body.title || !body.category) {
    return json({ error: "experienceId + title + category required" }, 400);
  }

  const { data: row } = await admin
    .from("user_experiences")
    .select("id")
    .eq("user_id", userId)
    .eq("experience_id", body.experienceId)
    .maybeSingle();
  if (!row) {
    return json({ error: "experience not found for this user" }, 404);
  }

  // 5. Call DeepSeek (OpenAI-compatible chat/completions).
  const prompt = buildPrompt(body);
  const aiReq = await fetch(DEEPSEEK_URL, {
    method: "POST",
    headers: {
      authorization: `Bearer ${deepseekKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1024,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!aiReq.ok) {
    const text = await aiReq.text();
    return json({ error: `deepseek error ${aiReq.status}: ${text}` }, 502);
  }
  const aiJson = await aiReq.json();
  const text: string = aiJson?.choices?.[0]?.message?.content ?? "";

  // Validate the single-object response.
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start === -1 || end === -1) {
    return json({ error: "anthropic returned no JSON object" }, 502);
  }
  let enriched: Record<string, unknown>;
  try {
    enriched = JSON.parse(text.substring(start, end + 1));
  } catch {
    return json({ error: "anthropic returned invalid JSON" }, 502);
  }
  if (typeof enriched.whyItMatters !== "string" || typeof enriched.soloOverall !== "number") {
    return json({ error: "anthropic response missing required fields" }, 502);
  }

  // Persist the AI completion back onto the row. We do NOT promote status here
  // (stays 'candidate'); a curator/service step handles candidate → active.
  await admin
    .from("user_experiences")
    .update({
      description: enriched.whyItMatters,
    })
    .eq("user_id", userId)
    .eq("experience_id", body.experienceId);

  await admin.from("sc_function_calls").insert({
    user_id: userId,
    function_name: FUNCTION_NAME,
  });

  return json({ enriched, cached: false });
});

function buildPrompt(body: RequestBody): string {
  return `A solo traveler added a place to the map and wants it fleshed out.

RESPECT THE USER'S INTENT: their title and description below are ground truth for what THIS place is. Do not contradict them or invent a different place. You may enrich tone and detail, but the subject stays theirs.

DO NOT fabricate hard facts (exact hours, prices, menu items, phone numbers). Speak to atmosphere and the solo experience, which is what you're being asked to assess.

User input:
- title: "${body.title}"
- oneLiner: "${body.oneLiner}"
- description: "${body.description}"
- category: ${body.category}
- coordinates(lon,lat): ${body.coordinates[0]}, ${body.coordinates[1]}
- cityCode: ${body.cityCode}

Return a single JSON object (no prose, no markdown fences) with:
  whyItMatters(string, 2-3 sentences, atmosphere + the feel of being there alone),
  soloOverall(number 4.0-9.0; be conservative — this is unverified user input),
  soloHint(string, one practical tip for visiting alone),
  bestStartHour(int 0-23), bestEndHour(int 0-23),
  durationMinMinutes(int), durationMaxMinutes(int),
  realInconveniences(array of { category: "scam"|"crowds"|"logistics"|"weather"|"etiquette"|"safety"|"other", text: string }).

Output language: ${body.locale}.`;
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}
