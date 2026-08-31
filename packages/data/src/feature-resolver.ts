import {
  type EvidenceObservation,
  type FeatureConflictAlternative,
  type FeatureKey,
  type FeaturePolicy,
  type JsonValue,
  type ResolvedPlaceFeature,
} from "./evidence";
import { policyForFeature } from "./feature-policy";

export const RESOLVER_VERSION = "evidence-v1";

interface WeightedObservation {
  readonly observation: EvidenceObservation;
  readonly effectiveWeight: number;
  readonly expiresAtMs: number;
  readonly observedAtMs: number;
}

interface ValueGroup {
  readonly value: JsonValue;
  readonly items: readonly WeightedObservation[];
  readonly weight: number;
  readonly latestObservedAtMs: number;
  readonly freshUntilMs: number;
}

export interface ResolveFeatureInput {
  readonly placeId: string;
  readonly featureKey: FeatureKey;
  readonly observations: readonly EvidenceObservation[];
  readonly now?: string;
  readonly policy?: FeaturePolicy;
}

export function resolveFeature(input: ResolveFeatureInput): ResolvedPlaceFeature {
  const nowIso = input.now ?? new Date().toISOString();
  const nowMs = parseTimestamp(nowIso, "now");
  const policy = input.policy ?? policyForFeature(input.featureKey);
  const candidates = input.observations.filter(
    (item) => item.placeId === input.placeId && item.featureKey === input.featureKey,
  );
  const collapsed = collapseDependentEvidence(candidates, policy, nowMs);
  const observed = collapsed.filter(
    (item) => item.observation.state === "observed" && item.observation.value !== undefined,
  );

  if (observed.length === 0) {
    const evidenceIds = collapsed.map((item) => item.observation.id).sort();
    return buildResult({
      placeId: input.placeId,
      featureKey: input.featureKey,
      status: "unknown",
      confidence: 0,
      supportingObservationIds: evidenceIds,
      conflictingObservationIds: [],
      resolvedAt: nowIso,
    });
  }

  if (policy.aggregation === "weighted_median") {
    return resolveNumeric(input.placeId, input.featureKey, observed, policy, nowIso, nowMs);
  }
  if (policy.aggregation === "currency_median") {
    return resolveCurrencyMedian(input.placeId, input.featureKey, observed, policy, nowIso, nowMs);
  }
  return resolveCategorical(input.placeId, input.featureKey, observed, policy, nowIso, nowMs);
}

function collapseDependentEvidence(
  observations: readonly EvidenceObservation[],
  policy: FeaturePolicy,
  nowMs: number,
): WeightedObservation[] {
  const latestByOrigin = new Map<string, WeightedObservation>();
  for (const observation of observations) {
    assertProbability(observation.confidence, "observation.confidence");
    assertProbability(observation.sourceWeight, "observation.sourceWeight");
    const observedAtMs = parseTimestamp(observation.observedAt, "observation.observedAt");
    const expiresAtMs = observation.expiresAt
      ? parseTimestamp(observation.expiresAt, "observation.expiresAt")
      : observedAtMs + policy.ttlSeconds * 1000;
    const ageSeconds = Math.max(0, (nowMs - observedAtMs) / 1000);
    const freshnessWeight = Math.max(0.05, 2 ** (-ageSeconds / policy.halfLifeSeconds));
    const weighted: WeightedObservation = {
      observation,
      observedAtMs,
      expiresAtMs,
      effectiveWeight: observation.confidence * observation.sourceWeight * freshnessWeight,
    };
    const existing = latestByOrigin.get(observation.independenceKey);
    if (
      existing === undefined ||
      weighted.observedAtMs > existing.observedAtMs ||
      (weighted.observedAtMs === existing.observedAtMs &&
        weighted.effectiveWeight > existing.effectiveWeight)
    ) {
      latestByOrigin.set(observation.independenceKey, weighted);
    }
  }
  return [...latestByOrigin.values()];
}

function resolveCategorical(
  placeId: string,
  featureKey: FeatureKey,
  observations: readonly WeightedObservation[],
  policy: FeaturePolicy,
  nowIso: string,
  nowMs: number,
): ResolvedPlaceFeature {
  const grouped = new Map<string, WeightedObservation[]>();
  for (const item of observations) {
    const key = stableJson(item.observation.value as JsonValue);
    const group = grouped.get(key) ?? [];
    group.push(item);
    grouped.set(key, group);
  }
  const groups = [...grouped.values()].map(toValueGroup).sort(compareGroups);
  const winner = groups[0];
  if (!winner) throw new Error("resolver invariant: categorical observations produced no group");
  return resultFromGroups(placeId, featureKey, winner, groups.slice(1), policy, nowIso, nowMs);
}

