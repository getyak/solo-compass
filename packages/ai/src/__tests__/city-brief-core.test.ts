import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, it, expect } from "vitest";
import {
  tavilyQueries,
  buildEventsPrompt,
  buildKitPrompt,
  parseModelJSON,
  validateEvents,
  validateKit,
  eventId,
  slugify,
  normalizeName,
  isAllowlistedKitHost,
  type CityContext,
  type Candidate,
  type DateWindow,
} from "../../../../infra/supabase/functions/_shared/city-brief-core";

// ─── Fixtures ────────────────────────────────────────────────────────────────

const fixturesDir = join(__dirname, "..", "__fixtures__");

function loadFixture<T>(name: string): T {
  return JSON.parse(readFileSync(join(fixturesDir, name), "utf-8")) as T;
}

const tavilyEvents = loadFixture<{
  results: Array<{ title: string; url: string; content: string; score: number }>;
}>("city-brief-tavily-events.json");

const deepseekEventsReply = loadFixture<Record<string, unknown>>("city-brief-deepseek-events.json");

const VTE: CityContext = {
  cityCode: "vte",
  nameEn: "Vientiane",
  nameZh: "万象",
  timezone: "Asia/Vientiane",
};

// Anchor "now" to the seed week (Mon 2026-07-06) so fixture dates land inside
// the [now-1d, now+21d] acceptance window deterministically.
const NOW = new Date("2026-07-06T00:00:00Z");

function windowFrom(now: Date): DateWindow {
  return {
    now,
    earliest: new Date(now.getTime() - 24 * 60 * 60 * 1000),
    latest: new Date(now.getTime() + 21 * 24 * 60 * 60 * 1000),
  };
}

function candidatesFromTavily(): Candidate[] {
  return tavilyEvents.results.map((r) => ({
    sourceId: "tavily",
    title: r.title,
    rawText: r.content.slice(0, 1200),
    url: r.url,
    fetchedAt: NOW.toISOString(),
  }));
}

/** Non-undefined first element (tsc `noUncheckedIndexedAccess`-friendly). */
function first<T>(arr: T[]): T {
  const v = arr[0];
  if (v === undefined) throw new Error("expected a non-empty array");
  return v;
}

// ─── tavilyQueries ───────────────────────────────────────────────────────────

describe("tavilyQueries", () => {
  it("builds 3 event queries incl. a news-topic notice query", () => {
    const qs = tavilyQueries(VTE, "events", windowFrom(NOW));
    expect(qs).toHaveLength(3);
    expect(qs.every((q) => q.query.includes("Vientiane"))).toBe(true);
    const news = qs.filter((q) => q.topic === "news");
    expect(news).toHaveLength(1);
    expect(first(news).days).toBeGreaterThan(0);
  });

  it("builds 4 kit queries, one per section", () => {
    const qs = tavilyQueries(VTE, "kit", windowFrom(NOW));
    expect(qs).toHaveLength(4);
    expect(new Set(qs.map((q) => q.section))).toEqual(new Set(["net", "money", "visa", "safety"]));
  });
});

// ─── prompts ─────────────────────────────────────────────────────────────────

describe("prompt builders", () => {
  it("events prompt lists every candidate URL for the whitelist", () => {
    const cands = candidatesFromTavily();
    const prompt = buildEventsPrompt(VTE, cands);
    for (const c of cands) expect(prompt).toContain(c.url);
    expect(prompt).toContain("zh-Hans");
    expect(prompt).toContain("refuse");
  });

  it("kit prompt states link_url is never changed by the model", () => {
    const prompt = buildKitPrompt(
      VTE,
      [{ section: "net", name: "eSIM", body: "buy eSIM", lensLine: null }],
      candidatesFromTavily(),
    );
    expect(prompt.toLowerCase()).toContain("never change link_url".toLowerCase());
    expect(prompt).toContain("confirm");
    expect(prompt).toContain("omit");
  });
});

// ─── parseModelJSON ──────────────────────────────────────────────────────────

