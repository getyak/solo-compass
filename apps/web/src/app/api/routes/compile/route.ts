import { NextResponse } from "next/server";
import { z } from "zod";
import {
  FEATURE_KEYS,
  type EnqueueRefreshInput,
  type ExperienceEvidenceSnapshot,
  type JsonValue,
} from "@solo-compass/data";
import {
  planWorkdayRoute,
  ValhallaMatrixClient,
  type RouteTask,
  type WorkdayPlanIntent,
} from "@solo-compass/routing";
import { coverageRefreshJob } from "@/lib/evidence-refresh";
import { getServerEnv } from "@/lib/env";
import {
  authenticatedUserId,
  getEvidenceRepo,
  getExperiencesRepo,
  getRouteCompilationRepo,
} from "@/lib/repos";
import { compileRouteCandidates, withDefaultTaskCandidatePools } from "@/lib/route-candidates";
import {
  cachedRoutePayload,
  ROUTE_COMPILER_CACHE_VERSION,
  routeCacheExpiry,
  routeFingerprint,
  toJsonValue,
  type CachedRoutePayload,
} from "@/lib/route-compilation-cache";
import { scheduleRefreshJobs } from "@/lib/refresh-scheduler";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const JsonValueSchema: z.ZodType<JsonValue> = z.lazy(() =>
  z.union([
    z.string(),
    z.number(),
    z.boolean(),
    z.null(),
    z.array(JsonValueSchema),
    z.record(JsonValueSchema),
  ]),
);

const ConstraintSchema = z.object({
  featureKey: z.string().trim().min(1).max(100),
  operator: z.enum(["eq", "gte", "lte", "in", "contains", "truthy"]),
  expected: JsonValueSchema.optional(),
  hard: z.boolean().optional(),
  acceptableStatuses: z
    .array(z.enum(["resolved", "stale", "conflicted", "unknown"]))
    .max(4)
    .optional(),
  minimumConfidence: z.number().min(0).max(1).default(0.6),
});

const TaskSchema = z.object({
  id: z.string().trim().min(1).max(60),
  kind: z.enum(["deep_work", "video_call", "meal", "explore", "break", "custom"]),
  durationMinutes: z.number().int().min(10).max(480),
  earliestStartMinute: z.number().int().min(0).max(1439).optional(),
  latestEndMinute: z.number().int().min(1).max(1440).optional(),
  candidateIds: z.array(z.string().trim().min(1)).max(30).optional(),
  constraints: z.array(ConstraintSchema).max(12).optional(),
  openingRequirement: z.enum(["known_open", "allow_unknown", "ignore"]).optional(),
});

const RequestSchema = z.object({
  origin: z.tuple([z.number().min(-180).max(180), z.number().min(-90).max(90)]),
  radiusMeters: z.number().int().min(100).max(10_000).default(3_000),
  localDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  mode: z.enum(["pedestrian", "bicycle", "auto"]).default("pedestrian"),
  intent: z.object({
    startMinute: z.number().int().min(0).max(1439),
    endMinute: z.number().int().min(1).max(1440),
    tasks: z.array(TaskSchema).min(1).max(6),
    maxTravelMinutes: z.number().int().positive().max(600).optional(),
    maxWaitMinutes: z.number().int().nonnegative().max(600).optional(),
    budget: z
      .object({
        maxAmount: z.number().nonnegative(),
        currency: z.string().regex(/^[A-Za-z]{3}$/),
      })
      .optional(),
    allowUnknownSpend: z.boolean().optional(),
    allowUnknownOpeningHours: z.boolean().optional(),
    fallbackMaxExtraTravelMinutes: z.number().int().nonnegative().max(60).optional(),
  }),
});

interface CompileRouteResponse extends CachedRoutePayload {
  readonly cache: "hit" | "miss";
}

