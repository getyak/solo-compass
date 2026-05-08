/**
 * Unit tests for structureExperience.
 *
 * All tests use inline synthetic mock responses — no DEEPSEEK_API_KEY or golden
 * files needed. Run `LIVE_API=true pnpm --filter @solo-compass/ai test:live` to
 * re-record golden responses once a real key is available.
 */

import { describe, it, expect, vi } from "vitest";
import type OpenAI from "openai";
import { structureExperience } from "./prompts/structure-experience";

// ─── Synthetic response payloads ──────────────────────────────────────────────

const EMIT_SUTHEP = {
  action: "emit",
  title: "Watch dawn light the golden chedi at Doi Suthep before the crowds arrive",
  oneLiner:
    "The most sacred moment at northern Thailand's holiest temple belongs to those who arrive at sunrise.",
  whyItMatters:
    "At 06:00 the gilded chedi glows orange-gold against a mist-covered valley. By 09:00 tour buses fill the terrace.",
  category: "culture",
  coordinates: { longitude: 98.9217, latitude: 18.8048 },
  addressHint: "Doi Suthep mountain, 15 km northwest of Chiang Mai old city",
  placeNameLocal: "วัดพระธาตุดอยสุเทพ",
  placeNameRomanized: "Wat Phra That Doi Suthep",
  bestTimes: [
    { startHour: 6, endHour: 8, note: "Sunrise — mist in valley, monks chanting, minimal crowds" },
  ],
  durationMin: 60,
  durationMax: 120,
  howTo: [
    { order: 1, text: "Board a songthaew at Chang Puak bus terminal and depart by 05:30." },
    { order: 2, text: "Climb the 1,685-step Naga staircase (free) or take the cable car." },
    {
      order: 3,
      text: "Pay the 50 THB entrance fee and remove shoes before stepping onto the terrace.",
    },
    { order: 4, text: "Circumambulate the golden chedi clockwise three times." },
    { order: 5, text: "Stand at the eastern viewpoint and watch the mist clear from the valley." },
    { order: 6, text: "Leave before 09:00 to beat the tour-bus wave." },
  ],
  realInconveniences: [
    { category: "crowds", text: "On weekends expect 200+ people queuing to photograph the chedi." },
    {
      category: "scam",
      text: "Songthaew drivers routinely overcharge — agree the fare before boarding.",
    },
    {
      category: "etiquette",
      text: "Shoulders and knees must be covered; sarongs are at the gate.",
    },
  ],
  sources: [
    {
      type: "wikivoyage",
      url: "https://en.wikivoyage.org/wiki/Chiang_Mai/Doi_Suthep",
      attribution: null,
      verifiedAt: "2026-05-07T00:00:00Z",
    },
  ],
  modelConfidence: 0.88,
};

const EMIT_COFFEE = {
  action: "emit",
  title: "Order single-origin micro-lots in the 8-seat Lab at Ristr8to before stocks run out",
  oneLiner:
    "A basement coffee lab where the barista explains altitude differences between two Doi Chaang farms.",
  whyItMatters:
    "The Lab is deliberately WiFi-free and seats only eight. Barista Bee has five years of championship experience.",
  category: "coffee",
  coordinates: { longitude: 98.9665, latitude: 18.7966 },
  addressHint: "15/3 Nimman Soi 3, Suthep, Chiang Mai — downstairs Lab section",
  placeNameLocal: null,
  placeNameRomanized: "Ristr8to Lab",
  bestTimes: [
    { startHour: 8, endHour: 11, note: "Tuesday–Saturday; micro-lots sell out by afternoon" },
  ],
  durationMin: 45,
  durationMax: 60,
  howTo: [
    { order: 1, text: "Arrive Tuesday–Saturday between 08:00 and 09:30." },
    { order: 2, text: "Head downstairs to the Lab section, not the main floor." },
    { order: 3, text: "Ask for the single-origin micro-lot menu." },
    { order: 4, text: "Ask barista Bee to explain the processing." },
    { order: 5, text: "Pay cash — the Lab is cash-only; ATM on Nimman Soi 1 is 200 m away." },
  ],
  realInconveniences: [
    { category: "logistics", text: "Cash only in the Lab — no card payment." },
    { category: "crowds", text: "Only 8 seats; arrivals after 10:00 will likely wait." },
    { category: "other", text: "Closed Sundays and Mondays." },
  ],
  sources: [
    {
      type: "reddit",
      url: "https://www.reddit.com/r/chiangmai/comments/coffee_thread_2024",
      attribution: "u/AroiMakSikhao",
      verifiedAt: "2026-05-07T00:00:00Z",
    },
  ],
  modelConfidence: 0.91,
};

