import type { Experience } from "@solo-compass/core";
import {
  FEATURE_KEYS,
  isWeeklyOpeningHours,
  windowsForDay,
  type ExperienceEvidenceSnapshot,
  type JsonValue as EvidenceJsonValue,
  type ResolvedPlaceFeatureRow,
} from "@solo-compass/data";
import type {
  JsonValue,
  OperatingStatus,
  RouteCandidate,
  RouteFeatureFact,
  RouteTask,
} from "@solo-compass/routing";

export function compileRouteCandidates(input: {
  readonly experiences: readonly Experience[];
  readonly snapshots: ReadonlyMap<string, ExperienceEvidenceSnapshot>;
  readonly dayOfWeek: number;
}): RouteCandidate[] {
  return input.experiences.map((experience) => {
    const snapshot = input.snapshots.get(experience.id);
    const byKey = new Map(snapshot?.features.map((feature) => [feature.feature_key, feature]));
    const openingFeature = byKey.get(FEATURE_KEYS.regularOpeningHours);
    const openingHours =
      openingFeature?.status === "resolved" &&
      openingFeature.confidence >= 0.4 &&
      isWeeklyOpeningHours(openingFeature.value)
        ? {
            status: "known" as const,
            windows: windowsForDay(openingFeature.value, input.dayOfWeek).map((window) => ({
              startMinute: window.startMinute,
              endMinute: window.endMinute,
            })),
          }
        : { status: "unknown" as const };
    const minimumSpend = byKey.get(FEATURE_KEYS.minimumSpend);
    return {
      id: experience.id,
      experienceId: experience.id,
      ...(snapshot ? { placeId: snapshot.placeId } : {}),
      title: experience.title,
      utility: clamp(experience.soloScore.overall / 10, 0, 1),
      estimatedSpend: spendFromFeature(minimumSpend),
      operatingStatus: operatingStatusFromFeature(byKey.get(FEATURE_KEYS.operatingStatus)),
      openingHours,
      features: Object.fromEntries(
        [...byKey.entries()].map(([key, feature]) => [key, featureFact(feature)]),
      ),
    };
  });
}

/** Product-semantic candidate pool; the solver still enforces all hard facts. */
export function withDefaultTaskCandidatePools(
  tasks: readonly RouteTask[],
  experiences: readonly Experience[],
): RouteTask[] {
  const categoryById = new Map(
    experiences.map((experience) => [experience.id, experience.category]),
  );
  return tasks.map((task) => {
    if (task.candidateIds) return task;
    const candidateIds = experiences
      .filter((experience) => categoryFitsTask(experience.category, task.kind))
      .map((experience) => experience.id)
      .filter((id) => categoryById.has(id));
    return { ...task, candidateIds };
  });
}

function categoryFitsTask(category: Experience["category"], kind: RouteTask["kind"]): boolean {
  switch (kind) {
    case "deep_work":
    case "video_call":
      return category === "work" || category === "coffee";
    case "meal":
      return category === "food" || category === "coffee";
    case "break":
      return category === "coffee" || category === "nature" || category === "wellness";
    case "explore":
    case "custom":
      return true;
  }
}

function operatingStatusFromFeature(feature: ResolvedPlaceFeatureRow | undefined): OperatingStatus {
  if (feature?.status !== "resolved" || typeof feature.value !== "string") return "unknown";
  if (
    feature.value === "active" ||
    feature.value === "unknown" ||
    feature.value === "temporarily_closed" ||
    feature.value === "permanently_closed"
  ) {
    return feature.value;
  }
  return "unknown";
}

function spendFromFeature(
  feature: ResolvedPlaceFeatureRow | undefined,
): RouteCandidate["estimatedSpend"] {
  if (feature?.status !== "resolved" || feature.confidence < 0.6 || !isRecord(feature.value)) {
    return { status: "unknown" };
  }
  const amount = feature.value["amount"];
  const currency = feature.value["currency"];
  if (
    typeof amount !== "number" ||
    amount < 0 ||
    typeof currency !== "string" ||
    !/^[A-Za-z]{3}$/.test(currency)
  ) {
    return { status: "unknown" };
  }
  return { status: "known", amount, currency: currency.toUpperCase() };
}

function featureFact(feature: ResolvedPlaceFeatureRow): RouteFeatureFact {
  return {
    value: feature.value as EvidenceJsonValue as JsonValue,
    status: feature.status,
    confidence: feature.confidence,
    ...(feature.fresh_until ? { freshUntil: feature.fresh_until } : {}),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}
