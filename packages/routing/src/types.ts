export type RouteTaskKind = "deep_work" | "video_call" | "meal" | "explore" | "break" | "custom";

export type TransportMode = "pedestrian" | "bicycle" | "auto";

export type OperatingStatus = "active" | "unknown" | "temporarily_closed" | "permanently_closed";

export type EvidenceStatus = "resolved" | "stale" | "conflicted" | "unknown";

export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue };

export interface LocalTimeWindow {
  /** Minute in the place's local day, inclusive. */
  startMinute: number;
  /** Minute in the place's local day, exclusive. Overnight windows must be split. */
  endMinute: number;
}

export type OpeningHoursEvidence =
  | { status: "known"; windows: LocalTimeWindow[] }
  | { status: "unknown" };

export interface RouteFeatureFact {
  value: JsonValue;
  status: EvidenceStatus;
  confidence: number;
  freshUntil?: string;
}

export type FeatureOperator = "eq" | "gte" | "lte" | "in" | "contains" | "truthy";

export interface FeatureConstraint {
  featureKey: string;
  operator: FeatureOperator;
  expected?: JsonValue;
  /** Hard constraints reject a candidate; soft constraints only reduce its score. */
  hard?: boolean;
  /** Defaults to fresh `resolved` evidence only. */
  acceptableStatuses?: EvidenceStatus[];
  /** Optional lower bound for using the fact in this decision. */
  minimumConfidence?: number;
}

export interface RouteCandidate {
  id: string;
  experienceId: string;
  placeId?: string;
  /** Matrix node id. Defaults to `id`. */
  nodeId?: string;
  title: string;
  utility: number;
  estimatedSpend?: { status: "known"; amount: number; currency: string } | { status: "unknown" };
  operatingStatus: OperatingStatus;
  openingHours?: OpeningHoursEvidence;
  features: Record<string, RouteFeatureFact | undefined>;
}

export interface RouteTask {
  id: string;
  kind: RouteTaskKind;
  durationMinutes: number;
  earliestStartMinute?: number;
  latestEndMinute?: number;
  candidateIds?: string[];
  constraints?: FeatureConstraint[];
  /** Defaults to `known_open`. */
  openingRequirement?: "known_open" | "allow_unknown" | "ignore";
}

export interface WorkdayPlanIntent {
  originNodeId: string;
  startMinute: number;
  endMinute: number;
  tasks: RouteTask[];
  maxTravelMinutes?: number;
  maxWaitMinutes?: number;
  budget?: { maxAmount: number; currency: string };
  /** Defaults to false when a hard budget is present. */
  allowUnknownSpend?: boolean;
  /** Global escape hatch; individual tasks can also allow unknown hours. */
  allowUnknownOpeningHours?: boolean;
  fallbackMaxExtraTravelMinutes?: number;
}

export interface MatrixCell {
  durationMinutes: number | null;
  distanceMeters?: number | null;
}

export interface TravelTimeMatrix {
  mode: TransportMode;
  generatedAt?: string;
  cells: Record<string, Record<string, MatrixCell | undefined> | undefined>;
}

export type RouteWarningCode =
  | "operating_status_unknown"
  | "opening_hours_unknown"
  | "soft_constraint_unmet"
  | "stale_evidence"
  | "conflicted_evidence"
  | "low_confidence_evidence"
  | "spend_unknown"
  | "spend_currency_mismatch";

export interface RouteWarning {
  code: RouteWarningCode;
  candidateId: string;
  featureKey?: string;
  message: string;
}

export interface ScheduledStop {
  taskId: string;
  taskKind: RouteTaskKind;
  candidateId: string;
  experienceId: string;
  placeId?: string;
  title: string;
  arrivalMinute: number;
  startMinute: number;
  endMinute: number;
  travelFromPreviousMinutes: number;
  distanceFromPreviousMeters?: number;
  waitMinutes: number;
  estimatedSpend?: { amount: number; currency: string };
  warnings: RouteWarning[];
}

export interface RouteFallback {
  taskId: string;
  primaryCandidateId: string;
  candidateId: string;
  experienceId: string;
  placeId?: string;
  title: string;
  arrivalMinute: number;
  startMinute: number;
  endMinute: number;
  incomingTravelMinutes: number;
  outgoingTravelMinutes: number;
  extraTravelMinutes: number;
  warnings: RouteWarning[];
}

export type RouteRejectionCode =
  | "candidate_not_allowed"
  | "candidate_reused"
  | "confirmed_closed"
  | "opening_hours_unknown"
  | "outside_opening_window"
  | "hard_constraint_unmet"
  | "missing_matrix_leg"
  | "task_time_window"
  | "day_time_window"
  | "travel_budget"
  | "wait_budget"
  | "money_budget"
  | "money_budget_unknown"
  | "money_budget_currency_mismatch";

export interface RouteRejectionSummary {
  code: RouteRejectionCode;
  count: number;
}

export interface RouteSolution {
  stops: ScheduledStop[];
  fallbacks: RouteFallback[];
  score: number;
  totalTravelMinutes: number;
  totalDistanceMeters?: number;
  totalWaitMinutes: number;
  totalEstimatedSpend?: { amount: number; currency: string };
  budgetEstimateIncomplete: boolean;
  startsAtMinute: number;
  endsAtMinute: number;
  warnings: RouteWarning[];
  solver: {
    version: string;
    exploredStates: number;
    beamWidth: number;
    matrixMode: TransportMode;
  };
}

export type RoutePlanResult =
  | { status: "solved"; solution: RouteSolution }
  | {
      status: "unsatisfiable";
      failedTaskId: string;
      rejections: RouteRejectionSummary[];
      exploredStates: number;
    };

export interface RoutePlannerOptions {
  beamWidth?: number;
}