const REFUSE_BLURB = {
  action: "refuse",
  reason:
    "Source is a generic tourist-brochure summary with no specific experience, no how-to steps, and no verifiable coordinates.",
};

// ─── Helper ────────────────────────────────────────────────────────────────────

function makeMockClient(payload: Record<string, unknown>): OpenAI {
  return {
    chat: {
      completions: {
        create: vi.fn().mockResolvedValue({
          choices: [{ message: { content: JSON.stringify(payload) } }],
          usage: { prompt_tokens: 100, completion_tokens: 80, total_tokens: 180 },
          model: "deepseek-v4-pro",
        }),
      },
    },
  } as unknown as OpenAI;
}

const BASE_INPUT = {
  rawText: "Synthetic raw text for unit testing.",
  cityCode: "cmi",
  cityName: "Chiang Mai",
};

// ─── Emit-success path ────────────────────────────────────────────────────────

describe("structureExperience — emit success (cultural experience)", () => {
  it("returns a non-null experience", async () => {
    const result = await structureExperience(BASE_INPUT, makeMockClient(EMIT_SUTHEP));
    expect(result.experience).not.toBeNull();
  });

  it("experience passes full schema validation", async () => {
    const { experience } = await structureExperience(BASE_INPUT, makeMockClient(EMIT_SUTHEP));
    expect(experience).not.toBeNull();
    if (!experience) return;

    expect(typeof experience.id).toBe("string");
    expect(experience.id).toMatch(/^exp_cmi_/);
    expect(typeof experience.title).toBe("string");
    expect(experience.title.length).toBeGreaterThan(0);
    expect(typeof experience.oneLiner).toBe("string");
    expect(typeof experience.whyItMatters).toBe("string");

    const validCategories = [
      "culture",
      "nature",
      "food",
      "coffee",
      "work",
      "wellness",
      "nightlife",
      "hidden",
    ];
    expect(validCategories).toContain(experience.category);

    expect(Array.isArray(experience.location.coordinates)).toBe(true);
    expect(experience.location.coordinates).toHaveLength(2);
    expect(typeof experience.location.coordinates[0]).toBe("number");
    expect(typeof experience.location.coordinates[1]).toBe("number");
    expect(experience.location.cityCode).toBe("cmi");

    for (const t of experience.bestTimes) {
      expect(t.startHour).toBeGreaterThanOrEqual(0);
      expect(t.startHour).toBeLessThanOrEqual(23);
      expect(t.endHour).toBeGreaterThanOrEqual(0);
      expect(t.endHour).toBeLessThanOrEqual(23);
    }

    expect(experience.durationMinutes.max).toBeGreaterThanOrEqual(experience.durationMinutes.min);

    expect(experience.howTo.length).toBeGreaterThanOrEqual(3);
    expect(experience.howTo.length).toBeLessThanOrEqual(7);

    expect(experience.realInconveniences.length).toBeGreaterThanOrEqual(1);
    const validIncCategories = [
      "scam",
      "crowds",
      "logistics",
      "weather",
      "etiquette",
      "safety",
      "other",
    ];
    for (const inc of experience.realInconveniences) {
      expect(validIncCategories).toContain(inc.category);
      expect(inc.text.length).toBeGreaterThan(0);
    }

    expect(experience.sources.length).toBeGreaterThanOrEqual(1);
    expect(experience.status).toBe("candidate");
    expect(experience.confidence.level).toBe(1);
  });

  it("coordinates are in GeoJSON order [longitude, latitude] for Chiang Mai region", async () => {
    const { experience } = await structureExperience(BASE_INPUT, makeMockClient(EMIT_SUTHEP));
    expect(experience).not.toBeNull();
    if (!experience) return;

    const [lng, lat] = experience.location.coordinates;
    // Chiang Mai: lat ~18-19°N, lng ~98-99°E
    expect(lng).toBeGreaterThan(90);
    expect(lng).toBeLessThan(110);
    expect(lat).toBeGreaterThan(15);
    expect(lat).toBeLessThan(25);
  });

  it("source URL not fabricated — only URLs present in input are passed through", async () => {
    const sourceUrl = "https://en.wikivoyage.org/wiki/Chiang_Mai/Doi_Suthep";
    const { experience } = await structureExperience(
      { ...BASE_INPUT, sourceUrl, sourceType: "wikivoyage" },
      makeMockClient(EMIT_SUTHEP),
    );
    expect(experience).not.toBeNull();
    if (!experience) return;

    for (const source of experience.sources) {
      if (source.url) {
        // The URL in our synthetic payload matches the sourceUrl provided in input
        expect(sourceUrl).toContain(new URL(source.url).pathname.split("/").slice(-1)[0] ?? "");
      }
    }
  });

  it("model confidence is between 0 and 1", async () => {
    const result = await structureExperience(BASE_INPUT, makeMockClient(EMIT_SUTHEP));
    expect(result.modelConfidence).toBeGreaterThanOrEqual(0);
    expect(result.modelConfidence).toBeLessThanOrEqual(1);
  });

  it("ID slug has no spaces or special chars", async () => {
    const { experience } = await structureExperience(BASE_INPUT, makeMockClient(EMIT_SUTHEP));
    expect(experience).not.toBeNull();
    if (!experience) return;
    expect(experience.id).toMatch(/^exp_[a-z0-9]+_[a-z0-9_]+$/);
  });

  it("soloScore is initialized with zero values", async () => {
    const { experience } = await structureExperience(BASE_INPUT, makeMockClient(EMIT_SUTHEP));
    expect(experience).not.toBeNull();
    if (!experience) return;
    expect(experience.soloScore.overall).toBe(0);
    expect(experience.soloScore.basedOnCount).toBe(0);
  });

  it("nearbyExperienceIds starts empty", async () => {
    const { experience } = await structureExperience(BASE_INPUT, makeMockClient(EMIT_SUTHEP));
    expect(experience?.nearbyExperienceIds).toEqual([]);
  });
});