function resolveNumeric(
  placeId: string,
  featureKey: FeatureKey,
  observations: readonly WeightedObservation[],
  policy: FeaturePolicy,
  nowIso: string,
  nowMs: number,
): ResolvedPlaceFeature {
  const numeric = observations.filter(
    (item) => typeof item.observation.value === "number" && Number.isFinite(item.observation.value),
  );
  if (numeric.length === 0) {
    return buildResult({
      placeId,
      featureKey,
      status: "unknown",
      confidence: 0,
      supportingObservationIds: [],
      conflictingObservationIds: observations.map((item) => item.observation.id).sort(),
      resolvedAt: nowIso,
    });
  }
  const sorted = [...numeric].sort(
    (left, right) => (left.observation.value as number) - (right.observation.value as number),
  );
  const totalWeight = sumWeight(sorted);
  let cumulative = 0;
  let median = sorted[sorted.length - 1]?.observation.value as number;
  for (const item of sorted) {
    cumulative += item.effectiveWeight;
    if (cumulative >= totalWeight / 2) {
      median = item.observation.value as number;
      break;
    }
  }
  const tolerance = policy.numericTolerance ?? 0;
  const supporting = sorted.filter(
    (item) => Math.abs((item.observation.value as number) - median) <= tolerance,
  );
  const conflicting = sorted.filter(
    (item) => Math.abs((item.observation.value as number) - median) > tolerance,
  );
  const winner = toValueGroupWithValue(median, supporting);
  const alternatives = conflicting.length > 0 ? [toValueGroup(conflicting)] : [];
  return resultFromGroups(placeId, featureKey, winner, alternatives, policy, nowIso, nowMs);
}

function resolveCurrencyMedian(
  placeId: string,
  featureKey: FeatureKey,
  observations: readonly WeightedObservation[],
  policy: FeaturePolicy,
  nowIso: string,
  nowMs: number,
): ResolvedPlaceFeature {
  const valid = observations.filter((item) => isCurrencyAmount(item.observation.value));
  if (valid.length === 0) {
    return buildResult({
      placeId,
      featureKey,
      status: "unknown",
      confidence: 0,
      supportingObservationIds: [],
      conflictingObservationIds: observations.map((item) => item.observation.id).sort(),
      resolvedAt: nowIso,
    });
  }
  const byCurrency = new Map<string, WeightedObservation[]>();
  for (const item of valid) {
    const value = item.observation.value;
    if (!isCurrencyAmount(value)) continue;
    const currency = value.currency.toUpperCase();
    const group = byCurrency.get(currency) ?? [];
    group.push(item);
    byCurrency.set(currency, group);
  }
  const currencies = [...byCurrency.entries()].sort(
    ([leftCode, left], [rightCode, right]) =>
      sumWeight(right) - sumWeight(left) || leftCode.localeCompare(rightCode),
  );
  const winningCurrency = currencies[0];
  if (!winningCurrency)
    throw new Error("resolver invariant: currency observations produced no group");
  const [currency, currencyItems] = winningCurrency;
  const sorted = [...currencyItems].sort(
    (left, right) => currencyAmount(left) - currencyAmount(right),
  );
  const totalWeight = sumWeight(sorted);
  let cumulative = 0;
  let median = currencyAmount(sorted[sorted.length - 1]!);
  for (const item of sorted) {
    cumulative += item.effectiveWeight;
    if (cumulative >= totalWeight / 2) {
      median = currencyAmount(item);
      break;
    }
  }
  const tolerance = policy.numericTolerance ?? 0;
  const supporting = sorted.filter((item) => Math.abs(currencyAmount(item) - median) <= tolerance);
  const winningCurrencyOutliers = sorted.filter((item) => !supporting.includes(item));
  const alternatives = [
    ...groupByStableValue(winningCurrencyOutliers).map(toValueGroup),
    ...currencies
      .slice(1)
      .map(([alternativeCurrency, items]) =>
        toValueGroupWithValue(
          { amount: weightedCurrencyMedian(items), currency: alternativeCurrency },
          items,
        ),
      ),
  ];
  return resultFromGroups(
    placeId,
    featureKey,
    toValueGroupWithValue({ amount: median, currency }, supporting),
    alternatives,
    policy,
    nowIso,
    nowMs,
  );
}

function isCurrencyAmount(value: JsonValue | undefined): value is {
  amount: number;
  currency: string;
} {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const record = value as Record<string, JsonValue>;
  return (
    typeof record["amount"] === "number" &&
    Number.isFinite(record["amount"]) &&
    record["amount"] >= 0 &&
    typeof record["currency"] === "string" &&
    /^[A-Za-z]{3}$/.test(record["currency"])
  );
}

function currencyAmount(item: WeightedObservation): number {
  const value = item.observation.value;
  if (!isCurrencyAmount(value)) throw new Error("resolver invariant: invalid currency amount");
  return value.amount;
}

function weightedCurrencyMedian(items: readonly WeightedObservation[]): number {
  const sorted = [...items].sort((left, right) => currencyAmount(left) - currencyAmount(right));
  const totalWeight = sumWeight(sorted);
  let cumulative = 0;
  for (const item of sorted) {
    cumulative += item.effectiveWeight;
    if (cumulative >= totalWeight / 2) return currencyAmount(item);
  }
  const last = sorted[sorted.length - 1];
  if (!last) throw new Error("resolver invariant: empty currency group");
  return currencyAmount(last);
}

