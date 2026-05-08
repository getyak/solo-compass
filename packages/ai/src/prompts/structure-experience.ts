import type OpenAI from "openai";
import type {
  Experience,
  ExperienceId,
  ExperienceCategory,
  TimeWindow,
  HowToStep,
  RealInconvenience,
  InformationSource,
} from "@solo-compass/core";
import { createDeepseekClient, deepseekModel } from "../client";
import { withCostTracking } from "../cost-tracker";
import { withRetry } from "../retry";

// ─── Input / Output ────────────────────────────────────────────────────────────

export interface StructureExperienceInput {
  /** Raw text from Wikivoyage section, Reddit thread, blog post, etc. */
  rawText: string;
  /** ISO-style city code used in experience IDs, e.g. "cmi" for Chiang Mai. */
  cityCode: string;
  /** Human-readable city name for prompt context, e.g. "Chiang Mai". */
  cityName: string;
  /** Original URL of the source document — cited in output sources field. */
  sourceUrl?: string;
  /** Source type — defaults to "blog" when not specified. */
  sourceType?: InformationSource["type"];
}

export interface StructureExperienceResult {
  experience: Experience | null;
  /** Why the model returned null — only set when experience is null. */
  refusalReason?: string;
  /** Raw confidence 0–1 from the model on its own output quality. */
  modelConfidence: number;
}

// ─── System prompt ─────────────────────────────────────────────────────────────

function buildSystemPrompt(cityName: string): string {
  return `You are a solo-travel experience curator for ${cityName}. Your job is to extract ONE concrete, time-bound, story-rich experience from raw source text.

WHAT YOU ARE EXTRACTING:
An "experience" is a specific thing worth doing — anchored to a place but NOT reducible to it.
  ✅ "Watch the sunset paint the white stupas at 17:30" — experience
  ❌ "Wat Suan Dok temple" — place name (reject this framing)

STRICT RULES — violating any of these is a critical failure:

1. NEVER fabricate. If a price, hour, or coordinate is not derivable from the text and your geographic knowledge of the city, use action="refuse".
2. ALWAYS populate realInconveniences with at least one honest downside. If none appear in the source, note: "other: specific downsides not confirmed in source — verify before visiting."
3. NEVER cite a URL that was not provided in the input. Set url only if the exact URL was given.
4. Set confidence.level = 1 (AI scrape, no human verify). Non-negotiable for this pipeline.
5. If source material yields only a generic summary ("great temple, worth visiting") with no sensory detail, no how-to, and no specific inconvenience — use action="refuse".
6. howTo must be 3–7 concrete steps. "Go there and enjoy it" is not a step.
7. title must be action-oriented. It cannot be a place name.

REFUSAL CRITERIA — use action="refuse" when:
- Source is fewer than ~150 words of substantive content
- Source describes a general area or district, not a specific experience
- You would need to fabricate coordinates, prices, or hours not in the source
- The experience is not solo-friendly (mandatory group activity, couples-only venue)

OUTPUT FORMAT:
Output ONLY a JSON object with NO markdown fences, NO extra text. The object must have:

For refusal:
{
  "action": "refuse",
  "reason": string  // why you are refusing — be specific about what is missing
}

For emission:
{
  "action": "emit",
  "title": string,              // action-oriented, specific, NOT a place name
  "oneLiner": string,           // one sentence answering "why does this experience exist?"
  "whyItMatters": string,       // three sentences max, atmosphere + sensory detail, no bullets
  "category": "culture"|"nature"|"food"|"coffee"|"work"|"wellness"|"nightlife"|"hidden",
  "coordinates": { "longitude": number, "latitude": number },  // WGS84, GeoJSON order
  "addressHint": string,        // human-readable, vague OK, do NOT fabricate a street address
  "placeNameLocal": string|null,      // local script name, null if not in source
  "placeNameRomanized": string|null,  // romanized name, null if not in source
  "bestTimes": [                // empty array = anytime
    { "startHour": number, "endHour": number, "note": string|null }
  ],
  "durationMin": number,        // minimum typical duration in minutes
  "durationMax": number,        // maximum typical duration in minutes
  "howTo": [                    // 3–7 steps, each something the user physically does
    { "order": number, "text": string }
  ],
  "realInconveniences": [       // REQUIRED ≥1, never gloss over downsides
    { "category": "scam"|"crowds"|"logistics"|"weather"|"etiquette"|"safety"|"other", "text": string }
  ],
  "sources": [                  // cite every source; include url only if provided in input
    { "type": "wikivoyage"|"wikipedia"|"reddit"|"blog"|"youtube"|"user"|"field_visit", "url": string|null, "attribution": string|null, "verifiedAt": string }
  ],
  "modelConfidence": number     // 0–1, your honest confidence given the source material
}`;
}

