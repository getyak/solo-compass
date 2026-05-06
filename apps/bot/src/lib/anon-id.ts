import { createHash } from "node:crypto";

/**
 * Hash a Telegram user_id with a server-side salt before it ever leaves the bot.
 * No raw Telegram identifier is ever stored or sent to analytics / Sentry.
 *
 * Salt rotation invalidates old hashes (a feature, not a bug — used for hard
 * deletes on /privacy opt-out).
 */
const SALT = process.env.ANON_ID_SALT ?? "solo-compass-dev-salt";

export function anonUserId(telegramUserId: number): string {
  return createHash("sha256").update(`${SALT}:${telegramUserId}`).digest("hex").slice(0, 16);
}
