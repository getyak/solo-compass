/**
 * Experience — the core unit of Solo Compass.
 *
 * NOT a place. NOT a POI. An experience is a *concrete, time-bound, story-rich
 * thing worth doing*, anchored to a place but not reducible to it.
 *
 *   "Wat Suan Dok temple"           ← place (we don't store this)
 *   "Watch the sunset paint the
 *    white stupas at 17:30"          ← experience (this is our unit)
 *
 * The schema is the moat. Every field exists because of a real product decision
 * documented in docs/PRODUCT_BRIEF.md. Don't add fields here without reading it.
 */

import type { Coordinates } from "./geo";
import type { Confidence } from "./confidence";
import type { SoloScore } from "./solo-score";

/**
 * Stable string identifier. Format: `exp_<city>_<slug>` (e.g. `exp_cmi_suan_dok_sunset`).
 * Generated once, never changes. Used in URLs and cross-references.
 */
export type ExperienceId = string & { readonly __brand: "ExperienceId" };

/**
 * ID prefix for experiences synthesised from OpenStreetMap POI data by the
 * AI pipeline. These entries start at `confidenceLevel === 1` (AI-generated,
 * not yet human-verified) and are promoted as users confirm them.
 *
 * Format: `exp_osm_<osm_id>` (e.g. `exp_osm_123456789`).
 */
export const EXP_OSM_ID_PREFIX = "exp_osm_" as const;

/**
 * Experience categories. Kept deliberately small — adding categories has high
 * downstream cost (icon design, filter UI, recommendation tuning). Resist the
 * urge to subdivide. If something doesn't fit, ask whether it's really an
 * experience.
 */
export type ExperienceCategory =
  | "culture" //   🛕 temples, monasteries, historical sites, ceremonies
  | "nature" //    🌳 viewpoints, hikes, parks, natural wonders
  | "food" //      🍜 specific meals at specific places (not generic restaurants)
  | "coffee" //    ☕ coffee places worth a journey, not daily caffeine
  | "work" //      💻 places to focus for 2+ hours (cafés, libraries, co-working)
  | "wellness" // 💆 massage, yoga, meditation, baths
  | "nightlife" // 🌃 evening scenes that aren't generic bars
  | "hidden"; //   ✨ user-discovered, not-on-attractions-list places

/**
 * Time windows when this experience is at its best. An experience can have
 * multiple windows (e.g. sunset AND sunrise). Empty array = anytime.
 *
 * `dayOfWeek`: 0=Sun .. 6=Sat. Empty/undefined = any day.
 * `season`: ISO month numbers 1-12. Empty/undefined = year-round.
 */
export interface TimeWindow {
  readonly startHour: number; // 0–23, local time
  readonly endHour: number; // 0–23, local time
  readonly dayOfWeek?: readonly number[];
  readonly season?: readonly number[];
  readonly note?: string; // e.g. "30 min before sunset"
}

/**
 * Where the experience lives. We store coordinates explicitly rather than
 * referencing an external Place ID — places change names, get renumbered,
 * disappear. Coordinates are eternal.
 */
export interface ExperienceLocation {
  readonly coordinates: Coordinates;
  readonly cityCode: string; // ISO-style: "cmi" (Chiang Mai), "ubud", etc.
  readonly addressHint?: string; // human-readable, NOT the source of truth
  readonly placeNameLocal?: string; // "วัดสวนดอก" — local language
  readonly placeNameRomanized?: string; // "Wat Suan Dok"
  // Cross-channel "hard" signals enriched from Foursquare / Apple MapKit when
  // available. All optional: OSM-only places leave them undefined. Surfaced to
  // the AI synthesis prompt so generated copy can cite real data instead of
  // generic placeholders, and shown in the detail view when present.
  readonly rating?: number; // 0–10 normalized provider rating (Foursquare uses 0–10)
  readonly openingHours?: string; // raw provider hours string, e.g. "Mon-Fri 8:00-18:00"
  readonly priceLevel?: number; // 1–4 (1 = cheap, 4 = expensive)
  readonly website?: string;
  readonly phone?: string;
}

/**
 * What the user actually does, step by step. 3–7 steps is the sweet spot.
 * Fewer = vague. More = a checklist, not an experience.
 */
export interface HowToStep {
  readonly order: number;
  readonly text: string;
}

/**
 * The unflattering side of every experience. These exist *as a separate field*
 * — not buried in the description — because honesty about inconvenience is the
 * product's moat. Tour books edit these out. We surface them.
 */
