import type { ExperienceId } from "./experience";
import type { UserId } from "./user";

/** Stable handle. Format: `itin_<random_id>`. */
export type ItineraryId = string & { readonly __brand: "ItineraryId" };

export interface Itinerary {
  readonly id: ItineraryId;
  readonly ownerId: UserId;
  readonly title: string;
  /** ISO 3166-1 alpha-3 or city code scoping this itinerary. */
  readonly cityCode: string;
  /** ISO 8601 date string (YYYY-MM-DD). */
  readonly startDate: string;
  /** ISO 8601 date string (YYYY-MM-DD). */
  readonly endDate: string;
  readonly experienceIds: readonly ExperienceId[];
  readonly note?: string;
  /** Whether the owner is open to meeting companions on this trip. */
  readonly openToCompanions: boolean;
  /** ISO 8601 UTC timestamp. */
  readonly createdAt: string;
  /** ISO 8601 UTC timestamp. */
  readonly updatedAt: string;
}
