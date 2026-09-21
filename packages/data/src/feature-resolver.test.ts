import { describe, expect, it } from "vitest";
import { FEATURE_KEYS, type EvidenceObservation, type JsonValue } from "./evidence";
import { resolveFeature } from "./feature-resolver";

const PLACE_ID = "11111111-1111-4111-8111-111111111111";
const NOW = "2026-08-31T12:00:00.000Z";

function observation(
  id: string,
  value: JsonValue | undefined,
  overrides: Partial<EvidenceObservation> = {},
): EvidenceObservation {
  return {
    id,
    placeId: PLACE_ID,
    featureKey: FEATURE_KEYS.videoCallFit,
    state: value === undefined ? "reported_unknown" : "observed",
    value,
    confidence: 0.9,
    sourceWeight: 0.8,
    independenceKey: `origin-${id}`,
    observedAt: "2026-08-30T12:00:00.000Z",
    ...overrides,
  };
}

describe("resolveFeature", () => {
  it("materializes corroborated independent evidence", () => {
    const resolved = resolveFeature({
      placeId: PLACE_ID,
      featureKey: FEATURE_KEYS.videoCallFit,
      observations: [observation("a", true), observation("b", true)],
      now: NOW,
    });

    expect(resolved.status).toBe("resolved");
    expect(resolved.value).toBe(true);
    expect(resolved.supportingObservationIds).toEqual(["a", "b"]);
    expect(resolved.conflictingObservationIds).toEqual([]);
    expect(resolved.confidence).toBeGreaterThan(0.8);
    expect(resolved.resolutionFingerprint).toMatch(/^fnv1a-/);
  });

  it("collapses updates and reposts that share an independence key", () => {
    const resolved = resolveFeature({
      placeId: PLACE_ID,
      featureKey: FEATURE_KEYS.videoCallFit,
      observations: [
        observation("old", true, {
          independenceKey: "merchant-page",
          observedAt: "2026-08-01T12:00:00.000Z",
        }),
        observation("new", false, {
          independenceKey: "merchant-page",
          observedAt: "2026-08-30T12:00:00.000Z",
        }),
        observation("visitor", false, { independenceKey: "work-session:visitor" }),
      ],
      now: NOW,
    });

    expect(resolved.status).toBe("resolved");
    expect(resolved.value).toBe(false);
    expect(resolved.supportingObservationIds).toEqual(["new", "visitor"]);
    expect(resolved.supportingObservationIds).not.toContain("old");
  });

  it("preserves a meaningful conflict instead of silently choosing a truth", () => {
    const resolved = resolveFeature({
      placeId: PLACE_ID,
      featureKey: FEATURE_KEYS.noiseLevel,
      observations: [
        observation("quiet", 1, {
          featureKey: FEATURE_KEYS.noiseLevel,
          observedAt: "2026-08-30T13:00:00.000Z",
        }),
        observation("loud", 5, {
          featureKey: FEATURE_KEYS.noiseLevel,
          observedAt: "2026-08-30T12:00:00.000Z",
        }),
      ],
      now: NOW,
    });

    expect(resolved.status).toBe("conflicted");
    expect(resolved.value).toBe(1);
    expect(resolved.supportingObservationIds).toEqual(["quiet"]);
    expect(resolved.conflictingObservationIds).toEqual(["loud"]);
    expect(resolved.conflictDetails?.alternatives[0]?.value).toBe(5);
  });

  it("serves the last known value as stale instead of erasing it", () => {
    const resolved = resolveFeature({
      placeId: PLACE_ID,
      featureKey: FEATURE_KEYS.longStayPolicy,
      observations: [
        observation("old-policy", "two_hours", {
          featureKey: FEATURE_KEYS.longStayPolicy,
          observedAt: "2026-01-01T12:00:00.000Z",
          expiresAt: "2026-01-15T12:00:00.000Z",
        }),
      ],
      now: NOW,
    });

    expect(resolved.status).toBe("stale");
    expect(resolved.value).toBe("two_hours");
    expect(resolved.freshUntil).toBe("2026-01-15T12:00:00.000Z");
  });

  it("uses a weighted median for noisy numeric measurements", () => {
    const resolved = resolveFeature({
      placeId: PLACE_ID,
      featureKey: FEATURE_KEYS.wifiSpeedMbps,
      observations: [
        observation("speed-20", 20, {
          featureKey: FEATURE_KEYS.wifiSpeedMbps,
          confidence: 1,
          sourceWeight: 1,
        }),
        observation("speed-30", 30, {
          featureKey: FEATURE_KEYS.wifiSpeedMbps,
          confidence: 1,
          sourceWeight: 1,
        }),
        observation("speed-100", 100, {
          featureKey: FEATURE_KEYS.wifiSpeedMbps,
          confidence: 0.3,
          sourceWeight: 1,
        }),
      ],
      now: NOW,
    });

    expect(resolved.value).toBe(30);
    expect(resolved.status).toBe("resolved");
    expect(resolved.supportingObservationIds).toEqual(["speed-20", "speed-30"]);
  });

  it("resolves minimum spend within one currency and preserves currency conflicts", () => {
    const resolved = resolveFeature({
      placeId: PLACE_ID,
      featureKey: FEATURE_KEYS.minimumSpend,
      observations: [
        observation(
          "usd-8",
          { amount: 8, currency: "USD" },
          {
            featureKey: FEATURE_KEYS.minimumSpend,
            confidence: 1,
            sourceWeight: 1,
          },
        ),
        observation(
          "usd-9",
          { amount: 9, currency: "usd" },
          {
            featureKey: FEATURE_KEYS.minimumSpend,
            confidence: 1,
            sourceWeight: 1,
          },
        ),
        observation(
          "eur-7",
          { amount: 7, currency: "EUR" },
          {
            featureKey: FEATURE_KEYS.minimumSpend,
            confidence: 0.8,
            sourceWeight: 1,
          },
        ),
        observation(
          "eur-8",
          { amount: 8, currency: "EUR" },
          {
            featureKey: FEATURE_KEYS.minimumSpend,
            confidence: 0.8,
            sourceWeight: 1,
          },
        ),
      ],
      now: NOW,
    });

    expect(resolved.value).toEqual({ amount: 8, currency: "USD" });
    expect(resolved.status).toBe("conflicted");
    expect(resolved.supportingObservationIds).toEqual(["usd-8", "usd-9"]);
    expect(resolved.conflictingObservationIds).toContain("eur-7");
  });

  it("keeps explicit unknown distinct from a negative assertion", () => {
    const resolved = resolveFeature({
      placeId: PLACE_ID,
      featureKey: FEATURE_KEYS.powerOutlets,
      observations: [observation("unknown", undefined, { featureKey: FEATURE_KEYS.powerOutlets })],
      now: NOW,
    });

    expect(resolved.status).toBe("unknown");
    expect(resolved.value).toBeUndefined();
    expect(resolved.supportingObservationIds).toEqual(["unknown"]);
  });

  it("rejects invalid trust weights instead of materializing misleading data", () => {
    expect(() =>
      resolveFeature({
        placeId: PLACE_ID,
        featureKey: FEATURE_KEYS.videoCallFit,
        observations: [observation("bad", true, { confidence: 1.2 })],
        now: NOW,
      }),
    ).toThrow("observation.confidence must be between 0 and 1");
  });
});
