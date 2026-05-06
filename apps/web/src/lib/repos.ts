/**
 * Singleton repo instances. One Supabase client per Node worker — recreating
 * a SupabaseClient per request leaks sockets in dev.
 *
 * Server-only by convention. Importing from a client component will pull
 * server env validation and crash at module load — keep the import server-side.
 */

import { CompletionsRepo, ExperiencesRepo } from "@solo-compass/data";
import { createClient } from "@supabase/supabase-js";
import type { Database } from "@solo-compass/data";
import { getServerEnv } from "./env";

let experiencesRepoCache: ExperiencesRepo | null = null;
let completionsRepoCache: CompletionsRepo | null = null;

export function getExperiencesRepo(): ExperiencesRepo {
  if (experiencesRepoCache) return experiencesRepoCache;
  const env = getServerEnv();
  // Anon key — RLS allows reading status='active' experiences.
  const client = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_KEY, {
    auth: { persistSession: false },
  });
  experiencesRepoCache = new ExperiencesRepo(client);
  return experiencesRepoCache;
}

export function getCompletionsRepo(): CompletionsRepo {
  if (completionsRepoCache) return completionsRepoCache;
  const env = getServerEnv();
  // Service-role — needed to upsert anon users + completions without auth.
  const client = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  completionsRepoCache = new CompletionsRepo(client);
  return completionsRepoCache;
}