// ─── Emit-success path (coffee) ───────────────────────────────────────────────

describe("structureExperience — emit success (coffee experience)", () => {
  it("category is 'coffee' for coffee-focused source", async () => {
    const { experience } = await structureExperience(
      { ...BASE_INPUT, sourceType: "reddit" as const },
      makeMockClient(EMIT_COFFEE),
    );
    expect(experience).not.toBeNull();
    expect(experience?.category).toBe("coffee");
  });

  it("source type reddit is preserved in sources array", async () => {
    const { experience } = await structureExperience(
      { ...BASE_INPUT, sourceType: "reddit" as const },
      makeMockClient(EMIT_COFFEE),
    );
    expect(experience).not.toBeNull();
    if (!experience) return;
    expect(experience.sources.some((s) => s.type === "reddit")).toBe(true);
  });

  it("realInconveniences includes at least one honest downside", async () => {
    const { experience } = await structureExperience(BASE_INPUT, makeMockClient(EMIT_COFFEE));
    expect(experience?.realInconveniences.length).toBeGreaterThanOrEqual(1);
  });

  it("experience ID uses city code prefix", async () => {
    const { experience } = await structureExperience(BASE_INPUT, makeMockClient(EMIT_COFFEE));
    expect(experience?.id).toMatch(/^exp_cmi_/);
  });
});

// ─── Refuse path ──────────────────────────────────────────────────────────────

