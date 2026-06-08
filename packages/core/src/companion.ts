import type { ExperienceCategory, ExperienceId } from "./experience";
import type { UserId } from "./user";

/** Stable handle. Format: `itin_<random_id>`. */
export type ItineraryId = string & { readonly __brand: "ItineraryId" };

/** Stable handle. Format: `cpost_<random_id>`. */
export type CompanionPostId = string & { readonly __brand: "CompanionPostId" };

/** Stable handle. Format: `creq_<random_id>`. */
export type CompanionRequestId = string & {
  readonly __brand: "CompanionRequestId";
};

/** Stable handle. Format: `cprof_<random_id>`. */
export type CompanionProfileId = string & {
  readonly __brand: "CompanionProfileId";
};

/** Stable handle. Format: `conv_<random_id>`. */
export type ConversationId = string & { readonly __brand: "ConversationId" };

/** Stable handle. Format: `cmsg_<random_id>`. */
export type ChatMessageId = string & { readonly __brand: "ChatMessageId" };

/** Stable handle. Format: `crep_<random_id>`. */
export type CompanionReportId = string & {
  readonly __brand: "CompanionReportId";
};

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

export type CompanionPostMode = "itinerary" | "nearby";

export interface CompanionPost {
  readonly id: CompanionPostId;
  readonly authorId: UserId;
  /** itinerary: tied to a named trip; nearby: open-ended local availability. */
  readonly mode: CompanionPostMode;
  /** Present when mode=itinerary. */
  readonly itineraryId?: ItineraryId;
  /** Short text intro visible to other users before they send a request. */
  readonly blurb: string;
  /** Activity categories the author is interested in. */
  readonly categories: readonly ExperienceCategory[];
  /** ISO 3166-1 alpha-3 or city code where the author is active. */
  readonly cityCode: string;
  /** ISO 8601 date string (YYYY-MM-DD). Null for nearby-mode posts. */
  readonly activeFrom?: string;
  /** ISO 8601 date string (YYYY-MM-DD). Null for nearby-mode posts. */
  readonly activeTo?: string;
  /** ISO 8601 UTC timestamp. */
  readonly createdAt: string;
  /** ISO 8601 UTC timestamp. */
  readonly updatedAt: string;
}

export type CompanionRequestStatus = "pending" | "accepted" | "declined" | "withdrawn";

export interface CompanionRequest {
  readonly id: CompanionRequestId;
  readonly postId: CompanionPostId;
  readonly requesterId: UserId;
  readonly recipientId: UserId;
  readonly status: CompanionRequestStatus;
  /** Optional introductory note from the requester. */
  readonly note?: string;
  /** ISO 8601 UTC timestamp. */
  readonly createdAt: string;
  /** ISO 8601 UTC timestamp. */
  readonly updatedAt: string;
}

export type CompanionVisibility = "off" | "itinerary_only" | "nearby_and_itinerary";

export interface CompanionProfile {
  readonly id: CompanionProfileId;
  readonly userId: UserId;
  /** Emoji or short generated avatar token. No real photo. */
  readonly avatarEmoji: string;
  /** Short bio, max 280 chars. */
  readonly bio: string;
  /** ISO language codes (e.g. ["en", "zh"]). */
  readonly languages: readonly string[];
  /** Controls whether and how the user appears in discovery. Default: off. */
  readonly visibility: CompanionVisibility;
  /** ISO 8601 UTC timestamp. */
  readonly createdAt: string;
  /** ISO 8601 UTC timestamp. */
  readonly updatedAt: string;
}

export interface Conversation {
  readonly id: ConversationId;
  /**
   * The CompanionRequest this thread was opened from. Optional: `friendDirect`
   * conversations are created from a Friendship, not a companion request.
   */
  readonly requestId?: CompanionRequestId;
  readonly participantIds: readonly UserId[];
  /**
   * `oneOnOne` for private companion threads; `groupRoute` for route-anchored
   * group chats; `friendDirect` for persistent 1:1 friend DMs (no request).
   */
  readonly type: "oneOnOne" | "groupRoute" | "friendDirect";
  /** Non-nil when `type === "groupRoute"` — the Route this group chat is anchored to. */
  readonly routeId?: string;
  /** ISO 8601 UTC timestamp of the most recent message. */
  readonly lastMessageAt?: string;
  /** When true, the chat is frozen — no new messages can be sent (route completed). */
  readonly isReadOnly: boolean;
  /** ISO 8601 UTC timestamp. */
  readonly createdAt: string;
  /** ISO 8601 UTC timestamp. */
  readonly updatedAt: string;
}

/** A media or document attachment carried by a {@link ChatMessage}. */
export interface ChatAttachment {
  readonly id: string;
  /** Discriminates a previewable image from an arbitrary file. */
  readonly kind: "image" | "file";
  readonly fileName: string;
  readonly mimeType: string;
  readonly fileSizeBytes: number;
  /** Path within the `chat-media` bucket: `{conversationId}/{messageId}/{attachmentId}-{fileName}`. */
  readonly storagePath: string;
  /** Pixel width, image kind only. */
  readonly width?: number;
  /** Pixel height, image kind only. */
  readonly height?: number;
}

export interface ChatMessage {
  readonly id: ChatMessageId;
  readonly conversationId: ConversationId;
  readonly senderId: UserId;
  readonly body: string;
  /** Attachments carried by this message. Omitted/empty when text-only. */
  readonly attachments?: readonly ChatAttachment[];
  /** ISO 8601 UTC timestamp when the recipient read the message. */
  readonly readAt?: string;
  /** ISO 8601 UTC timestamp. */
  readonly createdAt: string;
}

export type CompanionReportReason =
  | "spam"
  | "harassment"
  | "inappropriate_content"
  | "fake_profile"
  | "other";

export interface CompanionReport {
  readonly id: CompanionReportId;
  readonly reporterId: UserId;
  readonly targetUserId: UserId;
  readonly reason: CompanionReportReason;
  /** Optional free-text details. */
  readonly details?: string;
  /** ISO 8601 UTC timestamp. */
  readonly createdAt: string;
}