// ─── JSON fence stripper ───────────────────────────────────────────────────────

function stripFences(raw: string): string {
  return raw
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```\s*$/, "")
    .trim();
}

// ─── Main function ─────────────────────────────────────────────────────────────

export async function structureExperience(
  input: StructureExperienceInput,
  client?: OpenAI,
): Promise<StructureExperienceResult> {
  const deepseek = client ?? createDeepseekClient();
  const now = new Date().toISOString();
  const route = "structure";

  const userMessage = `Source type: ${input.sourceType ?? "blog"}
City: ${input.cityName} (code: ${input.cityCode})
${input.sourceUrl ? `Source URL: ${input.sourceUrl}` : "No source URL provided"}

---RAW SOURCE TEXT---
${input.rawText}
---END SOURCE TEXT---

Extract one concrete experience from the text above, or refuse if the material is too thin. Output ONLY the JSON object.`;

  const response = await withRetry(() =>
    withCostTracking(route, async () => {
      const msg = await deepseek.chat.completions.create({
        model: deepseekModel(),
        max_tokens: 2048,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: buildSystemPrompt(input.cityName) },
          { role: "user", content: userMessage },
        ],
      });
      const usage = msg.usage ?? { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 };
      return { result: msg, usage, model: msg.model };
    }),
  );

  const rawContent = response.choices[0]?.message.content ?? "";
  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(stripFences(rawContent)) as Record<string, unknown>;
  } catch {
    return {
      experience: null,
      refusalReason: "Model returned invalid JSON",
      modelConfidence: 0,
    };
  }

  if (parsed["action"] === "refuse") {
    return {
      experience: null,
      refusalReason:
        typeof parsed["reason"] === "string" ? parsed["reason"] : "Model refused without reason",
      modelConfidence: 0,
    };
  }

  if (parsed["action"] === "emit") {
    const raw = parsed as {
      title: string;
      oneLiner: string;
      whyItMatters: string;
      category: ExperienceCategory;
      coordinates: { longitude: number; latitude: number };
      addressHint: string;
      placeNameLocal?: string | null;
      placeNameRomanized?: string | null;
      bestTimes: Array<{ startHour: number; endHour: number; note?: string | null }>;
      durationMin: number;
      durationMax: number;
      howTo: Array<{ order: number; text: string }>;
      realInconveniences: Array<{ category: RealInconvenience["category"]; text: string }>;
      sources: Array<{
        type: InformationSource["type"];
        url?: string | null;
        attribution?: string | null;
        verifiedAt: string;
      }>;
      modelConfidence: number;
    };

    const slug = raw.title
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "_")
      .replace(/^_|_$/g, "")
      .slice(0, 40);

    const experience: Experience = {
      id: `exp_${input.cityCode}_${slug}` as ExperienceId,
      title: raw.title,
      oneLiner: raw.oneLiner,
      whyItMatters: raw.whyItMatters,
      category: raw.category,
      location: {
        coordinates: [raw.coordinates.longitude, raw.coordinates.latitude],
        cityCode: input.cityCode,
        addressHint: raw.addressHint,
        placeNameLocal: raw.placeNameLocal ?? undefined,
        placeNameRomanized: raw.placeNameRomanized ?? undefined,
      },
      bestTimes: raw.bestTimes.map(
        (t): TimeWindow => ({
          startHour: t.startHour,
          endHour: t.endHour,
          note: t.note ?? undefined,
        }),
      ),
      durationMinutes: { min: raw.durationMin, max: raw.durationMax },
      howTo: raw.howTo.map((s): HowToStep => ({ order: s.order, text: s.text })),
      realInconveniences: raw.realInconveniences,
      soloScore: {
        overall: 0,
        breakdown: {
          seatingFriendly: 0,
          soloPatronRatio: 0,
          staffPressure: 0,
          soloPortioning: 0,
          ambianceFit: 0,
          safety: 0,
        },
        basedOnCount: 0,
      },
      sources: raw.sources.map((s) => ({
        type: s.type,
        url: s.url ?? undefined,
        attribution: s.attribution ?? undefined,
        verifiedAt: s.verifiedAt,
      })),
      confidence: {
        level: 1,
        lastVerifiedAt: now,
        reason: "AI-scraped from open sources, no human verification",
        signals: {
          aiScrapeAgeDays: 0,
          passiveGpsHits30d: 0,
          activeReports30d: 0,
          trustedVerifications: 0,
        },
      },
      nearbyExperienceIds: [],
      stats: { completionCount: 0, averageRating: 0 },
      status: "candidate",
      createdAt: now,
      updatedAt: now,
    };

    return { experience, modelConfidence: raw.modelConfidence };
  }

  return {
    experience: null,
    refusalReason: `Unexpected action value: ${String(parsed["action"])}`,
    modelConfidence: 0,
  };
}
