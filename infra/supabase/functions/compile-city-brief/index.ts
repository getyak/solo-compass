// Edge Function: compile-city-brief
// Solo City OS v2 — server-side curation of the landing kit (落地包) and the
// live/在地 events for a city. NOT user-triggered: content is city-level and
// shared, so a user "refresh" is just a re-read of the tables. This function is
// invoked by GitHub Actions cron (x-cron-secret) or with the service-role key.
//
// Flow:
//   1. Auth: Authorization Bearer == SUPABASE_SERVICE_ROLE_KEY, OR
//      x-cron-secret == CITY_BRIEF_CRON_SECRET. Else 401.
//   2. Validate {city_code, target, force?}; city must exist + brief_enabled.
//   3. Cooldown via city_brief_runs (events 72h / kit 240h) unless force.
//   4. Tavily search (advanced, max_results 6) → normalize to Candidates,
//      dedup by URL, cap 18 / ~15k chars.
//   5. DeepSeek (json_object, retry once) → parse → quality gates in _shared.
//   6. Upsert: kit confirm→bump last_verified_at+green; omit→untouched; then
//      downgrade rows older than 45d to yellow. events upsert by deterministic
//      id + normalized-name ±2d dedup; never delete (expiry is by status).
//   7. Write a city_brief_runs row with usage numbers + status ok|partial|failed.
//
// Deploy: `supabase functions deploy compile-city-brief`
// Secrets: TAVILY_API_KEY, DEEPSEEK_API_KEY, CITY_BRIEF_CRON_SECRET,
//          (optional DEEPSEEK_BASE_URL, DEEPSEEK_MODEL). SUPABASE_URL /
//          SUPABASE_SERVICE_ROLE_KEY are provided by the runtime.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  tavilyQueries,
  buildEventsPrompt,
  buildKitPrompt,
  parseModelJSON,
  validateEvents,
  validateKit,
  eventId,
  normalizeName,
  type Candidate,
  type CityContext,
  type CompileTarget,
  type KitSection,
} from "../_shared/city-brief-core.ts";

// ─── Budget constants ────────────────────────────────────────────────────────

const TAVILY_URL = "https://api.tavily.com/search";
const TAVILY_MAX_RESULTS = 6;
const TAVILY_SEARCH_DEPTH = "advanced";
const MAX_CANDIDATES = 18;
const MAX_CANDIDATE_CHARS = 15_000;
const MAX_RAWTEXT_CHARS = 1_200;
const DEEPSEEK_MAX_TOKENS = 3_000;
const COOLDOWN_EVENTS_MS = 72 * 60 * 60 * 1000; // 72h
const COOLDOWN_KIT_MS = 240 * 60 * 60 * 1000; // 240h (10 days)
const KIT_STALE_YELLOW_MS = 45 * 24 * 60 * 60 * 1000; // 45 days

// ─── Types ───────────────────────────────────────────────────────────────────

interface RequestBody {
  city_code: string;
  target: CompileTarget | "both";
  force?: boolean;
}

interface CityRow {
  city_code: string;
  name_en: string;
  name_zh: string;
  name_local: string;
  timezone: string;
  brief_enabled: boolean;
}

interface RunOutcome {
  target: CompileTarget;
  status: "ok" | "partial" | "failed";
  searchCalls: number;
  promptTokens: number;
  outputTokens: number;
  itemsWritten: number;
  error?: string;
}

