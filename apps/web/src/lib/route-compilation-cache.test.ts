import { describe, expect, it } from "vitest";
import {
  cachedRoutePayload,
  routeCacheExpiry,
  routeFingerprint,
  toJsonValue,
  type CachedRoutePayload,
} from "./route-compilation-cache";

const solvedPayload: CachedRoutePayload = {
  result: {
    status: "solved",
    solution: {
      stops: [],
      fallbacks: [],
      score: 0,
      totalTravelMinutes: 0,
      totalWaitMinutes: 0,
      budgetEstimateIncomplete: false,
      startsAtMinute: 540,
      endsAtMinute: 540,
      warnings: [],
      solver: { version: "test", exploredStates: 1, beamWidth: 1, matrixMode: "pedestrian" },
    },
  },
  evidenceCoverage: "fresh",
  refreshScheduled: false,
};

describe("route compilation cache", () => {
  it("fingerprints object keys canonically while preserving array order", () => {
    expect(routeFingerprint({ b: 2, a: [1, 2] })).toBe(routeFingerprint({ a: [1, 2], b: 2 }));
    expect(routeFingerprint({ a: [1, 2], b: 2 })).not.toBe(routeFingerprint({ a: [2, 1], b: 2 }));
  });

  it("uses short TTLs for partial evidence and auto matrices", () => {
    const now = new Date("2026-08-31T12:00:00.000Z");
    expect(
      routeCacheExpiry({
        now,
        mode: "pedestrian",
        resultStatus: "solved",
        evidenceCoverage: "partial",
      }),
    ).toBe("2026-08-31T12:05:00.000Z");
    expect(
      routeCacheExpiry({
        now,
        mode: "auto",
        resultStatus: "solved",
        evidenceCoverage: "fresh",
      }),
    ).toBe("2026-08-31T12:10:00.000Z");
  });

  it("round-trips a trusted compiler payload and rejects unrelated JSON", () => {
    expect(cachedRoutePayload(toJsonValue(solvedPayload))).toEqual(solvedPayload);
    expect(cachedRoutePayload({ status: "solved" })).toBeNull();
  });
});
