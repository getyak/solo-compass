export { structureExperience } from "./prompts/structure-experience";
export type {
  StructureExperienceInput,
  StructureExperienceResult,
} from "./prompts/structure-experience";

export { rankExperiences } from "./prompts/rank-experiences";
export type {
  RankExperiencesInput,
  RankExperiencesResult,
  RankedExperience,
} from "./prompts/rank-experiences";

export { parseIntent } from "./parse-intent";
export type { IntentFilters } from "./parse-intent";

export { trackCost, withCostTracking } from "./cost-tracker";
export type { CostSnapshot } from "./cost-tracker";

export { dedup } from "./compilation/dedup";
export type { MergedCandidate, DedupStats, DedupResult } from "./compilation/dedup";

export {
  createDeepseekClient,
  deepseekModel,
  deepseekBaseURL,
  normalizeDeepseekModel,
  withDeepSeekThinkingDisabled,
  DEFAULT_DEEPSEEK_BASE_URL,
  DEFAULT_DEEPSEEK_MODEL,
  DEEPSEEK_THINKING_DISABLED,
  LEGACY_DEEPSEEK_MODELS,
} from "./client";

export { withRetry } from "./retry";
export type { RetryOptions } from "./retry";
