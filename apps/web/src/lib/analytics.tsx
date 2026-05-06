"use client";

/**
 * Analytics — PostHog wrapper. Fails open: every method is a no-op when
 * PostHog isn't configured, when DNT is on, or when init throws. UI must
 * never depend on a successful event.
 *
 * Event taxonomy:
 *   pageview      — automatic on first mount
 *   marker_view   — user opened the detail sheet for an experience
 *   intent_set    — user set or changed their voice/text intent
 *   checkin       — user pressed "I did this"
 *   sheet_open    — alias of marker_view (kept for spec parity)
 */

import { useEffect } from "react";
import posthog from "posthog-js";
import { clientEnv } from "./env";

let initialised = false;

function dntEnabled(): boolean {
  if (typeof navigator === "undefined") return false;
  // Multiple browser variants; treat any "1" or "yes" as opt-out.
  const flags = [
    navigator.doNotTrack,
    (navigator as Navigator & { msDoNotTrack?: string }).msDoNotTrack,
    (window as Window & { doNotTrack?: string }).doNotTrack,
  ];
  return flags.some((f) => f === "1" || f === "yes");
}

function ensureInit(): boolean {
  if (initialised) return true;
  if (typeof window === "undefined") return false;
  if (!clientEnv.NEXT_PUBLIC_POSTHOG_KEY) return false;
  if (dntEnabled()) return false;
  try {
    posthog.init(clientEnv.NEXT_PUBLIC_POSTHOG_KEY, {
      api_host: clientEnv.NEXT_PUBLIC_POSTHOG_HOST,
      capture_pageview: false, // we trigger it explicitly below
      autocapture: false, // PII risk — we send only the events listed above
      persistence: "localStorage",
      respect_dnt: true,
      disable_session_recording: true,
    });
    initialised = true;
    return true;
  } catch {
    // eslint-disable-next-line no-console
    console.warn("PostHog init failed — analytics disabled");
    return false;
  }
}

export type AnalyticsEvent =
  | { name: "pageview"; props?: Record<string, never> }
  | { name: "marker_view"; props: { experienceId: string; category: string } }
  | { name: "sheet_open"; props: { experienceId: string; category: string } }
  | { name: "intent_set"; props: { length: number; source: "voice" | "text" } }
  | { name: "checkin"; props: { experienceId: string; rated: boolean } };

export function track(event: AnalyticsEvent): void {
  if (!ensureInit()) return;
  try {
    posthog.capture(event.name, (event as { props?: Record<string, unknown> }).props ?? {});
  } catch {
    // never let analytics break the UI
  }
}

/** Mount once at the root to fire the initial pageview. */
export function AnalyticsBoot() {
  useEffect(() => {
    track({ name: "pageview" });
  }, []);
  return null;
}
