/**
 * Bot analytics. Same event names as web (channel="bot" property).
 *
 * No raw Telegram user_id ever leaves this process — anonUserId() hashes it
 * with a server-side salt first.
 *
 * No engagement events (no streaks, no daily-open nudges). Events are limited
 * to: app open, intent submitted, recommendations shown, experience opened,
 * experience completed, opt-out.
 *
 * Sink is configurable: PostHog or stdout for dev.
 */

import { anonUserId } from "./anon-id.js";

export type EventName =
  | "session_start"
  | "intent_submitted"
  | "recommendations_shown"
  | "experience_opened"
  | "experience_completed"
  | "experience_skipped"
  | "experience_reported"
  | "opted_out";

interface EventProps {
  [key: string]: string | number | boolean | undefined;
}

const POSTHOG_KEY = process.env.POSTHOG_KEY;
const POSTHOG_HOST = process.env.POSTHOG_HOST ?? "https://app.posthog.com";

const optedOut = new Set<string>();

export function isOptedOut(userId: number): boolean {
  return optedOut.has(anonUserId(userId));
}

export function optOut(userId: number): void {
  optedOut.add(anonUserId(userId));
}

export async function track(
  userId: number,
  event: EventName,
  props: EventProps = {},
): Promise<void> {
  const distinctId = anonUserId(userId);
  if (optedOut.has(distinctId) && event !== "opted_out") return;

  const payload = {
    api_key: POSTHOG_KEY,
    event,
    distinct_id: distinctId,
    properties: {
      channel: "bot",
      ...props,
    },
    timestamp: new Date().toISOString(),
  };

  if (!POSTHOG_KEY) {
    console.log("[analytics]", event, payload.properties);
    return;
  }

  try {
    await fetch(`${POSTHOG_HOST}/capture/`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
  } catch (err) {
    console.error("analytics post failed", err);
  }
}