export async function POST(
  request: Request,
): Promise<NextResponse<CompileRouteResponse | { error: string }>> {
  const body: unknown = await request.json().catch(() => undefined);
  const parsed = RequestSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json(
      {
        error: parsed.error.issues
          .map((issue) => `${issue.path.join(".")}: ${issue.message}`)
          .join("; "),
      },
      { status: 400 },
    );
  }
  const input = parsed.data;
  let serverEnv: ReturnType<typeof getServerEnv>;
  try {
    serverEnv = getServerEnv();
  } catch {
    return NextResponse.json({ error: "route backend is not configured" }, { status: 503 });
  }
  if (!serverEnv.VALHALLA_URL) {
    return NextResponse.json({ error: "routing matrix is not configured" }, { status: 503 });
  }
  const userId = await authenticatedUserId(request);
  if (!userId) return NextResponse.json({ error: "authentication required" }, { status: 401 });

  try {
    const experiences = await getExperiencesRepo().findNearby({
      center: input.origin,
      radiusMeters: input.radiusMeters,
      limit: 30,
    });
    if (experiences.length === 0) {
      scheduleRefreshJobs([
        coverageRefreshJob({ center: input.origin, radiusMeters: input.radiusMeters }),
      ]);
      return NextResponse.json(
        { error: "no route candidates; coverage refresh scheduled" },
        { status: 202 },
      );
    }

    const snapshots = await getEvidenceRepo().getSnapshotsForExperiences(
      experiences.map((experience) => experience.id),
    );
    const dayOfWeek = dayOfWeekForDate(input.localDate);
    const candidates = compileRouteCandidates({ experiences, snapshots, dayOfWeek });
    const tasks = withDefaultTaskCandidatePools(input.intent.tasks as RouteTask[], experiences);
    const intent: WorkdayPlanIntent = {
      originNodeId: "origin",
      startMinute: input.intent.startMinute,
      endMinute: input.intent.endMinute,
      tasks,
      ...(input.intent.maxTravelMinutes !== undefined
        ? { maxTravelMinutes: input.intent.maxTravelMinutes }
        : {}),
      ...(input.intent.maxWaitMinutes !== undefined
        ? { maxWaitMinutes: input.intent.maxWaitMinutes }
        : {}),
      ...(input.intent.budget
        ? {
            budget: {
              maxAmount: input.intent.budget.maxAmount,
              currency: input.intent.budget.currency,
            },
          }
        : {}),
      ...(input.intent.allowUnknownSpend !== undefined
        ? { allowUnknownSpend: input.intent.allowUnknownSpend }
        : {}),
      ...(input.intent.allowUnknownOpeningHours !== undefined
        ? { allowUnknownOpeningHours: input.intent.allowUnknownOpeningHours }
        : {}),
      ...(input.intent.fallbackMaxExtraTravelMinutes !== undefined
        ? { fallbackMaxExtraTravelMinutes: input.intent.fallbackMaxExtraTravelMinutes }
        : {}),
    };
    const refreshJobs = hardConstraintRefreshJobs({
      experiences,
      snapshots,
      tasks,
      budgetRequired: input.intent.budget !== undefined,
      center: input.origin,
      radiusMeters: input.radiusMeters,
    });
    scheduleRefreshJobs(refreshJobs);

    const requestFingerprint = routeFingerprint(input);
    const inputFingerprint = routeFingerprint({ intent, candidates });
    const cacheKey = routeFingerprint({
      compiler: ROUTE_COMPILER_CACHE_VERSION,
      requestFingerprint,
      inputFingerprint,
    });
    const routeCompilations = getRouteCompilationRepo();
    try {
      const cached = await routeCompilations.findFresh(userId, cacheKey);
      const payload = cached ? cachedRoutePayload(cached.plan_payload) : null;
      if (payload) {
        return NextResponse.json(
          { ...payload, cache: "hit" },
          { status: payload.result.status === "solved" ? 200 : 422 },
        );
      }
    } catch (error) {
      console.error("route compilation cache read failed", error);
    }
    if (!(await routeCompilations.consumeQuota(userId))) {
      return NextResponse.json(
        { error: "route compilation hourly limit reached" },
        { status: 429 },
      );
    }

    const matrix = await new ValhallaMatrixClient({ endpoint: serverEnv.VALHALLA_URL }).buildMatrix(
      [
        { id: "origin", coordinates: input.origin },
        ...experiences.map((experience) => ({
          id: experience.id,
          coordinates: [...experience.location.coordinates] as [number, number],
        })),
      ],
      input.mode,
      localDeparture(input.localDate, input.intent.startMinute),
    );
    const result = planWorkdayRoute(intent, candidates, matrix);
    const payload: CachedRoutePayload = {
      result,
      evidenceCoverage: refreshJobs.length === 0 ? "fresh" : "partial",
      refreshScheduled: refreshJobs.length > 0,
    };
    try {
      await routeCompilations.put({
        userId,
        cacheKey,
        requestFingerprint,
        inputFingerprint,
        status: result.status,
        planPayload: toJsonValue(payload),
        expiresAt: routeCacheExpiry({
          mode: input.mode,
          resultStatus: result.status,
          evidenceCoverage: payload.evidenceCoverage,
        }),
      });
    } catch (error) {
      console.error("route compilation cache write failed", error);
    }
    const response: CompileRouteResponse = { ...payload, cache: "miss" };
    return NextResponse.json(response, { status: result.status === "solved" ? 200 : 422 });
  } catch (error) {
    console.error("route compilation failed", error);
    return NextResponse.json({ error: "route compilation failed" }, { status: 502 });
  }
}

