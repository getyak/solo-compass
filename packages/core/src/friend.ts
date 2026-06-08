/**
 * Friend — the persistent relationship layer.
 *
 * Solo Compass's companion features (CompanionPost / CompanionRequest / Route)
 * produce *ephemeral* ties: a relationship exists only around a single meetup,
 * and the conversation freezes when the route completes. A `Friendship` is the
 * missing *persistent* layer — it promotes a one-off companion into a long-term
 * connection that unlocks direct companion invites, persistent DMs, and a
 * full read-only profile.
 *
 * Privacy posture mirrors `user.ts`: bidirectional confirmation, no real names,
 * no real photos (emoji only), and a rotatable friend code rather than
 * phone/email search.
 *
 * Keep field names in sync with the Swift mirrors in
 * `apps/ios/SoloCompass/Models/FriendRequest.swift` and `Friendship.swift`.
 * Guarded by `pnpm parity:check`.
 */

import type { UserId } from "./user";
import type { ConversationId } from "./companion";

/** Stable handle. Format: `fnd_<random_id>`. */
export type FriendshipId = string & { readonly __brand: "FriendshipId" };

/** Stable handle. Format: `freq_<random_id>`. */
export type FriendRequestId = string & { readonly __brand: "FriendRequestId" };

/**
 * A short, shareable code a user hands out to be added (e.g. "SOLO-7K2F-9XQR").
 * Rotatable — issuing a new one invalidates the old. Never the raw UserId.
 */
export type FriendCode = string & { readonly __brand: "FriendCode" };

export type FriendRequestStatus =
  | "pending"
  | "accepted"
  | "declined"
  | "withdrawn"
  | "expired";

/**
 * How the requester reached the recipient — drives anti-abuse weighting.
 * `discover` requests are gated by reporter_weight; `friend_code` requests
 * (offline trust) are not.
 */
export type FriendRequestSource =
  | "companion_chat" // already in a companion conversation together
  | "route_group" // in the same route group chat
  | "friend_code" // scanned / typed a friend code
  | "discover"; // added directly from an anonymized discover post

export interface FriendRequest {
  readonly id: FriendRequestId;
  readonly requesterId: UserId;
  readonly recipientId: UserId;
  readonly status: FriendRequestStatus;
  readonly source: FriendRequestSource;
  /** Optional one-line hello, max 120 chars. */
  readonly note?: string;
  /** ISO 8601 UTC. Requests auto-expire 14 days after creation → status "expired". */
  readonly expiresAt: string;
  /** ISO 8601 UTC timestamp. */
  readonly createdAt: string;
  /** ISO 8601 UTC timestamp. */
  readonly updatedAt: string;
}

/**
 * A confirmed, bidirectional friendship. Stored once per pair using an ordered
 * pair (`userLowId < userHighId` lexicographically) so A↔B is a single row and
 * lookups are idempotent. Direction/provenance lives in `initiatedBy`.
 */
export interface Friendship {
  readonly id: FriendshipId;
  /** Lexicographically smaller of the two UserIds. */
  readonly userLowId: UserId;
  /** Lexicographically larger of the two UserIds. */
  readonly userHighId: UserId;
  /** Who originally sent the accepted request (provenance, not direction). */
  readonly initiatedBy: UserId;
  /** The persistent 1:1 conversation backing this friendship (lazily created). */
  readonly conversationId?: ConversationId;
  /** ISO 8601 UTC when the friendship became active (request accepted). */
  readonly acceptedAt: string;
  /** ISO 8601 UTC timestamp. */
  readonly createdAt: string;
  /** ISO 8601 UTC timestamp. */
  readonly updatedAt: string;
}

/**
 * A device's APNs push token, keyed by (userId, deviceId). Used by the
 * push-notification Edge Functions to reach a user's devices.
 */
export interface DevicePushToken {
  readonly userId: UserId;
  readonly deviceId: string;
  readonly token: string;
  /** Platform discriminator. Currently always "ios". */
  readonly platform: "ios";
  /** ISO 8601 UTC timestamp. */
  readonly updatedAt: string;
}
