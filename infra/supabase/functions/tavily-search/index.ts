// Edge Function: tavily-search
//
// Real-time web search for the in-chat "Ask Solo" agent. The iOS app has no
// live search of its own — its `sendWebSearchQuery` only ever asked the model
// what it already knew from training. This function gives the chat agent a real
// web-search tool: it forwards a query to Tavily (the same provider the
// city-brief compiler already uses) and returns normalized results the model
// then summarizes into a sourced answer.
//
// The Tavily key stays server-side (TAVILY_API_KEY), never shipped in the app
// bundle — the app authenticates with its Supabase JWT and this function holds
// the provider secret, mirroring how chat-proxy fronts the LLM key.
//
// Flow:
//   1. Verify Supabase JWT; extract user_id.
//   2. Rate-limit via sc_function_calls (shared daily accounting table).
//   3. Call Tavily /search (advanced depth); normalize to {title,url,content}.
//
// Deliberately NOT Pro-gated: discovery/search should be broadly available;
// the daily rate-limit is the only guard against abuse. Enrichment (the paid AI
// synthesis) remains gated elsewhere.
//
// Deploy: `supabase functions deploy tavily-search`
// Required secret: TAVILY_API_KEY (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY are
// auto-injected by the Edge runtime).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TAVILY_URL = "https://api.tavily.com/search";
const TAVILY_MAX_RESULTS = 6;
const TAVILY_SEARCH_DEPTH = "advanced";
const FUNCTION_NAME = "tavily-search";
// Generous vs. the AI-synthesis quota — search is cheap and the point is that
// the agent can lean on it freely. Still bounded so a runaway loop can't bill.
const DAILY_QUOTA = 100;
// Hard cap on the per-result snippet the model sees, so a chatty page can't
// blow the context budget.
const MAX_CONTENT_CHARS = 1_500;

interface RequestBody {
  query: string;
  // Tavily topic: "general" (default) or "news" for time-sensitive queries.
  topic?: "general" | "news";
  // Only meaningful for topic:"news" — how many days back to search.
  days?: number;
  // Optional caller override, clamped to a sane range.
  maxResults?: number;
}

interface TavilyResult {
  title?: string;
  url?: string;
  content?: string;
}

interface NormalizedResult {
  title: string;
  url: string;
  content: string;
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
  const tavilyKey = Deno.env.get("TAVILY_API_KEY");
  if (!tavilyKey) return json({ error: "server misconfigured" }, 500);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  const { data: userData, error: userErr } = await admin.auth.getUser(jwt);
  if (userErr || !userData.user) return json({ error: "invalid jwt" }, 401);
  const userId = userData.user.id;

  // 2. Rate-limit: today's call count (shared accounting table).
  const dayStart = new Date();
  dayStart.setUTCHours(0, 0, 0, 0);
  const { count } = await admin
    .from("sc_function_calls")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("function_name", FUNCTION_NAME)
    .gte("called_at", dayStart.toISOString());
  if ((count ?? 0) >= DAILY_QUOTA) {
    return json({ error: "daily quota exceeded", quota: DAILY_QUOTA }, 429);
  }

  // 3. Parse.
  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  const query = (body.query ?? "").trim();
  if (!query) return json({ error: "query required" }, 400);

  const topic = body.topic === "news" ? "news" : "general";
  const maxResults = clampInt(body.maxResults ?? TAVILY_MAX_RESULTS, 1, 10);

  // 4. Call Tavily.
  const payload: Record<string, unknown> = {
    query,
    search_depth: TAVILY_SEARCH_DEPTH,
    max_results: maxResults,
    topic,
  };
  if (topic === "news" && typeof body.days === "number") {
    payload.days = clampInt(body.days, 1, 30);
  }

  let res: Response;
  try {
    res = await fetch(TAVILY_URL, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${tavilyKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    return json({ error: "search provider unreachable", detail: String(e) }, 502);
  }
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return json(
      { error: "search provider error", status: res.status, detail: text.slice(0, 500) },
      502,
    );
  }

  const data = (await res.json().catch(() => ({}))) as { results?: TavilyResult[] };

  // 5. Normalize + dedupe by URL.
  const seen = new Set<string>();
  const results: NormalizedResult[] = [];
  for (const r of data.results ?? []) {
    const url = (r.url ?? "").trim();
    if (!url || seen.has(url)) continue;
    seen.add(url);
    results.push({
      title: (r.title ?? "").trim(),
      url,
      content: (r.content ?? "").slice(0, MAX_CONTENT_CHARS),
    });
  }

  // 6. Record the call for rate-limiting (best-effort; a failed insert must not
  //    fail the search the user is waiting on).
  await admin
    .from("sc_function_calls")
    .insert({ user_id: userId, function_name: FUNCTION_NAME })
    .then(undefined, () => {});

  return json({ query, results });
});

function clampInt(n: number, lo: number, hi: number): number {
  const i = Math.floor(Number.isFinite(n) ? n : lo);
  return Math.min(hi, Math.max(lo, i));
}

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}
