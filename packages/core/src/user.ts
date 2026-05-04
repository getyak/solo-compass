/**
 * User — minimal by design.
 *
 * The product's privacy posture is deliberately strict: we collect what we
 * absolutely need to personalize, nothing more. No real names. No social graph.
 * No required photo. Email is optional even.
 *
 * Identity is defined by *what you've experienced*, not by who you say you are.
 */

import type { ExperienceCategory, ExperienceId } from "./experience";

/** Stable handle. Format: `user_<random_id>`. Generated; user picks display handle separately. */
export type UserId = string & { readonly __brand: "UserId" };

export interface UserPreferences {
  /** What categories interest this user (multi-select, derived from behavior + voice intro). */
  readonly interests: readonly ExperienceCategory[];

  /** Pace. Affects how many experiences/day to suggest. */
  readonly pace: "slow" | "moderate" | "packed";

  /** Tolerance for crowds. Affects ranking (low tolerance → push hidden category). */
  readonly crowdTolerance: "low" | "medium" | "high";

  /** Budget signal. Drives price-tier filtering. */
  readonly budgetTier: 1 | 2 | 3 | 4; // $ to $$$$

  /** Free-text style intro from voice onboarding. Stored verbatim for future re-prompting.
   *  We don't try to "structure" this — Claude reads it directly during recommendation. */
  readonly voiceIntroTranscript?: string;

  /** Languages user can communicate in. Used when picking experiences with locals. */
  readonly languages: readonly string[]; // ISO codes
}

export interface UserCompletion {
  readonly experienceId: ExperienceId;
  readonly completedAt: string;
  readonly rating?: 1 | 2 | 3 | 4 | 5;
  readonly note?: string; // 30-second voice note transcribed
  readonly photoUrls?: readonly string[];
}

export interface User {
  readonly id: UserId;
  readonly displayHandle: string; // user-chosen, not unique-required
  readonly createdAt: string;
  readonly preferences: UserPreferences;

  /** Soft trust score. Influences weight of this user's reports.
   *  Starts at 1.0. Goes up with verified reports, photos that match place,
   *  long-stay GPS confirming attendance. Goes down with abuse reports. */
  readonly reporterWeight: number;

  /** What city this user is currently using the app in. Used to scope the map.
   *  Empty when not in any seeded city. */
  readonly currentCityCode?: string;
}
