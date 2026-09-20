// Edge Function: synthesize-experiences
// Epic E US-030 — server-side AI synthesis so the iOS bundle never
// contains a DeepSeek API key.
//
// Flow:
//   1. Verify Supabase JWT from Authorization header.
//   2. Look up profiles.entitlement_tier; free tier rejected with 402.
//   3. Rate-limit: count today's calls in sc_function_calls; cap at 30.
//   4. Read SHA256 cache key from body; if synthesized_experiences row
//      exists, return it without calling DeepSeek.
//   5. Call DeepSeek (OpenAI-compatible chat/completions, thinking disabled)
//      with the prompt + POI batch.
//   6. Validate response shape, write to synthesized_experiences,
//      return to client.
//
// Deploy: `supabase functions deploy synthesize-experiences`
// Required secrets: DEEPSEEK_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
// Optional: DEEPSEEK_BASE_URL (defaults to https://api.deepseek.com/v1),
//           DEEPSEEK_MODEL (defaults to deepseek-flash).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  buildDeepSeekChatBody,
  deepSeekBaseUrl,
  normalizeDeepSeekModel,
  parseDeepSeekContent,
  parseJsonArrayFromText,
} from "../_shared/deepseek.ts";

const DAILY_QUOTA_PRO = 30;
const MAX_POIS_PER_CALL = 60; // US-MR-03: raised from 15 to accommodate the full 4-ring merge

interface POI {
  osmId: number;
  name: string;
  nameEn?: string | null;
  lat: number;
  lon: number;
  tags: Record<string, string>;
}

interface RequestBody {
  pois: POI[];
  cityCode: string;
  locale: string;
  cacheKey: string;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  // 1. Auth: extract user_id from JWT in Authorization header.
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

  // Verify JWT and extract user_id.
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

  // 3. Rate-limit: today's call count.
  const dayStart = new Date();
  dayStart.setUTCHours(0, 0, 0, 0);
  const { count } = await admin
    .from("sc_function_calls")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("function_name", "synthesize-experiences")
    .gte("called_at", dayStart.toISOString());
  if ((count ?? 0) >= DAILY_QUOTA_PRO) {
    return json({ error: "daily quota exceeded", quota: DAILY_QUOTA_PRO }, 429);
  }

  // 4. Parse + cache check.
  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  if (!body.cacheKey || !Array.isArray(body.pois) || body.pois.length === 0) {
    return json({ error: "cacheKey + non-empty pois required" }, 400);
  }
  if (body.pois.length > MAX_POIS_PER_CALL) {
    return json({ error: `max ${MAX_POIS_PER_CALL} POIs per call` }, 400);
  }

  // Resolve the target model BEFORE the cache lookup: a cached payload is
  // only reusable for the same model, so a legacy Claude/deepseek-chat entry
  // can never be served for a deepseek-flash request.
  const model = normalizeDeepSeekModel(Deno.env.get("DEEPSEEK_MODEL"));

  const { data: cached } = await admin
    .from("synthesized_experiences")
    .select("payload")
    .eq("source_cache_key", body.cacheKey)
    .eq("model_name", model)
    .limit(1)
    .maybeSingle();
  if (cached?.payload) {
    return json({ experiences: cached.payload, cached: true });
  }

  // 5. Call DeepSeek (OpenAI-compatible chat/completions, thinking disabled).
  const prompt = buildPrompt(body);
  const deepseekReq = await fetch(
    `${deepSeekBaseUrl(Deno.env.get("DEEPSEEK_BASE_URL"))}/chat/completions`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${deepseekKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(
        buildDeepSeekChatBody({
          model,
          max_tokens: 2048,
          messages: [{ role: "user", content: prompt }],
        }),
      ),
    },
  );
  if (!deepseekReq.ok) {
    const text = await deepseekReq.text();
    return json({ error: `deepseek error ${deepseekReq.status}: ${text}` }, 502);
  }
  const deepseekJson = await deepseekReq.json();
  const text = parseDeepSeekContent(deepseekJson);

  // 6. Validate response shape. Reject empty arrays and null / non-object
  //    items with a controlled 502 BEFORE any cache write, so a bad upstream
  //    payload never poisons the cache or crashes on items[0]/item.osmId.
  const items = parseJsonArrayFromText(text);
  if (!items) {
    return json({ error: "deepseek returned no JSON array" }, 502);
  }
  if (items.length === 0) {
    return json({ error: "deepseek returned an empty array" }, 502);
  }
  for (const item of items) {
    if (item === null || typeof item !== "object" || Array.isArray(item)) {
      return json({ error: "deepseek item is not an object" }, 502);
    }
    const fields = item as Record<string, unknown>;
    if (
      typeof fields.osmId !== "number" ||
      typeof fields.title !== "string" ||
      typeof fields.oneLiner !== "string" ||
      typeof fields.whyItMatters !== "string" ||
      typeof fields.category !== "string"
    ) {
      return json({ error: "deepseek item missing required fields" }, 502);
    }
  }

  // Write to cache and accounting tables.
  await admin.from("synthesized_experiences").upsert({
    id: `exp_osm_${(items[0] as Record<string, unknown>).osmId}`,
    city_code: body.cityCode,
    payload: items,
    model_name: model,
    source_cache_key: body.cacheKey,
  });
  await admin.from("sc_function_calls").insert({
    user_id: userId,
    function_name: "synthesize-experiences",
  });

  return json({ experiences: items, cached: false });
});

function buildPrompt(body: RequestBody): string {
  const lines = body.pois
    .map(
      (p) =>
        `- osmId=${p.osmId} name="${p.name}" nameEn="${p.nameEn ?? p.name}" lat=${p.lat} lon=${p.lon} tags=${JSON.stringify(p.tags)}`,
    )
    .join("\n");
  return `You are writing solo-traveler-focused entries for real OpenStreetMap places.

CRITICAL: Use ONLY the provided OSM tags. Do NOT invent menu items, hours, prices, owner backstories, or seating positions.

DISTANCE AWARENESS: POIs span 0–12 km from the query center (a Pro radial Explore covers 4 rings: 1.5/3/6/12 km). Infer approximate distance from each POI's lat/lon relative to the others; group your output by approximate distance band — near (<2 km), mid (2–6 km), far (6–12 km). Within each band, preserve input order. Do NOT mention distances, rings, or band names explicitly in the output — just let the framing reflect the proximity (walk-up vs half-day-out).

For each POI, return a JSON object with: osmId(int), title, oneLiner, whyItMatters, category(food|coffee|culture|nature|work|wellness|nightlife|hidden), bestStartHour(0-23), bestEndHour(0-23), durationMinMinutes(int), durationMaxMinutes(int), howTo(string[] navigation only), soloHint, soloOverall(6.0-9.5).

Output a JSON array, one object per POI. No prose, no markdown fences.

Output language: ${body.locale}.
City code: ${body.cityCode}.

POIs:
${lines}`;
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}
