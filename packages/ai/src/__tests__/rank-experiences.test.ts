/**
 * Anti-hallucination unit tests for rankExperiences.
 *
 * All tests pass a mock OpenAI client — no real API calls are made.
 */

import { describe, it, expect, vi } from "vitest";
import type OpenAI from "openai";
import { rankExperiences } from "../prompts/rank-experiences";
import type { Experience, ExperienceId } from "@solo-compass/core";

// ─── Helpers ──────────────────────────────────────────────────────────────────

function makeExperience(id: string, title: string): Experience {
  return {
    id: id as ExperienceId,
    title,
    oneLiner: "Test one-liner.",
    whyItMatters: "Test why it matters.",
    category: "culture",
    location: {
      coordinates: [100.0, 18.0],
      cityCode: "cmi",
      addressHint: "Near the old city",
    },
    bestTimes: [{ startHour: 6, endHour: 20 }],
    durationMinutes: { min: 30, max: 90 },
    howTo: [
      { order: 1, text: "Step one." },
      { order: 2, text: "Step two." },
      { order: 3, text: "Step three." },
    ],
    realInconveniences: [{ category: "crowds", text: "Busy on weekends." }],
    soloScore: {
      overall: 8,
      breakdown: {
        seatingFriendly: 8,
        soloPatronRatio: 8,
        staffPressure: 8,
        soloPortioning: 8,
        ambianceFit: 8,
        safety: 8,
      },
      basedOnCount: 5,
    },
    sources: [{ type: "blog", verifiedAt: "2024-01-01T00:00:00Z" }],
    confidence: {
      level: 1,
      lastVerifiedAt: "2024-01-01T00:00:00Z",
      reason: "AI-scraped.",
      signals: {
        aiScrapeAgeDays: 0,
        passiveGpsHits30d: 0,
        activeReports30d: 0,
        trustedVerifications: 0,
      },
    },
    nearbyExperienceIds: [],
    stats: { completionCount: 0, averageRating: 0 },
    status: "active",
    createdAt: "2024-01-01T00:00:00Z",
    updatedAt: "2024-01-01T00:00:00Z",
  };
}

function makeMockClient(
  rankedItems: Array<{ experienceId: string; score: number; reason: string }>,
): OpenAI {
  const content = JSON.stringify({ ranked: rankedItems });
  return {
    chat: {
      completions: {
        create: vi.fn().mockResolvedValue({
          choices: [{ message: { content } }],
          usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 },
          model: "deepseek-v4-pro",
        }),
      },
    },
  } as unknown as OpenAI;
}

const BASE_INPUT = {
  userLocation: [100.0, 18.0] as [number, number],
  userIntent: "something quiet to do",
  currentHour: 14,
};

// ─── Tests ────────────────────────────────────────────────────────────────────

describe("rankExperiences — anti-hallucination", () => {
  it("never invents IDs: model returns unknown id → omitted from result", async () => {
    const realExp = makeExperience("exp_cmi_real", "Real Experience");
    const mockClient = makeMockClient([
      { experienceId: "exp_cmi_invented_fake_id", score: 95, reason: "Hallucinated." },
      { experienceId: "exp_cmi_real", score: 80, reason: "Legit match." },
    ]);

    const result = await rankExperiences(
      { ...BASE_INPUT, availableExperiences: [realExp] },
      mockClient,
    );

    const ids = result.ranked.map((r) => r.experience.id as string);
    expect(ids).not.toContain("exp_cmi_invented_fake_id");
    expect(ids).toContain("exp_cmi_real");
  });

  it("clamps score above 100 down to 100", async () => {
    const exp = makeExperience("exp_cmi_a", "Experience A");
    const mockClient = makeMockClient([
      { experienceId: "exp_cmi_a", score: 150, reason: "Over the top." },
    ]);

    const result = await rankExperiences(
      { ...BASE_INPUT, availableExperiences: [exp] },
      mockClient,
    );

    expect(result.ranked).toHaveLength(1);
    expect(result.ranked[0]?.score).toBe(100);
  });

  it("clamps score below 0 up to 0", async () => {
    const exp = makeExperience("exp_cmi_b", "Experience B");
    const mockClient = makeMockClient([
      { experienceId: "exp_cmi_b", score: -10, reason: "Negative score." },
    ]);

    const result = await rankExperiences(
      { ...BASE_INPUT, availableExperiences: [exp] },
      mockClient,
    );

    expect(result.ranked).toHaveLength(1);
    expect(result.ranked[0]?.score).toBe(0);
  });

  it("returns at most 3 items even when model returns 5", async () => {
    const experiences = Array.from({ length: 5 }, (_, i) =>
      makeExperience(`exp_cmi_${i}`, `Experience ${i}`),
    );
    const mockClient = makeMockClient(
      experiences.map((e, i) => ({
        experienceId: e.id as string,
        score: 90 - i * 5,
        reason: `Reason ${i}.`,
      })),
    );

    const result = await rankExperiences(
      { ...BASE_INPUT, availableExperiences: experiences },
      mockClient,
    );

    expect(result.ranked.length).toBeLessThanOrEqual(3);
  });

  it("returns empty ranked array for empty availableExperiences without calling DeepSeek", async () => {
    const createMock = vi.fn();
    const mockClient = {
      chat: { completions: { create: createMock } },
    } as unknown as OpenAI;

    const result = await rankExperiences({ ...BASE_INPUT, availableExperiences: [] }, mockClient);

    expect(result.ranked).toHaveLength(0);
    expect(createMock).not.toHaveBeenCalled();
  });

  it("passes reason string through unchanged", async () => {
    const exp = makeExperience("exp_cmi_quiet", "Quiet Garden");
    const expectedReason = "Perfect for your quiet afternoon";
    const mockClient = makeMockClient([
      { experienceId: "exp_cmi_quiet", score: 88, reason: expectedReason },
    ]);

    const result = await rankExperiences(
      { ...BASE_INPUT, availableExperiences: [exp] },
      mockClient,
    );

    expect(result.ranked).toHaveLength(1);
    expect(result.ranked[0]?.reason).toBe(expectedReason);
  });

  it("handles fence-wrapped JSON response gracefully", async () => {
    const exp = makeExperience("exp_cmi_fence", "Fence Test");
    const content =
      '```json\n{"ranked":[{"experienceId":"exp_cmi_fence","score":75,"reason":"Good match."}]}\n```';
    const mockClient = {
      chat: {
        completions: {
          create: vi.fn().mockResolvedValue({
            choices: [{ message: { content } }],
            usage: { prompt_tokens: 50, completion_tokens: 25, total_tokens: 75 },
            model: "deepseek-v4-pro",
          }),
        },
      },
    } as unknown as OpenAI;

    const result = await rankExperiences(
      { ...BASE_INPUT, availableExperiences: [exp] },
      mockClient,
    );

    expect(result.ranked).toHaveLength(1);
    expect(result.ranked[0]?.score).toBe(75);
  });

  it("returns empty ranked array when response is invalid JSON", async () => {
    const exp = makeExperience("exp_cmi_bad", "Bad JSON Test");
    const mockClient = {
      chat: {
        completions: {
          create: vi.fn().mockResolvedValue({
            choices: [{ message: { content: "not json at all" } }],
            usage: { prompt_tokens: 50, completion_tokens: 10, total_tokens: 60 },
            model: "deepseek-v4-pro",
          }),
        },
      },
    } as unknown as OpenAI;

    const result = await rankExperiences(
      { ...BASE_INPUT, availableExperiences: [exp] },
      mockClient,
    );

    expect(result.ranked).toHaveLength(0);
  });
});