describe("structureExperience — refuse path", () => {
  it("returns null experience for thin source", async () => {
    const result = await structureExperience(BASE_INPUT, makeMockClient(REFUSE_BLURB));
    expect(result.experience).toBeNull();
  });

  it("provides a non-empty refusal reason", async () => {
    const result = await structureExperience(BASE_INPUT, makeMockClient(REFUSE_BLURB));
    expect(result.refusalReason).toBeDefined();
    expect(typeof result.refusalReason).toBe("string");
    expect(result.refusalReason!.length).toBeGreaterThan(10);
  });

  it("model confidence is 0 on refusal", async () => {
    const result = await structureExperience(BASE_INPUT, makeMockClient(REFUSE_BLURB));
    expect(result.modelConfidence).toBe(0);
  });
});

// ─── Fence-wrapped response stripping ─────────────────────────────────────────

describe("structureExperience — fence-wrapped response stripping", () => {
  it("strips ```json fences before parsing", async () => {
    const fencedContent = "```json\n" + JSON.stringify(EMIT_SUTHEP) + "\n```";
    const mockClient = {
      chat: {
        completions: {
          create: vi.fn().mockResolvedValue({
            choices: [{ message: { content: fencedContent } }],
            usage: { prompt_tokens: 100, completion_tokens: 80, total_tokens: 180 },
            model: "deepseek-v4-pro",
          }),
        },
      },
    } as unknown as OpenAI;

    const result = await structureExperience(BASE_INPUT, mockClient);
    expect(result.experience).not.toBeNull();
  });

  it("strips plain ``` fences before parsing", async () => {
    const fencedContent = "```\n" + JSON.stringify(EMIT_COFFEE) + "\n```";
    const mockClient = {
      chat: {
        completions: {
          create: vi.fn().mockResolvedValue({
            choices: [{ message: { content: fencedContent } }],
            usage: { prompt_tokens: 100, completion_tokens: 80, total_tokens: 180 },
            model: "deepseek-v4-pro",
          }),
        },
      },
    } as unknown as OpenAI;

    const result = await structureExperience(BASE_INPUT, mockClient);
    expect(result.experience).not.toBeNull();
  });
});

// ─── Malformed JSON returns null with refusalReason ───────────────────────────

describe("structureExperience — malformed JSON", () => {
  it("returns null experience with refusalReason when model returns invalid JSON", async () => {
    const mockClient = {
      chat: {
        completions: {
          create: vi.fn().mockResolvedValue({
            choices: [{ message: { content: "not valid json at all" } }],
            usage: { prompt_tokens: 50, completion_tokens: 10, total_tokens: 60 },
            model: "deepseek-v4-pro",
          }),
        },
      },
    } as unknown as OpenAI;

    const result = await structureExperience(BASE_INPUT, mockClient);

    expect(result.experience).toBeNull();
    expect(result.refusalReason).toBeDefined();
    expect(typeof result.refusalReason).toBe("string");
    expect(result.refusalReason!.length).toBeGreaterThan(0);
    expect(result.modelConfidence).toBe(0);
  });

  it("returns null with reason for unexpected action value", async () => {
    const mockClient = {
      chat: {
        completions: {
          create: vi.fn().mockResolvedValue({
            choices: [{ message: { content: JSON.stringify({ action: "unknown_action" }) } }],
            usage: { prompt_tokens: 50, completion_tokens: 20, total_tokens: 70 },
            model: "deepseek-v4-pro",
          }),
        },
      },
    } as unknown as OpenAI;

    const result = await structureExperience(BASE_INPUT, mockClient);

    expect(result.experience).toBeNull();
    expect(result.refusalReason).toContain("unknown_action");
    expect(result.modelConfidence).toBe(0);
  });

  it("propagates API errors (thrown exception)", async () => {
    const mockClient = {
      chat: {
        completions: {
          create: vi.fn().mockRejectedValue(new Error("Rate limit exceeded")),
        },
      },
    } as unknown as OpenAI;

    await expect(structureExperience(BASE_INPUT, mockClient)).rejects.toThrow(
      "Rate limit exceeded",
    );
  });
});
