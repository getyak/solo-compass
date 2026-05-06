import * as Sentry from "@sentry/node";

let initialized = false;

export function initSentry(): void {
  if (initialized) return;
  const dsn = process.env.SENTRY_DSN;
  if (!dsn) {
    console.log("Sentry: no SENTRY_DSN, skipping init");
    return;
  }
  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV ?? "development",
    tracesSampleRate: 0,
    beforeSend(event) {
      return scrubPII(event);
    },
  });
  initialized = true;
  console.log("Sentry: initialized for bot");
}

/**
 * Strip user transcripts, telegram identifiers, and any free-text we may have
 * attached to error context. Keeps stack traces; drops payload bodies.
 */
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
    delete event.extra.voice_url;
    delete event.extra.message_text;
  }
  if (event.contexts) {
    delete event.contexts.transcript;
  }
  return event;
}

export function captureException(err: unknown, tags?: Record<string, string>): void {
  if (!initialized) return;
  Sentry.captureException(err, tags ? { tags } : undefined);
}
