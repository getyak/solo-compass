/**
 * Runtime-validated environment variables.
 *
 * Two surfaces:
 *   - `clientEnv` — safe-to-ship NEXT_PUBLIC_* values, validated at module load.
 *   - `serverEnv` — secrets. Lazily validated, must never be imported from
 *     client components. Throws when required keys are missing.
 *
 * Missing vars produce a single clear error rather than a cryptic runtime
 * crash deep in a request handler.
 */

import { z } from "zod";

// ─── Client (NEXT_PUBLIC_*) ─────────────────────────────────────────────────────
// Always parsed — these inline into the client bundle, so a missing token
// would silently produce a broken map. Fail loud on boot instead.

const clientSchema = z.object({
  NEXT_PUBLIC_MAPBOX_TOKEN: z.string().min(10).default("pk.placeholder_token"),
  NEXT_PUBLIC_POSTHOG_KEY: z.string().optional(),
  NEXT_PUBLIC_POSTHOG_HOST: z.string().url().default("https://us.i.posthog.com"),
});

const clientParsed = clientSchema.safeParse({
  NEXT_PUBLIC_MAPBOX_TOKEN: process.env.NEXT_PUBLIC_MAPBOX_TOKEN,
  NEXT_PUBLIC_POSTHOG_KEY: process.env.NEXT_PUBLIC_POSTHOG_KEY,
  NEXT_PUBLIC_POSTHOG_HOST: process.env.NEXT_PUBLIC_POSTHOG_HOST,
});

if (!clientParsed.success) {
  // eslint-disable-next-line no-console
  console.error("Invalid NEXT_PUBLIC_* env:", clientParsed.error.flatten().fieldErrors);
  throw new Error("Invalid NEXT_PUBLIC_* environment configuration");
}

export const clientEnv = clientParsed.data;

// ─── Server (secrets) ──────────────────────────────────────────────────────────
// Lazy — many requests don't need them, and we want client bundles to not
// even attempt to read these names.

const serverSchema = z.object({
  SUPABASE_URL: z.string().url(),
  SUPABASE_KEY: z.string().min(20),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(20),
  ANTHROPIC_API_KEY: z.string().min(20).optional(),
});

export type ServerEnv = z.infer<typeof serverSchema>;

let serverEnvCache: ServerEnv | null = null;

export function getServerEnv(): ServerEnv {
  if (serverEnvCache) return serverEnvCache;
  const parsed = serverSchema.safeParse({
    SUPABASE_URL: process.env.SUPABASE_URL,
    SUPABASE_KEY: process.env.SUPABASE_KEY,
    SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
  });
  if (!parsed.success) {
    // eslint-disable-next-line no-console
    console.error("Invalid server env:", parsed.error.flatten().fieldErrors);
    throw new Error("Invalid server environment configuration");
  }
  serverEnvCache = parsed.data;
  return serverEnvCache;
}
