import type { Experience } from "@solo-compass/core";
import {
  decideFeatureRefresh,
  FEATURE_KEYS,
  type EnqueueRefreshInput,
  type EvidenceRepo,
  type JsonValue,
  type ResolvedPlaceFeature,
  type ResolvedPlaceFeatureRow,
} from "@solo-compass/data";

const DECISION_FEATURES = [
  { key: FEATURE_KEYS.operatingStatus, impact: 0.9 },
  { key: FEATURE_KEYS.regularOpeningHours, impact: 0.7 },
] as const;
const MAX_PLACES_PER_READ = 10;

export interface EvidenceRefreshPlan {
  readonly coverage: "fresh" | "partial" | "legacy";
  readonly jobs: readonly EnqueueRefreshInput[];
}

export async function planEvidenceRefresh(input: {
  readonly evidenceRepo: EvidenceRepo;
  readonly experiences: readonly Experience[];
  readonly center: readonly [longitude: number, latitude: number];
  readonly radiusMeters: number;
  readonly now?: string;
}): Promise<EvidenceRefreshPlan> {
  const now = input.now ?? new Date().toISOString();
  try {
    const selected = input.experiences.slice(0, MAX_PLACES_PER_READ);
    const snapshots = await input.evidenceRepo.getSnapshotsForExperiences(
      selected.map((experience) => experience.id),
    );
    const jobs: EnqueueRefreshInput[] = [];
    let hasGap = snapshots.size < selected.length;

    selected.forEach((experience, index) => {
      const snapshot = snapshots.get(experience.id);
      if (!snapshot) return;
      const staleKeys: string[] = [];
      let highestImpact = 0;
      let highestUncertainty = 0;
      let highestStaleness = 0;
      for (const definition of DECISION_FEATURES) {
        const row = snapshot.features.find((feature) => feature.feature_key === definition.key);
        const feature = row ? rowToFeature(row) : undefined;
        const decision = decideFeatureRefresh({
          feature,
          hardConstraint: false,
          viableAlternativeCount: Math.max(0, selected.length - 1),
          now,
        });
        if (!decision.enqueue) continue;
        staleKeys.push(definition.key);
        highestImpact = Math.max(highestImpact, definition.impact);
        highestUncertainty = Math.max(highestUncertainty, feature ? 1 - feature.confidence : 1);
        highestStaleness = Math.max(highestStaleness, stalenessScore(feature, now));
      }
      if (staleKeys.length === 0) return;
      hasGap = true;
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
        reason: "soft_stale",
        urgency: "background",
        demandScore: Math.max(0.2, 1 - index / MAX_PLACES_PER_READ),
        decisionImpact: highestImpact,
        uncertainty: highestUncertainty,
        staleness: highestStaleness,
        // Relative acquisition cost used for queue ordering, not a provider bill.
        estimatedCost: 0.2,
        budgetClass: "map_background",
        now,
      });
    });

    if (snapshots.size < selected.length) {
      jobs.push(
        coverageRefreshJob({
          center: input.center,
          radiusMeters: input.radiusMeters,
          experienceAnchors: selected.map((experience) => ({
            experienceId: experience.id,
            placeName:
              experience.location.placeNameRomanized ??
              experience.location.placeNameLocal ??
              experience.title,
            coordinates: experience.location.coordinates,
          })),
          now,
        }),
      );
    }
    return { coverage: hasGap ? "partial" : "fresh", jobs };
  } catch (error) {
    // Deploy-safe shadow mode: an older database can serve legacy Experiences
    // until migration 0014 lands. This is intentionally visible in logs.
    console.warn("evidence refresh planning unavailable; serving legacy snapshot", error);
    return { coverage: "legacy", jobs: [] };
  }
}

export function coverageRefreshJob(input: {
  readonly center: readonly [longitude: number, latitude: number];
  readonly radiusMeters: number;
  readonly experienceAnchors?: readonly {
    readonly experienceId: string;
    readonly placeName: string;
    readonly coordinates: readonly [longitude: number, latitude: number];
  }[];
  readonly now?: string;
}): EnqueueRefreshInput {
  const now = input.now ?? new Date().toISOString();
  return {
    featureKeys: [],
    query: {
      center: [...input.center],
      radiusMeters: input.radiusMeters,
      experienceAnchors: (input.experienceAnchors ?? []).map((anchor) => ({
        experienceId: anchor.experienceId,
        placeName: anchor.placeName,
        coordinates: [...anchor.coordinates],
      })),
    },
    reason: "coverage_gap",
    urgency: "background",
    demandScore: 0.8,
    decisionImpact: 0.7,
    uncertainty: 1,
    staleness: 1,
    estimatedCost: 0.5,
    budgetClass: "coverage_backfill",
    bucketSeconds: 6 * 60 * 60,
    now,
  };
}

function rowToFeature(row: ResolvedPlaceFeatureRow): ResolvedPlaceFeature {
  const base = {
    placeId: row.place_id,
    featureKey: row.feature_key,
    status: row.status,
    confidence: row.confidence,
    supportingObservationIds: row.supporting_observation_ids,
    conflictingObservationIds: row.conflicting_observation_ids,
    resolverVersion: row.resolver_version,
    resolutionFingerprint: row.resolution_fingerprint,
    resolvedAt: row.resolved_at,
    ...(row.latest_observed_at ? { latestObservedAt: row.latest_observed_at } : {}),
    ...(row.fresh_until ? { freshUntil: row.fresh_until } : {}),
  } as const;
  return row.status === "unknown" ? base : { ...base, value: row.value as JsonValue };
}

function stalenessScore(feature: ResolvedPlaceFeature | undefined, now: string): number {
  if (!feature || feature.status === "unknown" || feature.status === "conflicted") return 1;
  if (feature.status === "stale") return 0.9;
  if (!feature.freshUntil) return 0.8;
  return Date.parse(feature.freshUntil) <= Date.parse(now) ? 0.8 : 0;
}
