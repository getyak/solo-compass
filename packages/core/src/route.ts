import type { ExperienceId } from "./experience";
import type { UserId } from "./user";

/** Stable handle. Format: `route_<random_id>`. */
export type RouteId = string & { readonly __brand: "RouteId" };

export type Pace = "relaxed" | "standard" | "packed";

export type RouteSource = "editorial" | "aiGenerated" | "userCreated" | "coCreated";

export type VerificationStatus = "proposed" | "walkedBy" | "verified";

export interface RouteVerification {
  readonly status: VerificationStatus;
  readonly walkedByCount: number;
  readonly walkedBy: readonly UserId[];
}

/**
 * Placeholder for an attached companion slot — filled in by a later story.
 * Kept as an empty object so the parity guard catches divergence early.
 */
export interface RouteCompanion {}

export interface Route {
  readonly id: RouteId;
  readonly title: string;
  readonly summary: string;
  /** Ordered sequence of experience identifiers that make up this route. */
  readonly experienceIds: readonly ExperienceId[];
  readonly cityCode: string;
  readonly region: string;
  /** Estimated total duration in minutes. */
  readonly estimatedDuration: number;
  readonly distanceMeters: number;
  readonly pace: Pace;
  readonly tags: readonly string[];
  readonly source: RouteSource;
  readonly authorId?: UserId;
  /** Suggested start hour in the route's local timezone (0–23, fractional ok). */
  readonly bestStartHour?: number;
  /** Whether the route is currently inside its preferred window. */
  readonly bestNow: boolean;
  /**
   * Short human reason explaining why this route is surfaced right now,
   * shown as the "此刻理由" banner in now-context (e.g. "日落將至 · 30 分鐘後是最佳光線").
   */
  readonly reasonNow?: string;
  readonly verification: RouteVerification;
  readonly companion?: RouteCompanion;
}
