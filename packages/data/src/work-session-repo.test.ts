import { describe, expect, it } from "vitest";
import { FEATURE_KEYS } from "./evidence";
import type { WorkSessionRow } from "./db";
import { deriveWorkSessionObservations } from "./work-session-repo";

function session(overrides: Partial<WorkSessionRow> = {}): WorkSessionRow {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    user_id: "22222222-2222-4222-8222-222222222222",
    experience_id: "exp-cafe",
    place_id: "33333333-3333-4333-8333-333333333333",
    planned_task_kind: "video_call",
    started_at: "2026-08-31T06:00:00.000Z",
    ended_at: "2026-08-31T07:00:00.000Z",
    outcome: "completed",
    failure_reason: null,
    place_was_open: true,
    wifi_reliability: 4,
    noise_level: 2,
    power_available: true,
    video_call_worked: true,
    long_stay_accepted: true,
    minimum_spend_amount: 120,
    minimum_spend_currency: "THB",
    idempotency_key: "device-session-1",
    created_at: "2026-08-31T07:00:00.000Z",
    ...overrides,
  };
}

describe("deriveWorkSessionObservations", () => {
  it("derives bounded first-party facts without exposing the user id", () => {
    const observations = deriveWorkSessionObservations(session());
    expect(observations.map((observation) => observation.featureKey)).toEqual(
      expect.arrayContaining([
        FEATURE_KEYS.openOnArrival,
        FEATURE_KEYS.wifiReliability,
        FEATURE_KEYS.noiseLevel,
        FEATURE_KEYS.powerOutlets,
        FEATURE_KEYS.videoCallFit,
        FEATURE_KEYS.longStayPolicy,
        FEATURE_KEYS.minimumSpend,
      ]),
    );
    expect(observations).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          featureKey: FEATURE_KEYS.minimumSpend,
          value: { amount: 120, currency: "THB" },
          confidence: 0.95,
        }),
      ]),
    );
    expect(JSON.stringify(observations)).not.toContain("22222222-2222-4222-8222-222222222222");
  });

  it("turns a structured failure reason into a conservative observation", () => {
    const observations = deriveWorkSessionObservations(
      session({
        outcome: "abandoned",
        failure_reason: "wifi_unreliable",
        wifi_reliability: null,
      }),
    );
    expect(observations).toContainEqual(
      expect.objectContaining({
        featureKey: FEATURE_KEYS.wifiReliability,
        value: 1,
        confidence: 0.75,
      }),
    );
  });

  it("collapses repeated sessions from one traveler into one independent origin", () => {
    const first = deriveWorkSessionObservations(session());
    const second = deriveWorkSessionObservations(
      session({ id: "44444444-4444-4444-8444-444444444444" }),
    );
    expect(first[0]?.independenceKey).toBe(second[0]?.independenceKey);
    expect(first[0]?.sourceWeight).toBe(0.6);
    expect(first[0]?.independenceKey).not.toContain("22222222-2222-4222-8222-222222222222");
  });
});