function groupByStableValue(observations: readonly WeightedObservation[]): WeightedObservation[][] {
  const groups = new Map<string, WeightedObservation[]>();
  for (const item of observations) {
    if (item.observation.value === undefined) continue;
    const key = stableJson(item.observation.value);
    const group = groups.get(key) ?? [];
    group.push(item);
    groups.set(key, group);
  }
  return [...groups.values()];
}

function resultFromGroups(
  placeId: string,
  featureKey: FeatureKey,
  winner: ValueGroup,
  alternatives: readonly ValueGroup[],
  policy: FeaturePolicy,
  nowIso: string,
  nowMs: number,
): ResolvedPlaceFeature {
  const meaningfulAlternatives = alternatives.filter(
    (alternative) =>
      alternative.weight >= policy.minimumConflictWeight &&
      alternative.weight / Math.max(winner.weight, Number.EPSILON) >= policy.conflictRatio,
  );
  const conflictingIds = meaningfulAlternatives
    .flatMap((alternative) => alternative.items.map((item) => item.observation.id))
    .sort();
  const isConflict = meaningfulAlternatives.length > 0;
  const isStale = winner.freshUntilMs <= nowMs;
  const totalRelevantWeight =
    winner.weight + alternatives.reduce((sum, item) => sum + item.weight, 0);
  const agreement = winner.weight / Math.max(totalRelevantWeight, Number.EPSILON);
  const strength = Math.min(1, winner.weight / policy.confidenceWeightTarget);
  const status = isConflict ? "conflicted" : isStale ? "stale" : "resolved";
  const statusPenalty = isConflict ? 0.55 : isStale ? 0.7 : 1;
  const confidence = clamp01(agreement * strength * statusPenalty);
  const conflictDetails = isConflict
    ? {
        alternatives: meaningfulAlternatives.map(toConflictAlternative),
      }
    : undefined;

  return buildResult({
    placeId,
    featureKey,
    value: winner.value,
    status,
    confidence,
    latestObservedAt: new Date(winner.latestObservedAtMs).toISOString(),
    freshUntil: new Date(winner.freshUntilMs).toISOString(),
    supportingObservationIds: winner.items.map((item) => item.observation.id).sort(),
    conflictingObservationIds: conflictingIds,
    conflictDetails,
    resolvedAt: nowIso,
  });
}

function toValueGroup(items: readonly WeightedObservation[]): ValueGroup {
  const first = items[0];
  if (!first || first.observation.value === undefined) {
    throw new Error("resolver invariant: value group requires an observed value");
  }
  return toValueGroupWithValue(first.observation.value, items);
}

function toValueGroupWithValue(
  value: JsonValue,
  items: readonly WeightedObservation[],
): ValueGroup {
  if (items.length === 0) throw new Error("resolver invariant: value group cannot be empty");
  return {
    value,
    items,
    weight: sumWeight(items),
    latestObservedAtMs: Math.max(...items.map((item) => item.observedAtMs)),
    freshUntilMs: Math.max(...items.map((item) => item.expiresAtMs)),
  };
}

function compareGroups(left: ValueGroup, right: ValueGroup): number {
  if (right.weight !== left.weight) return right.weight - left.weight;
  if (right.latestObservedAtMs !== left.latestObservedAtMs) {
    return right.latestObservedAtMs - left.latestObservedAtMs;
  }
  return stableJson(left.value).localeCompare(stableJson(right.value));
}

function toConflictAlternative(group: ValueGroup): FeatureConflictAlternative {
  return {
    value: group.value,
    weight: group.weight,
    observationIds: group.items.map((item) => item.observation.id).sort(),
  };
}

function buildResult(
  input: Omit<ResolvedPlaceFeature, "resolverVersion" | "resolutionFingerprint">,
): ResolvedPlaceFeature {
  const fingerprintPayload = {
    featureKey: input.featureKey,
    value: input.value ?? null,
    status: input.status,
    supporting: input.supportingObservationIds,
    conflicting: input.conflictingObservationIds,
  };
  return {
    ...input,
    resolverVersion: RESOLVER_VERSION,
    resolutionFingerprint: fnv1a(stableJson(fingerprintPayload)),
  };
}

function sumWeight(items: readonly WeightedObservation[]): number {
  return items.reduce((sum, item) => sum + item.effectiveWeight, 0);
}

function stableJson(value: JsonValue | object): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map((item) => stableJson(item)).join(",")}]`;
  const record = value as Record<string, JsonValue>;
  return `{${Object.keys(record)
    .sort()
    .map((key) => `${JSON.stringify(key)}:${stableJson(record[key] as JsonValue)}`)
    .join(",")}}`;
}

function fnv1a(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return `fnv1a-${(hash >>> 0).toString(16).padStart(8, "0")}`;
}

function parseTimestamp(value: string, label: string): number {
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) throw new Error(`${label} must be a valid ISO 8601 timestamp`);
  return parsed;
}

function assertProbability(value: number, label: string): void {
  if (!Number.isFinite(value) || value < 0 || value > 1) {
    throw new Error(`${label} must be between 0 and 1`);
  }
}

function clamp01(value: number): number {
  return Math.min(1, Math.max(0, value));
}
