// city-brief-core — pure, zero-dependency logic shared between the
// compile-city-brief Edge Function (Deno) and its vitest unit tests (Node).
//
// NOTHING here imports anything: no supabase-js, no Deno globals, no fetch.
// It is the deterministic core — query construction, prompt building, JSON
// parsing, and the quality gates that keep model hallucinations out of the
// city_kits / city_events tables. All network I/O lives in index.ts.
//
// Design mirrors packages/ai/src/prompts/structure-experience.ts:
//   - sourced facts (name/date/place) must come from the snippet;
//   - judgment (solo_score / solo_note) is applied ON TOP of those facts;
//   - omit over invent; {"action":"refuse"} is allowed;
//   - source_url must be EXACTLY one of the candidate URLs we handed the model.

// ─── Shared types ────────────────────────────────────────────────────────────

export type KitSection = "net" | "money" | "visa" | "safety";
export type EventCategory =
  | "culture"
  | "wellness"
  | "market"
  | "music"
  | "sports"
  | "food"
  | "notice";
export type Health = "green" | "yellow" | "red" | "gray";
export type CompileTarget = "kit" | "events";

/** A normalized search result the model reads from. */
export interface Candidate {
  sourceId: string; // e.g. "tavily"
  title: string;
  rawText: string; // ≤ ~1200 chars
  url: string;
  fetchedAt: string; // ISO
}

/** Minimal city context the pure layer needs (no DB row type leaks in). */
export interface CityContext {
  cityCode: string; // lowercase, e.g. "vte"
  nameEn: string;
  nameZh: string;
  timezone: string; // IANA
}

export interface DateWindow {
  now: Date;
  /** Inclusive lower bound for accepting an event's ends_at. */
  earliest: Date;
  /** Inclusive upper bound for accepting an event's ends_at. */
  latest: Date;
}

/** A validated event ready to upsert. */
export interface ValidatedEvent {
  name: string;
  category: EventCategory;
  whenLabel: string;
  startsAt: string | null;
  endsAt: string;
  soloScore: number | null;
  soloNote: string | null;
  seenLabel: string | null;
  sourceUrl: string;
  limitedLabel: string | null;
  health: Health;
}

/** A validated kit section decision. */
export type KitDecision =
  | { section: KitSection; action: "confirm" }
  | {
      section: KitSection;
      action: "update";
      name: string;
      body: string;
      lensLine: string | null;
      linkLabel: string | null;
      sources: unknown[];
      health: Health;
    }
  | { section: KitSection; action: "omit" };

// ─── Constants ───────────────────────────────────────────────────────────────

/** Superlative / hype blacklist — any hit rejects the item. */
const SUPERLATIVE_RE = /必去|绝对|最棒|一生一次|must-see|best ever|once in a lifetime/i;

/**
 * Kit deep-link host allowlist. A kit link_url must resolve to one of these
 * hosts (or be omitted). Keeps the model from linking to arbitrary blogs.
 */
const KIT_LINK_ALLOWLIST = ["airalo.com", "wise.com", "geosureglobal.com"];

const MAX_SOLO_NOTE = 60;
const MAX_WHEN_LABEL = 20;

// ─── Tavily query construction ───────────────────────────────────────────────

export interface TavilyQuery {
  query: string;
  /** Tavily topic; "news" narrows recency for notices. */
  topic?: "general" | "news";
  /** For news topic — how many days back to search. */
  days?: number;
  /** Which kit section this query serves (events queries omit this). */
  section?: KitSection;
}

/**
 * Build the Tavily search queries for a compile run.
 *   - events: 3 queries (general this-week events, venue/market specific,
 *     notices via news topic).
 *   - kit:    4 queries, one per section.
 */
export function tavilyQueries(
  city: CityContext,
  target: CompileTarget,
  dateWindow: DateWindow,
): TavilyQuery[] {
  const cityName = city.nameEn;
  if (target === "events") {
    const monthDay = `${dateWindow.now.getUTCFullYear()}-${pad2(dateWindow.now.getUTCMonth() + 1)}`;
    return [
      {
        query: `${cityName} events festivals things to do this week ${monthDay}`,
        topic: "general",
      },
      {
        query: `${cityName} night market weekend market live music venue this week`,
        topic: "general",
      },
      {
        query: `${cityName} travel notice closure safety advisory`,
        topic: "news",
        days: 10,
      },
    ];
  }

  // kit — one query per section.
  const perSection: Record<KitSection, string> = {
    net: `${cityName} eSIM SIM card mobile data tourist connectivity`,
    money: `${cityName} money exchange ATM fees cash card payment tips traveler`,
    visa: `${cityName} visa on arrival tourist visa requirements days`,
    safety: `${cityName} solo traveler safety emergency police number areas`,
  };
  return (Object.keys(perSection) as KitSection[]).map((section) => ({
    query: perSection[section],
    topic: "general",
    section,
  }));
}