describe("parseModelJSON", () => {
  it("strips markdown fences", () => {
    const parsed = parseModelJSON('```json\n{"a":1}\n```');
    expect(parsed).toEqual({ a: 1 });
  });

  it("takes first-brace to last-brace on surrounding prose", () => {
    const parsed = parseModelJSON('Sure! Here you go: {"ok":true} — hope that helps');
    expect(parsed).toEqual({ ok: true });
  });

  it("returns null on invalid JSON and on arrays", () => {
    expect(parseModelJSON("not json")).toBeNull();
    expect(parseModelJSON("[1,2,3]")).toBeNull();
  });
});

// ─── slug / id / normalize ───────────────────────────────────────────────────

describe("deterministic ids", () => {
  it("eventId is stable and matches evt_{city}_{slug}_{yyyymmdd}", () => {
    const id = eventId("VTE", "That Luang Night Market", "2026-07-12T15:00:00Z");
    expect(id).toBe("evt_vte_that_luang_night_market_20260712");
    // deterministic
    expect(eventId("vte", "That Luang Night Market", "2026-07-12T15:00:00Z")).toBe(id);
  });

  it("slugify falls back to a stable hash for all-CJK names (no empty slug)", () => {
    const s = slugify("塔銮周边夜市");
    expect(s.length).toBeGreaterThan(0);
    expect(slugify("塔銮周边夜市")).toBe(s); // stable
    // two different CJK names must not collide to the same fallback
    expect(slugify("塔銮周边夜市")).not.toBe(slugify("湄公河岸步道段整修封闭"));
  });

  it("normalizeName collapses punctuation/space for ±2-day dedup", () => {
    expect(normalizeName("That Luang · Night Market")).toBe(normalizeName("thatluangnightmarket"));
  });
});

// ─── isAllowlistedKitHost ────────────────────────────────────────────────────

describe("isAllowlistedKitHost", () => {
  it("accepts airalo/wise/geosure, *.gov and *.la", () => {
    expect(isAllowlistedKitHost("https://www.airalo.com/laos-esim")).toBe(true);
    expect(isAllowlistedKitHost("https://wise.com/x")).toBe(true);
    expect(isAllowlistedKitHost("https://geosureglobal.com")).toBe(true);
    expect(isAllowlistedKitHost("https://laoevisa.gov.la")).toBe(true);
    expect(isAllowlistedKitHost("https://embassy.gov")).toBe(true);
  });

  it("rejects arbitrary blogs", () => {
    expect(isAllowlistedKitHost("https://random-travel-blog.example.com/x")).toBe(false);
    expect(isAllowlistedKitHost("not-a-url")).toBe(false);
  });
});

// ─── validateEvents (the core quality gate) ──────────────────────────────────

