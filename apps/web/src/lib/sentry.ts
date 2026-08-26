import type { ErrorEvent } from "@sentry/nextjs";

/** Strip known secrets and message content before an event leaves the app. */
export function scrubSentryEvent(event: ErrorEvent): ErrorEvent {
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