// ─── Prompt construction ─────────────────────────────────────────────────────

function candidateBlock(candidates: Candidate[]): string {
  return candidates
    .map((c, i) => `[${i + 1}] url=${c.url}\ntitle=${c.title}\ntext="""${c.rawText}"""`)
    .join("\n\n");
}

/**
 * Build the events-curation prompt. The model must ground every fact
 * (name/date/place) in a candidate snippet and cite the EXACT candidate URL.
 */
export function buildEventsPrompt(city: CityContext, candidates: Candidate[]): string {
  const urls = candidates.map((c) => c.url);
  return `You are a solo-travel local-events curator for ${city.nameEn} (${city.nameZh}). Curate real, time-bound local events from the search snippets below, for a traveler exploring the city ALONE. Output zh-Hans.

SOURCED FACTS vs JUDGMENT — keep them separate:
  - SOURCED (must come from a snippet, never invented): name, dates, venue/location, whether it is limited-time.
  - JUDGMENT (yours, applied on top of the facts): solo_score, solo_note, category.

STRICT RULES — violating any is a critical failure:
1. source_url MUST be copied EXACTLY from one of the candidate url= lines. If an event's facts are not clearly in a snippet, OMIT it. Do NOT invent a URL.
2. Do NOT use superlatives or hype ("必去", "绝对", "最棒", "must-see"). Describe plainly.
3. solo_score is 0–10 on this rubric: 安全感 / 单人自在 / 氛围 / 无需交谈. A "notice" (closure/advisory) carries solo_score = null.
4. solo_note ≤ ${MAX_SOLO_NOTE} chars; when_label ≤ ${MAX_WHEN_LABEL} chars, human-facing (e.g. "本周五 傍晚").
5. seen_label describes provenance from the snippet's source type + date (e.g. "官方 · 7月"); NEVER fake "已确认".
6. ends_at is an ISO-8601 timestamp when the event is over. If only a date is known, use end-of-day. starts_at may be null.
7. If nothing solid is present, return {"action":"refuse","reason":"…"}.

CANDIDATE URLS (source_url must be one of these exactly):
${urls.map((u) => `  - ${u}`).join("\n")}

OUTPUT FORMAT — a JSON object, no markdown fences:
{
  "events": [
    {
      "name": string,
      "category": "culture"|"wellness"|"market"|"music"|"sports"|"food"|"notice",
      "when_label": string,
      "starts_at": string|null,
      "ends_at": string,
      "solo_score": number|null,
      "solo_note": string|null,
      "seen_label": string|null,
      "limited_label": string|null,
      "source_url": string
    }
  ]
}
Or, if the snippets yield nothing solid: {"action":"refuse","reason": string}

SEARCH SNIPPETS:
${candidateBlock(candidates)}`;
}

/**
 * Build the kit re-verification prompt. This is CONFIRM / UPDATE / OMIT mode:
 * the model re-verifies existing rows against fresh snippets. It NEVER changes
 * link_url — that field is owned by the pipeline, not the model.
 */
export function buildKitPrompt(
  city: CityContext,
  currentRows: Array<{ section: KitSection; name: string; body: string; lensLine: string | null }>,
  candidates: Candidate[],
): string {
  const urls = candidates.map((c) => c.url);
  const current = currentRows
    .map(
      (r) => `- section=${r.section} name="${r.name}" body="${r.body}" lens="${r.lensLine ?? ""}"`,
    )
    .join("\n");
  return `You are re-verifying the landing kit for ${city.nameEn} (${city.nameZh}) against fresh search snippets. Output zh-Hans.

This is CONFIRM / UPDATE / OMIT mode. For each EXISTING section below, decide:
  - "confirm": the snippets still support the current copy → no text change, we just bump freshness.
  - "update": the snippets contradict or improve the copy → return new name/body/lens_line/health.
  - "omit": the snippets are silent or you cannot verify → leave the row untouched.

STRICT RULES:
1. You NEVER change link_url. It is not in your output. Do not invent links.
2. SOURCED facts (prices, day counts, numbers) must come from a snippet. Judgment stays plain.
3. No superlatives/hype ("必去", "绝对", "最棒", "must-see").
4. Every "sources" entry's url must be EXACTLY one of the candidate url= lines below.
5. health ∈ green|yellow|red|gray reflecting how current/reliable the info is.

CANDIDATE URLS (any sources url must be one of these exactly):
${urls.map((u) => `  - ${u}`).join("\n")}

EXISTING SECTIONS:
${current}

OUTPUT FORMAT — a JSON object, no markdown fences:
{
  "decisions": [
    { "section": "net"|"money"|"visa"|"safety", "action": "confirm" },
    { "section": "...", "action": "update", "name": string, "body": string, "lens_line": string|null, "link_label": string|null, "health": "green"|"yellow"|"red"|"gray", "sources": [{"type": string, "url": string, "attribution": string|null}] },
    { "section": "...", "action": "omit" }
  ]
}

SEARCH SNIPPETS:
${candidateBlock(candidates)}`;
}