function hardConstraintRefreshJobs(input: {
  readonly experiences: readonly import("@solo-compass/core").Experience[];
  readonly snapshots: ReadonlyMap<string, ExperienceEvidenceSnapshot>;
  readonly tasks: readonly RouteTask[];
  readonly budgetRequired: boolean;
  readonly center: readonly [number, number];
  readonly radiusMeters: number;
}): EnqueueRefreshInput[] {
  const requiredKeys = new Map<string, number>([
    [FEATURE_KEYS.operatingStatus, 0],
    [FEATURE_KEYS.regularOpeningHours, 0.4],
  ]);
  for (const task of input.tasks) {
    for (const constraint of task.constraints ?? []) {
      if (constraint.hard ?? true) {
        requiredKeys.set(
          constraint.featureKey,
          Math.max(requiredKeys.get(constraint.featureKey) ?? 0, constraint.minimumConfidence ?? 0),
        );
      }
    }
  }
  if (input.budgetRequired) requiredKeys.set(FEATURE_KEYS.minimumSpend, 0.6);

  const jobs: EnqueueRefreshInput[] = [];
  for (const experience of input.experiences.slice(0, 12)) {
    const snapshot = input.snapshots.get(experience.id);
    if (!snapshot) continue;
    const staleKeys = [...requiredKeys].flatMap(([key, minimumConfidence]) => {
      const feature = snapshot.features.find((candidate) => candidate.feature_key === key);
      return feature?.status !== "resolved" || feature.confidence < minimumConfidence ? [key] : [];
    });
    if (staleKeys.length === 0) continue;
    jobs.push({
      placeId: snapshot.placeId,
      featureKeys: staleKeys,
      query: {
        experienceId: experience.id,
        placeName:
          experience.location.placeNameRomanized ??
          experience.location.placeNameLocal ??
          experience.title,
        coordinates: [...experience.location.coordinates],
      },
      reason: "hard_constraint",
      urgency: "interactive",
      demandScore: 1,
      decisionImpact: 1,
      uncertainty: 1,
      staleness: 1,
      estimatedCost: 0.2,
      budgetClass: "route_decision",
      bucketSeconds: 5 * 60,
    });
  }
  if (input.snapshots.size < input.experiences.length) {
    jobs.push(
      coverageRefreshJob({
        center: input.center,
        radiusMeters: input.radiusMeters,
        experienceAnchors: input.experiences.map((experience) => ({
          experienceId: experience.id,
          placeName:
            experience.location.placeNameRomanized ??
            experience.location.placeNameLocal ??
            experience.title,
          coordinates: experience.location.coordinates,
        })),
      }),
    );
  }
  return jobs;
}

function dayOfWeekForDate(localDate: string): number {
  const date = new Date(`${localDate}T12:00:00Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0, 10) !== localDate) {
    throw new Error("localDate is invalid");
  }
  return date.getUTCDay();
}

function localDeparture(localDate: string, minute: number): string {
  const hours = Math.floor(minute / 60)
    .toString()
    .padStart(2, "0");
  const minutes = (minute % 60).toString().padStart(2, "0");
  return `${localDate}T${hours}:${minutes}`;
}
