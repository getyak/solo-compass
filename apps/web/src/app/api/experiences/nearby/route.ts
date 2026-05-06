/**
 * GET /api/experiences/nearby
 *
 * Query params:
 *   lng     — required, [-180, 180]
 *   lat     — required, [-90, 90]
 *   intent  — optional free-text. If provided, we ask the AI ranker to score
 *             top-3 by intent fit. If omitted, we sort by soloScore.
 *   radius  — optional meters. Default 1500. Max 10000.
 *
 * Response:
 *   { results: NearbyResult[], degraded?: true }
 *
 * `degraded: true` means the AI ranker failed (no key, network error, etc.)
 * and we fell back to soloScore sorting. The UI keeps working.
 */

import { NextResponse } from "next/server";
import { z } from "zod";
import { rankExperiences } from "@solo-compass/ai";
import {
  type Experience,
  distanceMeters,
  walkingMinutes,
  healthFromConfidence,
  type HealthStatus,
} from "@solo-compass/core";
import { getExperiencesRepo } from "@/lib/repos";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const QuerySchema = z.object({
  lng: z.coerce.number().min(-180).max(180),
  lat: z.coerce.number().min(-90).max(90),
  intent: z.string().trim().min(1).max(280).optional(),
  radius: z.coerce.number().int().min(100).max(10_000).default(1500),
});

export interface NearbyResult {
  readonly experience: Experience;
  readonly reason: string;
  readonly score: number;
  readonly walkingMinutes: number;
  readonly health: HealthStatus;
}

export interface NearbyResponse {
  readonly results: readonly NearbyResult[];
  readonly degraded?: true;
}

const MAX_RESULTS = 5;

function fallbackRank(
  experiences: readonly Experience[],
  center: readonly [number, number],
): NearbyResult[] {
  return experiences
    .map((exp) => {
      const meters = distanceMeters(center, exp.location.coordinates);
      const walkMin = walkingMinutes(meters);
      // Composite: soloScore weighted higher, distance mildly penalising.
      const distancePenalty = Math.min(30, walkMin); // 0–30 cap
      const score = Math.max(0, exp.soloScore.overall * 10 - distancePenalty);
      return {
        experience: exp,
        reason: exp.soloScore.hint ?? exp.oneLiner,
        score,
        walkingMinutes: walkMin,
        health: healthFromConfidence(exp.confidence),
      };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, MAX_RESULTS);
}

export async function GET(
  request: Request,
): Promise<NextResponse<NearbyResponse | { error: string }>> {
  const url = new URL(request.url);
  const parsed = QuerySchema.safeParse({
    lng: url.searchParams.get("lng"),
    lat: url.searchParams.get("lat"),
    intent: url.searchParams.get("intent") ?? undefined,
    radius: url.searchParams.get("radius") ?? undefined,
  });

  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ") },
      { status: 400 },
    );
  }

  const { lng, lat, intent, radius } = parsed.data;
  const center = [lng, lat] as const;

  let candidates: Experience[];
  try {
    const repo = getExperiencesRepo();
    candidates = await repo.findNearby({ center, radiusMeters: radius, limit: 30 });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error("findNearby failed", err);
    return NextResponse.json({ error: "experience lookup failed" }, { status: 502 });
  }

  if (candidates.length === 0) {
    return NextResponse.json({ results: [] });
  }

  // No intent → straightforward distance/score sort, no AI call.
  if (!intent) {
    return NextResponse.json({ results: fallbackRank(candidates, center) });
  }

  // Intent provided → ask the ranker to pick the top 3.
  try {
    const currentHour = new Date().getUTCHours(); // approximate; per-city local time deferred
    const ranked = await rankExperiences({
      userLocation: center,
      userIntent: intent,
      availableExperiences: candidates,
      currentHour,
    });
    if (ranked.ranked.length === 0) {
      return NextResponse.json({ results: fallbackRank(candidates, center), degraded: true });
    }
    const results: NearbyResult[] = ranked.ranked.slice(0, MAX_RESULTS).map((r) => ({
      experience: r.experience,
      reason: r.reason,
      score: r.score,
      walkingMinutes: r.walkingMinutes,
      health: healthFromConfidence(r.experience.confidence),
    }));
    return NextResponse.json({ results });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error("rankExperiences failed, falling back to soloScore", err);
    return NextResponse.json({ results: fallbackRank(candidates, center), degraded: true });
  }
}