// ─── JSON parsing ────────────────────────────────────────────────────────────

/**
 * Parse a model reply that should be a JSON object: strip markdown fences, then
 * take the substring from the first "{" to the last "}". Returns null on failure.
 */
export function parseModelJSON(raw: string): Record<string, unknown> | null {
  if (typeof raw !== "string") return null;
  const stripped = raw
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```\s*$/i, "")
    .trim();
  const start = stripped.indexOf("{");
  const end = stripped.lastIndexOf("}");
  if (start === -1 || end === -1 || end < start) return null;
  try {
    const parsed = JSON.parse(stripped.slice(start, end + 1));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

// ─── Deterministic id / slug ─────────────────────────────────────────────────

/**
 * Slugify a name to lowercase ascii-ish tokens joined by underscore, ≤32 chars.
 * Non-ascii (e.g. Chinese) is dropped; if nothing ascii remains, a short stable
 * hash of the original stands in so distinct names never collide to "".
 */
export function slugify(name: string, maxLen = 32): string {
  const ascii = name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "")
    .slice(0, maxLen);
  if (ascii.length > 0) return ascii;
  return `x${stableHash(name).slice(0, 8)}`;
}

/** yyyymmdd from an ISO/date string, in UTC. "00000000" if unparseable. */
function yyyymmdd(dateish: string): string {
  const t = Date.parse(dateish);
  if (Number.isNaN(t)) return "00000000";
  const d = new Date(t);
  return `${d.getUTCFullYear()}${pad2(d.getUTCMonth() + 1)}${pad2(d.getUTCDate())}`;
}

/**
 * Deterministic event id: evt_{city}_{slug≤32}_{yyyymmdd}. The date anchor is
 * the event's start (or end when start is unknown), so the same real event
 * re-curated later collapses onto the same row.
 */
export function eventId(cityCode: string, name: string, dateAnchor: string): string {
  return `evt_${cityCode.toLowerCase()}_${slugify(name)}_${yyyymmdd(dateAnchor)}`;
}

/**
 * Normalize a name for ±2-day dedup: lowercase, collapse whitespace, drop
 * punctuation. Two events with the same normalized name within 2 days are the
 * same event even if their ids differ by a day.
 */
export function normalizeName(name: string): string {
  return name
    .toLowerCase()
    .replace(/[\s　]+/g, "")
    .replace(/[·・.,!?，。！？、「」“”"'()（）\-—]+/g, "");
}

// ─── Validators (quality gates) ──────────────────────────────────────────────

export interface EventValidation {
  accepted: ValidatedEvent[];
  rejected: Array<{ name: string; reason: string }>;
}

/**
 * Validate & filter model-emitted events against the candidate URL whitelist
 * and the quality gates. Also dedups by normalized name within ±2 days,
 * keeping the earliest-seen (highest-priority) instance.
 */
export function validateEvents(
  items: unknown,
  candidateURLs: string[],
  now: Date,
): EventValidation {
  const accepted: ValidatedEvent[] = [];
  const rejected: Array<{ name: string; reason: string }> = [];
  const urlSet = new Set(candidateURLs);

  const earliest = new Date(now.getTime() - 1 * 24 * 60 * 60 * 1000);
  const latest = new Date(now.getTime() + 21 * 24 * 60 * 60 * 1000);

  if (!Array.isArray(items)) return { accepted, rejected };

  // For ±2-day dedup: normalized name → list of accepted end-times.
  const seen: Array<{ norm: string; endMs: number }> = [];
  const TWO_DAYS = 2 * 24 * 60 * 60 * 1000;

  for (const raw of items) {
    if (typeof raw !== "object" || raw === null) {
      rejected.push({ name: "?", reason: "not an object" });
      continue;
    }
    const e = raw as Record<string, unknown>;
    const name = typeof e["name"] === "string" ? (e["name"] as string).trim() : "";
    if (!name) {
      rejected.push({ name: "?", reason: "missing name" });
      continue;
    }

    const category = e["category"];
    const validCats: EventCategory[] = [
      "culture",
      "wellness",
      "market",
      "music",
      "sports",
      "food",
      "notice",
    ];
    if (typeof category !== "string" || !validCats.includes(category as EventCategory)) {
      rejected.push({ name, reason: `invalid category ${String(category)}` });
      continue;
    }

    const sourceUrl = typeof e["source_url"] === "string" ? (e["source_url"] as string) : "";
    if (!urlSet.has(sourceUrl)) {
      rejected.push({ name, reason: "source_url not in candidate whitelist" });
      continue;
    }

    const combinedText = `${name} ${String(e["solo_note"] ?? "")} ${String(e["when_label"] ?? "")}`;
    if (SUPERLATIVE_RE.test(combinedText)) {
      rejected.push({ name, reason: "superlative/hype language" });
      continue;
    }

    const endsAtRaw = typeof e["ends_at"] === "string" ? (e["ends_at"] as string) : "";
    const endMs = Date.parse(endsAtRaw);
    if (Number.isNaN(endMs)) {
      rejected.push({ name, reason: "ends_at unparseable" });
      continue;
    }
    if (endMs < earliest.getTime() || endMs > latest.getTime()) {
      rejected.push({ name, reason: "ends_at outside [now-1d, now+21d]" });
      continue;
    }

    let startsAt: string | null = null;
    if (typeof e["starts_at"] === "string" && (e["starts_at"] as string).trim() !== "") {
      const startMs = Date.parse(e["starts_at"] as string);
      if (Number.isNaN(startMs)) {
        rejected.push({ name, reason: "starts_at unparseable" });
        continue;
      }
      if (endMs < startMs) {
        rejected.push({ name, reason: "ends_at before starts_at" });
        continue;
      }
      startsAt = new Date(startMs).toISOString();
    }

    // solo_score: notices carry null; others clamp to [0,10].
    let soloScore: number | null = null;
    const rawScore = e["solo_score"];
    if (category === "notice") {
      soloScore = null;
    } else if (typeof rawScore === "number" && !Number.isNaN(rawScore)) {
      soloScore = Math.min(10, Math.max(0, rawScore));
    }

    let soloNote = typeof e["solo_note"] === "string" ? (e["solo_note"] as string).trim() : null;
    if (soloNote && soloNote.length > MAX_SOLO_NOTE) {
      soloNote = soloNote.slice(0, MAX_SOLO_NOTE);
    }

    let whenLabel = typeof e["when_label"] === "string" ? (e["when_label"] as string).trim() : "";
    if (!whenLabel) {
      rejected.push({ name, reason: "missing when_label" });
      continue;
    }
    if (whenLabel.length > MAX_WHEN_LABEL) whenLabel = whenLabel.slice(0, MAX_WHEN_LABEL);

    // ±2-day dedup by normalized name.
    const norm = normalizeName(name);
    const dup = seen.find((s) => s.norm === norm && Math.abs(s.endMs - endMs) <= TWO_DAYS);
    if (dup) {
      rejected.push({ name, reason: "duplicate within ±2 days" });
      continue;
    }
    seen.push({ norm, endMs });

    accepted.push({
      name,
      category: category as EventCategory,
      whenLabel,
      startsAt,
      endsAt: new Date(endMs).toISOString(),
      soloScore,
      soloNote,
      seenLabel:
        typeof e["seen_label"] === "string" ? (e["seen_label"] as string).trim() || null : null,
      sourceUrl,
      limitedLabel:
        typeof e["limited_label"] === "string"
          ? (e["limited_label"] as string).trim() || null
          : null,
      health: coerceHealth(e["health"]),
    });
  }

  return { accepted, rejected };
}

export interface KitValidation {
  decisions: KitDecision[];
  rejected: Array<{ section: string; reason: string }>;
}

/**
 * Validate model kit decisions. UPDATE decisions must pass the superlative
 * blacklist and, if they carry sources, every source url must be both a
 * candidate url and on the kit host allowlist. The model never supplies
 * link_url; it is owned by the pipeline.
 */
export function validateKit(items: unknown, candidateURLs: string[]): KitValidation {
  const decisions: KitDecision[] = [];
  const rejected: Array<{ section: string; reason: string }> = [];
  const urlSet = new Set(candidateURLs);
  const validSections: KitSection[] = ["net", "money", "visa", "safety"];

  if (!Array.isArray(items)) return { decisions, rejected };
  const seenSections = new Set<string>();

  for (const raw of items) {
    if (typeof raw !== "object" || raw === null) {
      rejected.push({ section: "?", reason: "not an object" });
      continue;
    }
    const d = raw as Record<string, unknown>;
    const section = d["section"];
    if (typeof section !== "string" || !validSections.includes(section as KitSection)) {
      rejected.push({ section: String(section), reason: "invalid section" });
      continue;
    }
    if (seenSections.has(section)) {
      rejected.push({ section, reason: "duplicate section" });
      continue;
    }
    seenSections.add(section);

    const action = d["action"];
    if (action === "confirm") {
      decisions.push({ section: section as KitSection, action: "confirm" });
      continue;
    }
    if (action === "omit") {
      decisions.push({ section: section as KitSection, action: "omit" });
      continue;
    }
    if (action !== "update") {
      rejected.push({ section, reason: `invalid action ${String(action)}` });
      continue;
    }

    const name = typeof d["name"] === "string" ? (d["name"] as string).trim() : "";
    const body = typeof d["body"] === "string" ? (d["body"] as string).trim() : "";
    if (!name || !body) {
      rejected.push({ section, reason: "update missing name/body" });
      continue;
    }
    if (SUPERLATIVE_RE.test(`${name} ${body} ${String(d["lens_line"] ?? "")}`)) {
      rejected.push({ section, reason: "superlative/hype language" });
      continue;
    }

    // Sources: every url must be in the candidate whitelist AND host-allowlisted.
    const rawSources = Array.isArray(d["sources"]) ? (d["sources"] as unknown[]) : [];
    let badSource = false;
    for (const s of rawSources) {
      if (typeof s !== "object" || s === null) continue;
      const url = (s as Record<string, unknown>)["url"];
      if (typeof url === "string" && url.trim() !== "") {
        if (!urlSet.has(url) || !isAllowlistedKitHost(url)) {
          badSource = true;
          break;
        }
      }
    }
    if (badSource) {
      rejected.push({ section, reason: "source url not whitelisted/allowlisted" });
      continue;
    }

    decisions.push({
      section: section as KitSection,
      action: "update",
      name,
      body,
      lensLine:
        typeof d["lens_line"] === "string" ? (d["lens_line"] as string).trim() || null : null,
      linkLabel:
        typeof d["link_label"] === "string" ? (d["link_label"] as string).trim() || null : null,
      sources: rawSources,
      health: coerceHealth(d["health"]),
    });
  }

  return { decisions, rejected };
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function pad2(n: number): string {
  return n < 10 ? `0${n}` : String(n);
}

function coerceHealth(v: unknown): Health {
  return v === "green" || v === "yellow" || v === "red" || v === "gray" ? v : "gray";
}

/**
 * True when the URL's host is on the kit allowlist:
 * airalo.com / wise.com / geosureglobal.com, or any *.gov / *.la host.
 */
export function isAllowlistedKitHost(url: string): boolean {
  const host = hostOf(url);
  if (host === null) return false;
  if (KIT_LINK_ALLOWLIST.some((h) => host === h || host.endsWith(`.${h}`))) return true;
  // *.gov (incl. gov.la etc.) and *.la country hosts.
  const parts = host.split(".");
  const tld = parts[parts.length - 1] ?? "";
  if (tld === "la") return true;
  if (parts.includes("gov")) return true;
  return false;
}

/** Extract a lowercase host from a URL without the URL global (Deno/Node safe). */
function hostOf(url: string): string | null {
  const m = /^[a-z][a-z0-9+.-]*:\/\/([^/?#]+)/i.exec(url.trim());
  if (!m || m[1] === undefined) return null;
  let host = m[1].toLowerCase();
  // strip userinfo and port
  const at = host.lastIndexOf("@");
  if (at !== -1) host = host.slice(at + 1);
  const colon = host.indexOf(":");
  if (colon !== -1) host = host.slice(0, colon);
  return host || null;
}

/** Small deterministic 32-bit FNV-1a hash, hex. Used only for slug fallback. */
function stableHash(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(16).padStart(8, "0");
}