describe("validateEvents", () => {
  const candidateURLs = tavilyEvents.results.map((r) => r.url);
  const CAND0 = first(candidateURLs);

  it("parses the canned DeepSeek reply and rejects hype + off-whitelist URLs", () => {
    const parsed = parseModelJSON(JSON.stringify(deepseekEventsReply));
    expect(parsed).not.toBeNull();
    const { accepted, rejected } = validateEvents(parsed!["events"], candidateURLs, NOW);

    const names = accepted.map((a) => a.name);
    // three clean rows survive
    expect(names).toContain("塔銮周边夜市");
    expect(names).toContain("那伽火球节前导市集");
    expect(names).toContain("湄公河岸步道段整修封闭");

    // superlative row and off-whitelist row are rejected
    expect(names).not.toContain("神秘河边酒吧一生一次派对");
    expect(names).not.toContain("查无来源的幽灵集市");

    const reasons = rejected.map((r) => r.reason);
    expect(reasons.some((r) => /superlative/.test(r))).toBe(true);
    expect(reasons.some((r) => /whitelist/.test(r))).toBe(true);
  });

  it("clamps solo_score into [0,10]", () => {
    const parsed = parseModelJSON(JSON.stringify(deepseekEventsReply));
    const { accepted } = validateEvents(parsed!["events"], candidateURLs, NOW);
    const naga = accepted.find((a) => a.name === "那伽火球节前导市集");
    expect(naga?.soloScore).toBe(10); // 12.5 clamped
  });

  it("forces solo_score = null for notices", () => {
    const parsed = parseModelJSON(JSON.stringify(deepseekEventsReply));
    const { accepted } = validateEvents(parsed!["events"], candidateURLs, NOW);
    const notice = accepted.find((a) => a.category === "notice");
    expect(notice?.soloScore).toBeNull();
  });

  it("rejects events whose ends_at is outside [now-1d, now+21d]", () => {
    const items = [
      {
        name: "过期事件",
        category: "market",
        when_label: "上周",
        ends_at: "2026-06-01T00:00:00Z",
        solo_score: 7,
        source_url: CAND0,
      },
      {
        name: "太远的事件",
        category: "market",
        when_label: "下个月",
        ends_at: "2026-09-01T00:00:00Z",
        solo_score: 7,
        source_url: CAND0,
      },
    ];
    const { accepted, rejected } = validateEvents(items, candidateURLs, NOW);
    expect(accepted).toHaveLength(0);
    expect(rejected.every((r) => /outside/.test(r.reason))).toBe(true);
  });

  it("rejects ends_at before starts_at", () => {
    const items = [
      {
        name: "时间倒挂",
        category: "market",
        when_label: "本周",
        starts_at: "2026-07-10T10:00:00Z",
        ends_at: "2026-07-10T08:00:00Z",
        solo_score: 7,
        source_url: CAND0,
      },
    ];
    const { accepted, rejected } = validateEvents(items, candidateURLs, NOW);
    expect(accepted).toHaveLength(0);
    expect(first(rejected).reason).toMatch(/before starts_at/);
  });

  it("dedups same normalized name within ±2 days", () => {
    const items = [
      {
        name: "夜市",
        category: "market",
        when_label: "周五",
        ends_at: "2026-07-10T14:00:00Z",
        solo_score: 8,
        source_url: CAND0,
      },
      {
        name: "夜 市",
        category: "market",
        when_label: "周六",
        ends_at: "2026-07-11T14:00:00Z",
        solo_score: 8,
        source_url: CAND0,
      },
    ];
    const { accepted, rejected } = validateEvents(items, candidateURLs, NOW);
    expect(accepted).toHaveLength(1);
    expect(rejected.some((r) => /duplicate/.test(r.reason))).toBe(true);
  });

  it("truncates over-long solo_note to 60 chars", () => {
    const long = "很".repeat(80);
    const items = [
      {
        name: "长备注事件",
        category: "market",
        when_label: "本周",
        ends_at: "2026-07-10T14:00:00Z",
        solo_score: 8,
        solo_note: long,
        source_url: CAND0,
      },
    ];
    const { accepted } = validateEvents(items, candidateURLs, NOW);
    expect(first(accepted).soloNote?.length).toBe(60);
  });
});

// ─── validateKit ─────────────────────────────────────────────────────────────

describe("validateKit", () => {
  const candidateURLs = [
    "https://www.airalo.com/laos-esim",
    "https://random-travel-blog.example.com/x",
  ];

  it("passes confirm/omit through and accepts a clean update", () => {
    const items = [
      { section: "net", action: "confirm" },
      { section: "money", action: "omit" },
      {
        section: "visa",
        action: "update",
        name: "落地签 30 天",
        body: "多数国籍落地签 30 天。",
        lens_line: "记好入境日",
        health: "green",
        sources: [{ type: "official", url: "https://www.airalo.com/laos-esim" }],
      },
    ];
    const { decisions, rejected } = validateKit(items, candidateURLs);
    expect(decisions).toHaveLength(3);
    expect(rejected).toHaveLength(0);
    const visa = decisions.find((d) => d.section === "visa");
    expect(visa?.action).toBe("update");
  });

  it("rejects an update with superlative language", () => {
    const items = [
      {
        section: "safety",
        action: "update",
        name: "绝对安全",
        body: "这里必去，绝对最棒。",
        health: "green",
        sources: [],
      },
    ];
    const { decisions, rejected } = validateKit(items, candidateURLs);
    expect(decisions).toHaveLength(0);
    expect(first(rejected).reason).toMatch(/superlative/);
  });

  it("rejects an update whose source url is off the allowlist", () => {
    const items = [
      {
        section: "net",
        action: "update",
        name: "eSIM",
        body: "买 eSIM。",
        health: "green",
        sources: [{ type: "blog", url: "https://random-travel-blog.example.com/x" }],
      },
    ];
    const { decisions, rejected } = validateKit(items, candidateURLs);
    expect(decisions).toHaveLength(0);
    expect(first(rejected).reason).toMatch(/allowlist|whitelist/);
  });
});
