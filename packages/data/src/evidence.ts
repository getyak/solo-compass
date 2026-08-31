/** JSON values accepted by Postgres JSONB and provider-independent tools. */
export type JsonPrimitive = string | number | boolean | null;
export type JsonValue =
  | JsonPrimitive
  | readonly JsonValue[]
  | { readonly [key: string]: JsonValue };

export const FEATURE_KEYS = {
  canonicalName: "identity.canonical_name",
  coordinates: "identity.coordinates",
  operatingStatus: "operating.status",
  rawOpeningHours: "opening_hours.raw",
  regularOpeningHours: "opening_hours.regular",
  openOnArrival: "opening_hours.open_on_arrival",
  wifiReliability: "work.wifi_reliability",
  wifiSpeedMbps: "work.wifi_speed_mbps",
  noiseLevel: "work.noise_level",
  powerOutlets: "work.power_outlets",
  seatAvailability: "work.seat_availability",
  videoCallFit: "work.video_call_fit",
  longStayPolicy: "work.long_stay_policy",
  minimumSpend: "work.minimum_spend",
} as const;

export type KnownFeatureKey = (typeof FEATURE_KEYS)[keyof typeof FEATURE_KEYS];
/** Extensible without a database enum migration. Known keys receive tuned policies. */
export type FeatureKey = KnownFeatureKey | (string & {});

export type ObservationState = "observed" | "reported_unknown" | "not_applicable";
export type ResolvedFeatureStatus = "resolved" | "unknown" | "conflicted" | "stale";

export interface EvidenceObservation {
  readonly id: string;
  readonly placeId: string;
  readonly featureKey: FeatureKey;
  readonly state: ObservationState;
  readonly value?: JsonValue;
  readonly confidence: number;
  readonly sourceWeight: number;
  /**
   * Independent origin of the claim. Reposts and API mirrors of the same
   * source share a key so they cannot manufacture consensus.
   */
  readonly independenceKey: string;
  readonly observedAt: string;
  readonly expiresAt?: string;
}

export interface FeatureConflictAlternative {
  readonly value: JsonValue;
  readonly weight: number;
  readonly observationIds: readonly string[];
}

export interface ResolvedPlaceFeature {
  readonly placeId: string;
  readonly featureKey: FeatureKey;
  /** Best-supported value is retained even when status is conflicted/stale. */
  readonly value?: JsonValue;
  readonly status: ResolvedFeatureStatus;
  readonly confidence: number;
  readonly latestObservedAt?: string;
  readonly freshUntil?: string;
  readonly supportingObservationIds: readonly string[];
  readonly conflictingObservationIds: readonly string[];
  readonly conflictDetails?: {
    readonly alternatives: readonly FeatureConflictAlternative[];
  };
  readonly resolverVersion: string;
  readonly resolutionFingerprint: string;
  readonly resolvedAt: string;
}

export type FeatureAggregation = "categorical" | "weighted_median" | "currency_median";

export interface FeaturePolicy {
  readonly ttlSeconds: number;
  readonly halfLifeSeconds: number;
  readonly aggregation: FeatureAggregation;
  readonly confidenceWeightTarget: number;
  readonly conflictRatio: number;
  readonly minimumConflictWeight: number;
  readonly numericTolerance?: number;
}
