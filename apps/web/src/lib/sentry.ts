/**
 * Web Sentry init helper.
 *
 * Lazy-initialized — first call wins, subsequent are no-ops. We do this rather
 * than wiring instrumentation.ts so the helper is platform-agnostic and easy
 * to read.
 *
 * beforeSend strips PII: no Mapbox tokens, no transcripts, no message text.
 */

import * as Sentry from "@sentry/nextjs";

let initialized = false;

export function initSentry(): void {
  if (initialized || typeof window === "undefined") return;
  const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;
  if (!dsn) return;

  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV ?? "development",
    tracesSampleRate: 0,
    beforeSend(event) {
      return scrubPII(event);
    },
  });
  initialized = true;
}

function scrubPII(event: Sentry.ErrorEvent): Sentry.ErrorEvent {
  if (event.user) {
    delete event.user.email;
    delete event.user.username;
    delete event.user.ip_address;
  }
  if (event.request) {
    delete event.request.cookies;
    delete event.request.data;
    delete event.request.query_string;
    delete event.request.headers;
  }
  if (event.extra) {
    delete event.extra.transcript;
    delete event.extra.intent;
    delete event.extra.message_text;
    delete event.extra.mapbox_token;
  }
  return event;
}
