import { FEATURE_KEYS, type FeatureKey, type FeaturePolicy } from "./evidence";

const DAY = 24 * 60 * 60;

const DEFAULT_POLICY: FeaturePolicy = {
  ttlSeconds: 30 * DAY,
  halfLifeSeconds: 45 * DAY,
  aggregation: "categorical",
  confidenceWeightTarget: 1.5,
  conflictRatio: 0.55,
  minimumConflictWeight: 0.2,
};

const POLICIES: Readonly<Record<string, FeaturePolicy>> = {
  [FEATURE_KEYS.canonicalName]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 90 * DAY,
    halfLifeSeconds: 180 * DAY,
    confidenceWeightTarget: 1,
  },
  [FEATURE_KEYS.coordinates]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 90 * DAY,
    halfLifeSeconds: 180 * DAY,
    confidenceWeightTarget: 1,
  },
  [FEATURE_KEYS.operatingStatus]: {
    ...DEFAULT_POLICY,
    ttlSeconds: DAY,
    halfLifeSeconds: 7 * DAY,
    confidenceWeightTarget: 1,
    conflictRatio: 0.4,
  },
  [FEATURE_KEYS.regularOpeningHours]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 7 * DAY,
    halfLifeSeconds: 21 * DAY,
  },
  [FEATURE_KEYS.openOnArrival]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 2 * DAY,
    halfLifeSeconds: 7 * DAY,
    confidenceWeightTarget: 1,
  },
  [FEATURE_KEYS.wifiReliability]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 14 * DAY,
    halfLifeSeconds: 30 * DAY,
    aggregation: "weighted_median",
    numericTolerance: 1,
  },
  [FEATURE_KEYS.wifiSpeedMbps]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 14 * DAY,
    halfLifeSeconds: 30 * DAY,
    aggregation: "weighted_median",
    numericTolerance: 10,
  },
  [FEATURE_KEYS.noiseLevel]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 14 * DAY,
    halfLifeSeconds: 30 * DAY,
    aggregation: "weighted_median",
    numericTolerance: 1,
  },
  [FEATURE_KEYS.powerOutlets]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 30 * DAY,
    halfLifeSeconds: 60 * DAY,
  },
  [FEATURE_KEYS.seatAvailability]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 7 * DAY,
    halfLifeSeconds: 21 * DAY,
  },
  [FEATURE_KEYS.videoCallFit]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 14 * DAY,
    halfLifeSeconds: 30 * DAY,
  },
  [FEATURE_KEYS.longStayPolicy]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 14 * DAY,
    halfLifeSeconds: 30 * DAY,
  },
  [FEATURE_KEYS.minimumSpend]: {
    ...DEFAULT_POLICY,
    ttlSeconds: 14 * DAY,
    halfLifeSeconds: 30 * DAY,
    aggregation: "currency_median",
    numericTolerance: 1,
  },
};

export function policyForFeature(featureKey: FeatureKey): FeaturePolicy {
  return POLICIES[featureKey] ?? DEFAULT_POLICY;
}
