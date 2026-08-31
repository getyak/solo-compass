import { describe, expect, it } from "vitest";
import { planWorkdayRoute } from "./solver";
import type { RouteCandidate, TravelTimeMatrix, WorkdayPlanIntent } from "./types";

function candidate(id: string, options: Partial<RouteCandidate> = {}): RouteCandidate {
  return {
    id,
    experienceId: `exp-${id}`,
    title: id,
    utility: 0.8,
    operatingStatus: "active",
    openingHours: { status: "known", windows: [{ startMinute: 8 * 60, endMinute: 20 * 60 }] },
    features: {},
    ...options,
  };
}

function matrix(values: Record<string, Record<string, number | null>>): TravelTimeMatrix {
  return {
    mode: "pedestrian",
    cells: Object.fromEntries(
      Object.entries(values).map(([from, row]) => [
        from,
        Object.fromEntries(
          Object.entries(row).map(([to, durationMinutes]) => [to, { durationMinutes }]),
        ),
      ]),
    ),
  };
}

describe("planWorkdayRoute", () => {
  it("satisfies task and opening windows before optimizing utility", () => {
    const intent: WorkdayPlanIntent = {
      originNodeId: "origin",
      startMinute: 8 * 60,
      endMinute: 18 * 60,
      tasks: [
        {
          id: "focus",
          kind: "deep_work",
          durationMinutes: 120,
          latestEndMinute: 12 * 60,
          candidateIds: ["late", "desk"],
        },
        {
          id: "call",
          kind: "video_call",
          durationMinutes: 60,
          earliestStartMinute: 14 * 60,
          latestEndMinute: 16 * 60,
          candidateIds: ["call"],
          constraints: [{ featureKey: "work.video_call", operator: "eq", expected: true }],
        },
      ],
    };
    const result = planWorkdayRoute(
      intent,
      [
        candidate("late", {
          utility: 1,
          openingHours: {
            status: "known",
            windows: [{ startMinute: 11 * 60, endMinute: 20 * 60 }],
          },
        }),
        candidate("desk", { utility: 0.7 }),
        candidate("call", {
          features: { "work.video_call": { value: true, status: "resolved", confidence: 0.9 } },
        }),
      ],
      matrix({
        origin: { late: 5, desk: 10, call: 12 },
        late: { call: 5 },
        desk: { call: 10 },
      }),
    );
    expect(result.status).toBe("solved");
    if (result.status !== "solved") return;
    expect(result.solution.stops.map((stop) => stop.candidateId)).toEqual(["desk", "call"]);
    expect(result.solution.stops[1]?.startMinute).toBe(14 * 60);
    expect(result.solution.totalWaitMinutes).toBeGreaterThan(0);
  });

  it("never uses confirmed-closed or hard-constraint candidates", () => {
    const result = planWorkdayRoute(
      {
        originNodeId: "origin",
        startMinute: 9 * 60,
        endMinute: 17 * 60,
        tasks: [
          {
            id: "call",
            kind: "video_call",
            durationMinutes: 60,
            candidateIds: ["closed", "no-power"],
            constraints: [{ featureKey: "work.power", operator: "eq", expected: true }],
          },
        ],
      },
      [
        candidate("closed", {
          operatingStatus: "permanently_closed",
          features: { "work.power": { value: true, status: "resolved", confidence: 1 } },
        }),
        candidate("no-power", {
          features: { "work.power": { value: false, status: "resolved", confidence: 1 } },
        }),
      ],
      matrix({ origin: { closed: 2, "no-power": 2 } }),
    );
    expect(result).toMatchObject({
      status: "unsatisfiable",
      failedTaskId: "call",
    });
    if (result.status !== "unsatisfiable") return;
    expect(result.rejections).toEqual(
      expect.arrayContaining([
        { code: "confirmed_closed", count: 1 },
        { code: "hard_constraint_unmet", count: 1 },
      ]),
    );
  });

  it("does not promote low-confidence evidence into a hard route decision", () => {
    const result = planWorkdayRoute(
      {
        originNodeId: "origin",
        startMinute: 9 * 60,
        endMinute: 17 * 60,
        tasks: [
          {
            id: "call",
            kind: "video_call",
            durationMinutes: 60,
            candidateIds: ["single-report"],
            constraints: [
              {
                featureKey: "work.video_call",
                operator: "eq",
                expected: true,
                minimumConfidence: 0.6,
              },
            ],
          },
        ],
      },
      [
        candidate("single-report", {
          features: { "work.video_call": { value: true, status: "resolved", confidence: 0.36 } },
        }),
      ],
      matrix({ origin: { "single-report": 5 } }),
    );
    expect(result).toMatchObject({ status: "unsatisfiable" });
    if (result.status !== "unsatisfiable") return;
    expect(result.rejections).toContainEqual({ code: "hard_constraint_unmet", count: 1 });
  });

  it("uses network travel times and does not invent a missing leg", () => {
    const intent: WorkdayPlanIntent = {
      originNodeId: "origin",
      startMinute: 9 * 60,
      endMinute: 17 * 60,
      tasks: [{ id: "work", kind: "deep_work", durationMinutes: 60 }],
    };
    const result = planWorkdayRoute(
      intent,
      [candidate("near-but-slow", { utility: 0.9 }), candidate("far-but-fast", { utility: 0.8 })],
      matrix({ origin: { "near-but-slow": 50, "far-but-fast": 5 } }),
    );
    expect(result.status).toBe("solved");
    if (result.status !== "solved") return;
    expect(result.solution.stops[0]?.candidateId).toBe("far-but-fast");

    const missing = planWorkdayRoute(
      { ...intent, tasks: [{ ...intent.tasks[0]!, candidateIds: ["near-but-slow"] }] },
      [candidate("near-but-slow")],
      matrix({ origin: {} }),
    );
    expect(missing).toMatchObject({ status: "unsatisfiable" });
  });

  it("keeps unknown hours distinct and only uses them when policy allows", () => {
    const unknown = candidate("unknown", { openingHours: { status: "unknown" } });
    const base: WorkdayPlanIntent = {
      originNodeId: "origin",
      startMinute: 9 * 60,
      endMinute: 17 * 60,
      tasks: [{ id: "work", kind: "deep_work", durationMinutes: 60 }],
    };
    expect(planWorkdayRoute(base, [unknown], matrix({ origin: { unknown: 5 } }))).toMatchObject({
      status: "unsatisfiable",
    });
    const allowed = planWorkdayRoute(
      { ...base, allowUnknownOpeningHours: true },
      [unknown],
      matrix({ origin: { unknown: 5 } }),
    );
    expect(allowed.status).toBe("solved");
    if (allowed.status !== "solved") return;
    expect(allowed.solution.warnings.map((warning) => warning.code)).toContain(
      "opening_hours_unknown",
    );
  });

  it("prepares a fallback that preserves the next hard appointment", () => {
    const result = planWorkdayRoute(
      {
        originNodeId: "origin",
        startMinute: 9 * 60,
        endMinute: 17 * 60,
        fallbackMaxExtraTravelMinutes: 10,
        tasks: [
          {
            id: "focus",
            kind: "deep_work",
            durationMinutes: 60,
            candidateIds: ["primary", "backup"],
          },
          {
            id: "call",
            kind: "video_call",
            durationMinutes: 30,
            earliestStartMinute: 11 * 60,
            latestEndMinute: 12 * 60,
            candidateIds: ["call"],
          },
        ],
      },
      [
        candidate("primary", { utility: 0.9 }),
        candidate("backup", { utility: 0.7 }),
        candidate("call", { utility: 0.8 }),
      ],
      matrix({
        origin: { primary: 5, backup: 8, call: 20 },
        primary: { call: 5 },
        backup: { call: 7 },
      }),
    );
    expect(result.status).toBe("solved");
    if (result.status !== "solved") return;
    expect(result.solution.stops[0]?.candidateId).toBe("primary");
    expect(result.solution.fallbacks).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          primaryCandidateId: "primary",
          candidateId: "backup",
          extraTravelMinutes: 5,
        }),
      ]),
    );
  });

  it("enforces the whole-day money budget", () => {
    const result = planWorkdayRoute(
      {
        originNodeId: "origin",
        startMinute: 9 * 60,
        endMinute: 17 * 60,
        budget: { maxAmount: 10, currency: "USD" },
        tasks: [{ id: "meal", kind: "meal", durationMinutes: 60 }],
      },
      [
        candidate("expensive", {
          estimatedSpend: { status: "known", amount: 20, currency: "USD" },
        }),
      ],
      matrix({ origin: { expensive: 5 } }),
    );
    expect(result).toMatchObject({ status: "unsatisfiable" });
    if (result.status !== "unsatisfiable") return;
    expect(result.rejections).toContainEqual({ code: "money_budget", count: 1 });
  });

  it("does not pretend an unknown spend is free under a hard budget", () => {
    const result = planWorkdayRoute(
      {
        originNodeId: "origin",
        startMinute: 9 * 60,
        endMinute: 17 * 60,
        budget: { maxAmount: 10, currency: "USD" },
        tasks: [{ id: "meal", kind: "meal", durationMinutes: 60 }],
      },
      [candidate("unknown-price")],
      matrix({ origin: { "unknown-price": 5 } }),
    );
    expect(result).toMatchObject({ status: "unsatisfiable" });
    if (result.status !== "unsatisfiable") return;
    expect(result.rejections).toContainEqual({ code: "money_budget_unknown", count: 1 });
  });
});
