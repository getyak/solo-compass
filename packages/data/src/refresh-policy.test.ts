import { describe, expect, it } from "vitest";
import { FEATURE_KEYS, type ResolvedPlaceFeature } from "./evidence";
import {
  calculateRefreshPriority,
  decideFeatureRefresh,
  makeRefreshIdempotencyKey,
} from "./refresh-policy";

function feature(
  status: ResolvedPlaceFeature["status"],
  freshUntil = "2026-09-01T00:00:00.000Z",
): ResolvedPlaceFeature {
  return {
    placeId: "place",
    featureKey: FEATURE_KEYS.regularOpeningHours,
    value: "Mon-Fri 08:00-18:00",
    status,
    confidence: 0.8,
    latestObservedAt: "2026-08-30T00:00:00.000Z",
    freshUntil,
    supportingObservationIds: ["obs"],
    conflictingObservationIds: [],
    resolverVersion: "test",
    resolutionFingerprint: "test",
    resolvedAt: "2026-08-31T00:00:00.000Z",
  };
}

describe("refresh policy", () => {
  it("prioritizes high-impact uncertain evidence within a bounded score", () => {
    expect(
      calculateRefreshPriority({
        demandScore: 0.9,
        decisionImpact: 1,
        uncertainty: 0.8,
        staleness: 1,
        estimatedCost: 0.1,
        urgency: "interactive",
      }),
    ).toBe(1000);
    expect(
      calculateRefreshPriority({
        demandScore: 0.2,
        decisionImpact: 0.2,
        uncertainty: 0.2,
        staleness: 0.2,
        estimatedCost: 1,
        urgency: "background",
      }),
    ).toBe(0);
  });

  it("serves fresh materialized evidence without external work", () => {
    expect(
      decideFeatureRefresh({
        feature: feature("resolved"),
        hardConstraint: true,
        viableAlternativeCount: 0,
        now: "2026-08-31T00:00:00.000Z",
      }),
    ).toMatchObject({ action: "none", enqueue: false });
  });

  it("blocks only when a hard constraint has no viable fallback", () => {
    expect(
      decideFeatureRefresh({
        feature: feature("stale", "2026-08-01T00:00:00.000Z"),
        hardConstraint: true,
        viableAlternativeCount: 0,
        now: "2026-08-31T00:00:00.000Z",
      }),
    ).toMatchObject({ action: "blocking", enqueue: true, reason: "hard_constraint" });
  });

  it("excludes stale hard-constraint candidates when a fallback exists", () => {
    expect(
      decideFeatureRefresh({
        feature: feature("conflicted"),
        hardConstraint: true,
        viableAlternativeCount: 2,
        now: "2026-08-31T00:00:00.000Z",
      }),
    ).toMatchObject({ action: "exclude", enqueue: true });
  });

  it("deduplicates refresh jobs by sorted fields and time bucket", () => {
    const first = makeRefreshIdempotencyKey({
      placeId: "place",
      featureKeys: [FEATURE_KEYS.videoCallFit, FEATURE_KEYS.regularOpeningHours],
      reason: "hard_constraint",
      now: "2026-08-31T12:12:00.000Z",
    });
    const second = makeRefreshIdempotencyKey({
      placeId: "place",
      featureKeys: [FEATURE_KEYS.regularOpeningHours, FEATURE_KEYS.videoCallFit],
      reason: "hard_constraint",
      now: "2026-08-31T12:55:00.000Z",
    });
    expect(first).toBe(second);
  });
});
