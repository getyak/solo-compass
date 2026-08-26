import * as Sentry from "@sentry/nextjs";
import { scrubSentryEvent } from "./src/lib/sentry";

if (process.env.SENTRY_DSN) {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    tracesSampleRate: 0.1,
    environment: process.env.NODE_ENV ?? "development",
    sendDefaultPii: false,
    beforeSend: scrubSentryEvent,
  });
}
