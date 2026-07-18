/**
 * seed-city-brief.ts
 *
 * Loads the curated city-brief seed (seeds/vte-city-brief.json) into Supabase
 * via the service-role key (bypasses RLS). Upserts three tables:
 *   - sc_cities   (by city_code)
 *   - city_kits   (by (city_code, section))
 *   - city_events (by deterministic id)
 *
 * Idempotent: re-running upserts the same rows. `last_verified_at` is preserved
 * on existing rows via a pre-fetch — the seed value is used only when INSERTing a
 * new row, so a human re-verification timestamp already in the DB is never
 * clobbered by the seed's baseline date.
 *
 * Event IDs are derived the same way the compile-city-brief Edge Function does
 * (evt_{city}_{slug≤32}_{yyyymmdd}), so a seeded event and a later model-refreshed
 * event with the same name/date collapse onto one row instead of duplicating.
 *
 * Run:  pnpm tsx scripts/seed-city-brief.ts
 * Env:  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY read from process.env
 *       (export them, or run under `tsx --env-file=.env`, mirroring seed-load.ts).
 */

import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createClient } from "@supabase/supabase-js";
import { eventId } from "../infra/supabase/functions/_shared/city-brief-core";

// ─── Env ─────────────────────────────────────────────────────────────────────

function requireEnv(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing required env var: ${key}`);
  return v;
}

function getEnv(key: string, fallback: string): string {
  return process.env[key] ?? fallback;
}

// ─── Seed shape ──────────────────────────────────────────────────────────────

interface SeedCity {
  city_code: string;
  name_local: string;
  name_zh: string;
  name_en: string;
  country_code: string;
  lat: number;
  lon: number;
  timezone: string;
  brief_enabled: boolean;
}

interface SeedKit {
  section: "net" | "money" | "visa" | "safety";
  name: string;
  body: string;
  lens_line?: string | null;
  health?: "green" | "yellow" | "red" | "gray";
  last_verified_at?: string | null;
  link_url?: string | null;
  link_label?: string | null;
  action?: unknown;
  sources?: unknown;
  model_name?: string | null;
  // `seen_label` in the seed is documentation only; there is no such column on
  // city_kits — kit provenance lives in `sources`. It is ignored on load.
  seen_label?: string | null;
}

interface SeedEvent {
  name: string;
  category: string;
  when_label: string;
  starts_at?: string | null;
  ends_at: string;
  solo_score?: number | null;
  solo_note?: string | null;
  health?: "green" | "yellow" | "red" | "gray";
  seen_label?: string | null;
  lat?: number | null;
  lng?: number | null;
  limited_label?: string | null;
  source_url: string;
  verified_at?: string | null;
  model_name?: string | null;
}

interface Seed {
  city: SeedCity;
  kits: SeedKit[];
  events: SeedEvent[];
}

// ─── Validation ──────────────────────────────────────────────────────────────

function validateSeed(seed: unknown): asserts seed is Seed {
  if (typeof seed !== "object" || seed === null) {
    throw new Error("seed must be an object");
  }
  const s = seed as Record<string, unknown>;

  const city = s["city"] as Record<string, unknown> | undefined;
  if (!city || typeof city["city_code"] !== "string" || city["city_code"].trim() === "") {
    throw new Error("seed.city.city_code must be a non-empty string");
  }
  if (city["city_code"] !== (city["city_code"] as string).toLowerCase()) {
    throw new Error(`seed.city.city_code must be lowercase, got "${String(city["city_code"])}"`);
  }
  for (const field of ["name_local", "name_zh", "name_en", "country_code", "timezone"]) {
    if (typeof city[field] !== "string" || (city[field] as string).trim() === "") {
      throw new Error(`seed.city.${field} must be a non-empty string`);
    }
  }
  if (typeof city["lat"] !== "number" || typeof city["lon"] !== "number") {
    throw new Error("seed.city.lat / seed.city.lon must be numbers");
  }

  if (!Array.isArray(s["kits"])) throw new Error("seed.kits must be an array");
  const sections = new Set<string>();
  for (const [i, k] of (s["kits"] as Record<string, unknown>[]).entries()) {
    const section = k["section"];
    if (typeof section !== "string" || !["net", "money", "visa", "safety"].includes(section)) {
      throw new Error(`seed.kits[${i}].section must be net|money|visa|safety`);
    }
    if (sections.has(section)) throw new Error(`seed.kits: duplicate section "${section}"`);
    sections.add(section);
    if (typeof k["name"] !== "string" || typeof k["body"] !== "string") {
      throw new Error(`seed.kits[${i}] must have string name + body`);
    }
  }

  if (!Array.isArray(s["events"])) throw new Error("seed.events must be an array");
  const validCategories = ["culture", "wellness", "market", "music", "sports", "food", "notice"];
  for (const [i, e] of (s["events"] as Record<string, unknown>[]).entries()) {
    if (typeof e["name"] !== "string" || e["name"].trim() === "") {
      throw new Error(`seed.events[${i}].name must be a non-empty string`);
    }
    if (typeof e["category"] !== "string" || !validCategories.includes(e["category"])) {
      throw new Error(`seed.events[${i}].category invalid: ${String(e["category"])}`);
    }
    if (typeof e["ends_at"] !== "string" || Number.isNaN(Date.parse(e["ends_at"]))) {
      throw new Error(`seed.events[${i}].ends_at must be a parseable ISO timestamp`);
    }
    if (typeof e["source_url"] !== "string" || e["source_url"].trim() === "") {
      throw new Error(`seed.events[${i}].source_url must be a non-empty string`);
    }
    const score = e["solo_score"];
    if (score != null && (typeof score !== "number" || score < 0 || score > 10)) {
      throw new Error(`seed.events[${i}].solo_score must be null or in [0,10]`);
    }
  }
}

// ─── Row mappers ─────────────────────────────────────────────────────────────

function kitToRow(cityCode: string, k: SeedKit, existingLastVerifiedAt: string | null) {
  return {
    city_code: cityCode,
    section: k.section,
    name: k.name,
    body: k.body,
    lens_line: k.lens_line ?? null,
    health: k.health ?? "gray",
    // Preserve a human re-verification timestamp already on the row.
    last_verified_at: existingLastVerifiedAt ?? k.last_verified_at ?? null,
    link_url: k.link_url ?? null,
    link_label: k.link_label ?? null,
    action: k.action ?? null,
    sources: k.sources ?? [],
    model_name: k.model_name ?? null,
  };
}

function eventToRow(cityCode: string, e: SeedEvent, existingVerifiedAt: string | null) {
  const anchor = e.starts_at ?? e.ends_at;
  return {
    id: eventId(cityCode, e.name, anchor),
    city_code: cityCode,
    name: e.name,
    category: e.category,
    when_label: e.when_label,
    starts_at: e.starts_at ?? null,
    ends_at: e.ends_at,
    solo_score: e.solo_score ?? null,
    solo_note: e.solo_note ?? null,
    health: e.health ?? "gray",
    seen_label: e.seen_label ?? null,
    lat: e.lat ?? null,
    lng: e.lng ?? null,
    limited_label: e.limited_label ?? null,
    source_url: e.source_url,
    verified_at: existingVerifiedAt ?? e.verified_at ?? null,
    model_name: e.model_name ?? null,
    status: "active",
  };
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const seedPath = resolve(getEnv("SEED_FILE", "./seeds/vte-city-brief.json"));
  const supabaseUrl = requireEnv("SUPABASE_URL");
  const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

  const raw = await readFile(seedPath, "utf-8");
  const seed = JSON.parse(raw) as unknown;
  validateSeed(seed);

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const cityCode = seed.city.city_code;
  console.log(`seed-city-brief: loading ${cityCode} from ${seedPath}`);

  // 1. Upsert the city row.
  const { error: cityErr } = await client.from("sc_cities").upsert(
    {
      city_code: cityCode,
      name_local: seed.city.name_local,
      name_zh: seed.city.name_zh,
      name_en: seed.city.name_en,
      country_code: seed.city.country_code,
      lat: seed.city.lat,
      lon: seed.city.lon,
      timezone: seed.city.timezone,
      brief_enabled: seed.city.brief_enabled,
    },
    { onConflict: "city_code" },
  );
  if (cityErr) throw new Error(`sc_cities upsert failed: ${cityErr.message}`);
  console.log(`  [OK] sc_cities: ${cityCode}`);

  // 2. Upsert kits, preserving last_verified_at on existing rows.
  const { data: existingKits, error: kitFetchErr } = await client
    .from("city_kits")
    .select("section, last_verified_at")
    .eq("city_code", cityCode);
  if (kitFetchErr) throw new Error(`city_kits pre-fetch failed: ${kitFetchErr.message}`);
  const kitLastVerified = new Map<string, string | null>();
  for (const row of existingKits ?? []) {
    kitLastVerified.set(row.section as string, (row.last_verified_at as string | null) ?? null);
  }
  const kitRows = seed.kits.map((k) =>
    kitToRow(cityCode, k, kitLastVerified.get(k.section) ?? null),
  );
  const { error: kitErr, count: kitCount } = await client
    .from("city_kits")
    .upsert(kitRows, { onConflict: "city_code,section", ignoreDuplicates: false })
    .select("section");
  if (kitErr) throw new Error(`city_kits upsert failed: ${kitErr.message}`);
  console.log(`  [OK] city_kits: ${kitCount ?? kitRows.length} row(s)`);

  // 3. Upsert events, preserving verified_at on existing rows.
  const eventIds = seed.events.map((e) => eventId(cityCode, e.name, e.starts_at ?? e.ends_at));
  const { data: existingEvents, error: evFetchErr } = await client
    .from("city_events")
    .select("id, verified_at")
    .in("id", eventIds);
  if (evFetchErr) throw new Error(`city_events pre-fetch failed: ${evFetchErr.message}`);
  const evVerified = new Map<string, string | null>();
  for (const row of existingEvents ?? []) {
    evVerified.set(row.id as string, (row.verified_at as string | null) ?? null);
  }
  const finalEventRows = seed.events.map((e) =>
    eventToRow(
      cityCode,
      e,
      evVerified.get(eventId(cityCode, e.name, e.starts_at ?? e.ends_at)) ?? null,
    ),
  );
  const { error: evErr, count: evCount } = await client
    .from("city_events")
    .upsert(finalEventRows, { onConflict: "id", ignoreDuplicates: false })
    .select("id");
  if (evErr) throw new Error(`city_events upsert failed: ${evErr.message}`);
  console.log(`  [OK] city_events: ${evCount ?? finalEventRows.length} row(s)`);

  console.log(
    `\nseed-city-brief complete — city: 1, kits: ${kitRows.length}, events: ${finalEventRows.length}`,
  );
}

main().catch((err) => {
  console.error("seed-city-brief error:", (err as Error).message);
  process.exit(1);
});