// ─── Entry ───────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const cronSecret = Deno.env.get("CITY_BRIEF_CRON_SECRET");
  const tavilyKey = Deno.env.get("TAVILY_API_KEY");
  const deepseekKey = Deno.env.get("DEEPSEEK_API_KEY");

  // 1. Auth — service-role bearer OR cron secret header.
  const authHeader = req.headers.get("Authorization") ?? "";
  const bearer = authHeader.replace(/^Bearer /i, "");
  const headerCronSecret = req.headers.get("x-cron-secret") ?? "";
  const authOk =
    (bearer.length > 0 && bearer === serviceKey) ||
    (cronSecret != null && cronSecret.length > 0 && headerCronSecret === cronSecret);
  if (!authOk) return json({ error: "unauthorized" }, 401);

  if (!tavilyKey || !deepseekKey) return json({ error: "server misconfigured" }, 500);

  // 2. Parse + validate input.
  let body: RequestBody;
  try {
    body = (await req.json()) as RequestBody;
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  const cityCode = (body.city_code ?? "").toLowerCase().trim();
  if (!cityCode) return json({ error: "city_code required" }, 400);
  const target = body.target;
  if (target !== "kit" && target !== "events" && target !== "both") {
    return json({ error: "target must be kit|events|both" }, 400);
  }
  const force = body.force === true;

  const admin = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false } });

  // City must exist and be brief-enabled.
  const { data: cityRow } = await admin
    .from("sc_cities")
    .select("city_code, name_en, name_zh, name_local, timezone, brief_enabled")
    .eq("city_code", cityCode)
    .maybeSingle();
  const city = cityRow as CityRow | null;
  if (!city) return json({ error: "city not found" }, 404);
  if (!city.brief_enabled) return json({ error: "brief not enabled for city" }, 409);

  const cityCtx: CityContext = {
    cityCode: city.city_code,
    nameEn: city.name_en,
    nameZh: city.name_zh,
    timezone: city.timezone,
  };

  const targets: CompileTarget[] = target === "both" ? ["events", "kit"] : [target];
  const outcomes: RunOutcome[] = [];

  for (const t of targets) {
    // 3. Cooldown check (unless forced).
    if (!force) {
      const cooled = await withinCooldown(admin, cityCode, t);
      if (cooled) {
        outcomes.push({
          target: t,
          status: "ok",
          searchCalls: 0,
          promptTokens: 0,
          outputTokens: 0,
          itemsWritten: 0,
          error: "cooldown",
        });
        continue;
      }
    }

    const startedAt = new Date().toISOString();
    let outcome: RunOutcome;
    try {
      outcome =
        t === "events"
          ? await compileEvents(admin, cityCtx, tavilyKey, deepseekKey)
          : await compileKit(admin, cityCtx, tavilyKey, deepseekKey);
    } catch (err) {
      outcome = {
        target: t,
        status: "failed",
        searchCalls: 0,
        promptTokens: 0,
        outputTokens: 0,
        itemsWritten: 0,
        error: (err as Error).message,
      };
    }
    await writeRun(admin, cityCode, outcome, startedAt);
    outcomes.push(outcome);
  }

  return json({ city_code: cityCode, outcomes });
});

// ─── Cooldown ────────────────────────────────────────────────────────────────

async function withinCooldown(
  admin: SupabaseAdmin,
  cityCode: string,
  target: CompileTarget,
): Promise<boolean> {
  const { data } = await admin
    .from("city_brief_runs")
    .select("started_at, status")
    .eq("city_code", cityCode)
    .eq("target", target)
    .in("status", ["ok", "partial"])
    .order("started_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!data?.started_at) return false;
  const last = Date.parse(data.started_at as string);
  if (Number.isNaN(last)) return false;
  const cooldownMs = target === "events" ? COOLDOWN_EVENTS_MS : COOLDOWN_KIT_MS;
  return Date.now() - last < cooldownMs;
}

// ─── Tavily ──────────────────────────────────────────────────────────────────

interface TavilyResult {
  title?: string;
  url?: string;
  content?: string;
}

async function runTavily(
  tavilyKey: string,
  queries: ReturnType<typeof tavilyQueries>,
): Promise<{ candidates: Candidate[]; calls: number }> {
  const now = new Date().toISOString();
  const byUrl = new Map<string, Candidate>();
  let calls = 0;
  let totalChars = 0;

  for (const q of queries) {
    if (byUrl.size >= MAX_CANDIDATES || totalChars >= MAX_CANDIDATE_CHARS) break;
    const payload: Record<string, unknown> = {
      query: q.query,
      search_depth: TAVILY_SEARCH_DEPTH,
      max_results: TAVILY_MAX_RESULTS,
      topic: q.topic ?? "general",
    };
    if (q.topic === "news" && q.days) payload.days = q.days;

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
    } catch {
      continue; // skip a failed query; others may still yield candidates
    }
    calls++;
    if (!res.ok) continue;
    const data = (await res.json()) as { results?: TavilyResult[] };
    for (const r of data.results ?? []) {
      const url = (r.url ?? "").trim();
      if (!url || byUrl.has(url)) continue;
      if (byUrl.size >= MAX_CANDIDATES || totalChars >= MAX_CANDIDATE_CHARS) break;
      const rawText = (r.content ?? "").slice(0, MAX_RAWTEXT_CHARS);
      totalChars += rawText.length;
      byUrl.set(url, {
        sourceId: "tavily",
        title: r.title ?? "",
        rawText,
        url,
        fetchedAt: now,
      });
    }
  }

  return { candidates: [...byUrl.values()], calls };
}

