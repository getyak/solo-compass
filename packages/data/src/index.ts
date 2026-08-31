export { createAnonClient, createServiceClient, rowToExperience } from "./db";
export type {
  Database,
  ExperienceRow,
  UserRow,
  CompletionRow,
  TrafficPingRow,
  PlaceRow,
  PlaceExternalRefRow,
  SourceArtifactRow,
  PlaceObservationRow,
  ResolvedPlaceFeatureRow,
  ExperiencePlaceLinkRow,
  RefreshJobRow,
  WorkSessionRow,
  PlaceOperatingStatus,
  ArtifactRetentionPolicy,
  RefreshJobStatus,
  WorkSessionOutcome,
  WorkSessionFailureReason,
  RouteCompilationRow,
  RouteCompilationStatus,
  RouteCompileQuotaRow,
} from "./db";

export { ExperiencesRepo } from "./experiences-repo";
export type { FindNearbyParams } from "./experiences-repo";

export { CompletionsRepo } from "./completions-repo";
export type { RecordCheckinParams, RecordCheckinResult, CompletionEntry } from "./completions-repo";

export * from "./evidence";
export {
  isWeeklyOpeningHours,
  parseSimpleOpeningHours,
  WEEKDAY_CODES,
  windowsForDay,
} from "./opening-hours";
export type { OpeningWindow, WeekdayCode, WeeklyOpeningHours } from "./opening-hours";
export { policyForFeature } from "./feature-policy";
export { resolveFeature, RESOLVER_VERSION } from "./feature-resolver";
export type { ResolveFeatureInput } from "./feature-resolver";
export {
  calculateRefreshPriority,
  decideFeatureRefresh,
  makeRefreshIdempotencyKey,
} from "./refresh-policy";

export { EvidenceRepo } from "./evidence-repo";
export type {
  AppendObservationInput,
  ExperienceEvidenceSnapshot,
  RegisterSourceArtifactInput,
  UpsertPlaceIdentityInput,
} from "./evidence-repo";
export { RefreshQueueRepo } from "./refresh-queue-repo";
export type { EnqueueRefreshInput } from "./refresh-queue-repo";
export {
  WorkSessionRateLimitError,
  WorkSessionValidationError,
  WorkSessionRepo,
  deriveWorkSessionObservations,
} from "./work-session-repo";
export type { RecordWorkSessionInput, RecordWorkSessionResult } from "./work-session-repo";
export { RouteCompilationRepo } from "./route-compilation-repo";
export type { PutRouteCompilationInput } from "./route-compilation-repo";
export { matchCandidateToExperience } from "./entity-resolution";
export type { EntityMatch, ExperienceAnchor, PlaceMatchCandidate } from "./entity-resolution";
export type {
  FeatureRefreshDecision,
  FeatureRefreshDecisionInput,
  RefreshAction,
  RefreshPriorityInput,
  RefreshReason,
  RefreshUrgency,
} from "./refresh-policy";