export interface RealInconvenience {
  readonly category: "scam" | "crowds" | "logistics" | "weather" | "etiquette" | "safety" | "other";
  readonly text: string;
}

/**
 * Where the seed information for this experience came from. Persists with the
 * experience forever — the user can always trace back to original sources.
 *
 * `verifiedAt`: ISO timestamp of last AI re-fetch or human verification.
 *               If older than 60 days, the experience shows ⚫ "may be stale".
 */
export interface InformationSource {
  readonly type:
    | "wikivoyage"
    | "wikipedia"
    | "reddit"
    | "blog"
    | "youtube"
    | "user"
    | "field_visit";
  readonly url?: string;
  readonly attribution?: string; // user handle, blog name, etc.
  readonly verifiedAt: string; // ISO 8601
}

/**
 * The complete Experience record.
 *
 * Two flows produce these:
 *   1. AI-curated from open data (Wikivoyage + Reddit + blogs) → reviewed by humans
 *   2. User-shared via 30-second voice memo → AI-structured → verified by 1–2 users
 *
 * Both flows produce the same shape. Provenance is visible via `sources` and
 * `confidence`.
 */
export interface Experience {
  readonly id: ExperienceId;

  /** Action-oriented title. NOT a place name.
   *  ✅ "Watch the sunset paint the white stupas"
   *  ❌ "Wat Suan Dok temple" */
  readonly title: string;

  /** One sentence. Should answer "why does this exist?" */
  readonly oneLiner: string;

  /** Three sentences max. Atmosphere, sensory details, the *feel* of being there.
   *  This is what makes the experience emotional, not a list. */
  readonly whyItMatters: string;

  readonly category: ExperienceCategory;
  readonly location: ExperienceLocation;

  /** When this is at its best. */
  readonly bestTimes: readonly TimeWindow[];

  /** Typical duration, minutes. Range = uncertainty (60–90), single = precise (45). */
  readonly durationMinutes: { readonly min: number; readonly max: number };

  /** Step-by-step. Don't repeat what's in `whyItMatters` — those are different things. */
  readonly howTo: readonly HowToStep[];

  /** Things that will go wrong. Surface them. */
  readonly realInconveniences: readonly RealInconvenience[];

  /** Solo-friendliness, computed from user reports + heuristics. */
  readonly soloScore: SoloScore;

  /** Provenance + recency = trust. */
  readonly sources: readonly InformationSource[];
  readonly confidence: Confidence;

  /** Other experiences within walking distance worth chaining.
   *  Stored as IDs to avoid circular shape issues. The recommendation engine
   *  expands these on demand. */
  readonly nearbyExperienceIds: readonly ExperienceId[];

  /** Aggregate stats — denormalized for query speed. Updated by background job. */
  readonly stats: {
    readonly completionCount: number;
    readonly averageRating: number; // 0–5
    readonly lastCompletedAt?: string; // ISO 8601
  };

  /** Lifecycle. */
  readonly status: "candidate" | "active" | "stale" | "retired";
  readonly createdAt: string;
  readonly updatedAt: string;

  /** User-defined free-form tags layered on top of the category enum.
   *  Optional in JSON; absence is equivalent to an empty array. */
  readonly userTags?: readonly string[];
}

/**
 * A user-shared experience that hasn't been verified yet.
 * Same shape as Experience, but `status: "candidate"` and `confidence` is low.
 * Surfaces on the map with a distinct icon — users can opt into verifying it.
 */
export type CandidateExperience = Experience & { readonly status: "candidate" };

/**
 * A city the user has reverse-geocoded after an Explore session.
 * Mirrors `DiscoveredCityRecord` in the iOS SwiftData layer.
 *
 * `cityCode` — slug like `"vn-hanoi"` or the synthetic `"osm_<lat>_<lon>"`.
 * `centerLat` / `centerLon` — WGS-84 degrees, stored as two scalars (not a
 *   `Coordinates` pair) so SwiftData can index them independently.
 * `discoveredAt` — ISO 8601 UTC timestamp of first reverse-geocode.
 */
export interface DiscoveredCity {
  readonly cityCode: string;
  readonly name: string;
  readonly countryCode: string;
  readonly centerLat: number;
  readonly centerLon: number;
  readonly discoveredAt: string; // ISO 8601
}

/**
 * Type guard.
 */
export function isCandidateExperience(exp: Experience): exp is CandidateExperience {
  return exp.status === "candidate";
}