// ─── DeepSeek ────────────────────────────────────────────────────────────────

interface DeepSeekUsage {
  prompt_tokens: number;
  completion_tokens: number;
}

async function callDeepSeek(
  deepseekKey: string,
  prompt: string,
): Promise<{ content: string; usage: DeepSeekUsage }> {
  const base = Deno.env.get("DEEPSEEK_BASE_URL") ?? "https://api.deepseek.com/v1";
  const model = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-chat";
  const res = await fetch(`${base}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${deepseekKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: DEEPSEEK_MAX_TOKENS,
      response_format: { type: "json_object" },
      messages: [{ role: "user", content: prompt }],
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`deepseek ${res.status}: ${text.slice(0, 200)}`);
  }
  const jsonRes = (await res.json()) as {
    choices?: Array<{ message?: { content?: string } }>;
    usage?: DeepSeekUsage;
  };
  const content = jsonRes.choices?.[0]?.message?.content ?? "";
  const usage = jsonRes.usage ?? { prompt_tokens: 0, completion_tokens: 0 };
  return { content, usage };
}

/** Call DeepSeek, parse JSON, retry once on unparseable output. */
async function deepSeekJSON(
  deepseekKey: string,
  prompt: string,
): Promise<{ parsed: Record<string, unknown> | null; usage: DeepSeekUsage }> {
  const first = await callDeepSeek(deepseekKey, prompt);
  let parsed = parseModelJSON(first.content);
  let usage = first.usage;
  if (parsed === null) {
    const retry = await callDeepSeek(
      deepseekKey,
      `${prompt}\n\nYour previous reply was not valid JSON. Reply with ONLY the JSON object.`,
    );
    parsed = parseModelJSON(retry.content);
    usage = {
      prompt_tokens: usage.prompt_tokens + retry.usage.prompt_tokens,
      completion_tokens: usage.completion_tokens + retry.usage.completion_tokens,
    };
  }
  return { parsed, usage };
}

// ─── Events compile ──────────────────────────────────────────────────────────

const DAY_MS = 24 * 60 * 60 * 1000;

async function compileEvents(
  admin: SupabaseAdmin,
  city: CityContext,
  tavilyKey: string,
  deepseekKey: string,
): Promise<RunOutcome> {
  const now = new Date();
  const queries = tavilyQueries(city, "events", {
    now,
    earliest: new Date(now.getTime() - DAY_MS),
    latest: new Date(now.getTime() + 21 * DAY_MS),
  });
  const { candidates, calls } = await runTavily(tavilyKey, queries);
  if (candidates.length === 0) {
    return {
      target: "events",
      status: "failed",
      searchCalls: calls,
      promptTokens: 0,
      outputTokens: 0,
      itemsWritten: 0,
      error: "no search candidates",
    };
  }

  const prompt = buildEventsPrompt(city, candidates);
  const { parsed, usage } = await deepSeekJSON(deepseekKey, prompt);
  if (parsed === null) {
    return {
      target: "events",
      status: "failed",
      searchCalls: calls,
      promptTokens: usage.prompt_tokens,
      outputTokens: usage.completion_tokens,
      itemsWritten: 0,
      error: "model returned invalid JSON",
    };
  }
  if (parsed["action"] === "refuse") {
    return {
      target: "events",
      status: "ok",
      searchCalls: calls,
      promptTokens: usage.prompt_tokens,
      outputTokens: usage.completion_tokens,
      itemsWritten: 0,
      error: "model refused",
    };
  }

  const candidateURLs = candidates.map((c) => c.url);
  const { accepted, rejected } = validateEvents(parsed["events"], candidateURLs, now);

  // Fetch existing active events for this city for ±2-day normalized-name dedup.
  const { data: existingRows } = await admin
    .from("city_events")
    .select("id, name, ends_at")
    .eq("city_code", city.cityCode)
    .eq("status", "active");
  const existing = (existingRows ?? []) as Array<{ id: string; name: string; ends_at: string }>;

  const model = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-chat";
  const nowIso = now.toISOString();
  let written = 0;

  for (const ev of accepted) {
    const anchor = ev.startsAt ?? ev.endsAt;
    let id = eventId(city.cityCode, ev.name, anchor);

    // Secondary dedup: an existing active row with the same normalized name
    // within ±2 days is the SAME event → update it in place rather than insert.
    const norm = normalizeName(ev.name);
    const endMs = Date.parse(ev.endsAt);
    const twin = existing.find(
      (r) =>
        normalizeName(r.name) === norm &&
        Math.abs(Date.parse(r.ends_at) - endMs) <= 2 * DAY_MS,
    );
    if (twin) id = twin.id;

    const { error } = await admin.from("city_events").upsert(
      {
        id,
        city_code: city.cityCode,
        name: ev.name,
        category: ev.category,
        when_label: ev.whenLabel,
        starts_at: ev.startsAt,
        ends_at: ev.endsAt,
        solo_score: ev.soloScore,
        solo_note: ev.soloNote,
        health: ev.health,
        seen_label: ev.seenLabel,
        limited_label: ev.limitedLabel,
        source_url: ev.sourceUrl,
        verified_at: nowIso,
        model_name: model,
        status: "active",
      },
      { onConflict: "id" },
    );
    if (!error) written++;
  }

  const status: RunOutcome["status"] =
    written === 0 && accepted.length === 0 && rejected.length > 0 ? "partial" : "ok";

  return {
    target: "events",
    status,
    searchCalls: calls,
    promptTokens: usage.prompt_tokens,
    outputTokens: usage.completion_tokens,
    itemsWritten: written,
  };
}

// ─── Kit compile (re-verify) ─────────────────────────────────────────────────

async function compileKit(
  admin: SupabaseAdmin,
  city: CityContext,
  tavilyKey: string,
  deepseekKey: string,
): Promise<RunOutcome> {
  const now = new Date();

  // Existing kit rows are what we re-verify. If none exist, there is nothing to
  // confirm/update — kit content is seeded first, then re-verified here.
  const { data: kitRows } = await admin
    .from("city_kits")
    .select("section, name, body, lens_line, last_verified_at")
    .eq("city_code", city.cityCode);
  const current = (kitRows ?? []) as Array<{
    section: KitSection;
    name: string;
    body: string;
    lens_line: string | null;
    last_verified_at: string | null;
  }>;

  if (current.length === 0) {
    return {
      target: "kit",
      status: "ok",
      searchCalls: 0,
      promptTokens: 0,
      outputTokens: 0,
      itemsWritten: 0,
      error: "no kit rows to verify (seed first)",
    };
  }

  const queries = tavilyQueries(city, "kit", {
    now,
    earliest: new Date(now.getTime() - DAY_MS),
    latest: new Date(now.getTime() + 21 * DAY_MS),
  });
  const { candidates, calls } = await runTavily(tavilyKey, queries);
  if (candidates.length === 0) {
    // Still run the 45-day downgrade sweep even without fresh candidates.
    await downgradeStaleKit(admin, city.cityCode, now);
    return {
      target: "kit",
      status: "partial",
      searchCalls: calls,
      promptTokens: 0,
      outputTokens: 0,
      itemsWritten: 0,
      error: "no search candidates",
    };
  }

  const prompt = buildKitPrompt(
    city,
    current.map((r) => ({
      section: r.section,
      name: r.name,
      body: r.body,
      lensLine: r.lens_line,
    })),
    candidates,
  );
  const { parsed, usage } = await deepSeekJSON(deepseekKey, prompt);
  if (parsed === null) {
    return {
      target: "kit",
      status: "failed",
      searchCalls: calls,
      promptTokens: usage.prompt_tokens,
      outputTokens: usage.completion_tokens,
      itemsWritten: 0,
      error: "model returned invalid JSON",
    };
  }

  const candidateURLs = candidates.map((c) => c.url);
  const { decisions } = validateKit(parsed["decisions"], candidateURLs);
  const model = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-chat";
  const nowIso = now.toISOString();
  let written = 0;

  for (const d of decisions) {
    if (d.action === "omit") continue; // leave the row untouched

    if (d.action === "confirm") {
      // Bump freshness + health green; never touch link_url / body.
      const { error } = await admin
        .from("city_kits")
        .update({ last_verified_at: nowIso, health: "green", model_name: model })
        .eq("city_code", city.cityCode)
        .eq("section", d.section);
      if (!error) written++;
      continue;
    }

    // update — refresh copy; link_url is intentionally NOT set here.
    const patch: Record<string, unknown> = {
      name: d.name,
      body: d.body,
      lens_line: d.lensLine,
      health: d.health,
      last_verified_at: nowIso,
      model_name: model,
    };
    if (d.linkLabel != null) patch.link_label = d.linkLabel;
    if (Array.isArray(d.sources) && d.sources.length > 0) patch.sources = d.sources;
    const { error } = await admin
      .from("city_kits")
      .update(patch)
      .eq("city_code", city.cityCode)
      .eq("section", d.section);
    if (!error) written++;
  }

  // Downgrade any kit row not re-verified in 45 days to yellow.
  await downgradeStaleKit(admin, city.cityCode, now);

  return {
    target: "kit",
    status: "ok",
    searchCalls: calls,
    promptTokens: usage.prompt_tokens,
    outputTokens: usage.completion_tokens,
    itemsWritten: written,
  };
}

async function downgradeStaleKit(admin: SupabaseAdmin, cityCode: string, now: Date): Promise<void> {
  const cutoff = new Date(now.getTime() - KIT_STALE_YELLOW_MS).toISOString();
  await admin
    .from("city_kits")
    .update({ health: "yellow" })
    .eq("city_code", cityCode)
    .in("health", ["green"])
    .lt("last_verified_at", cutoff);
}

// ─── Run accounting ──────────────────────────────────────────────────────────

async function writeRun(
  admin: SupabaseAdmin,
  cityCode: string,
  outcome: RunOutcome,
  startedAt: string,
): Promise<void> {
  await admin.from("city_brief_runs").insert({
    city_code: cityCode,
    target: outcome.target,
    status: outcome.status,
    search_calls: outcome.searchCalls,
    prompt_tokens: outcome.promptTokens,
    output_tokens: outcome.outputTokens,
    items_written: outcome.itemsWritten,
    error: outcome.error ?? null,
    started_at: startedAt,
    finished_at: new Date().toISOString(),
  });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

// Loose alias so we don't depend on supabase-js generic types in Deno.
type SupabaseAdmin = ReturnType<typeof createClient>;

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}
