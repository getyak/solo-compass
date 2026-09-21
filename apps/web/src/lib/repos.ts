/**
 * Singleton repo instances. One Supabase client per Node worker — recreating
 * a SupabaseClient per request leaks sockets in dev.
 *
 * Server-only by convention. Importing from a client component will pull
 * server env validation and crash at module load — keep the import server-side.
 */

import {
  CompletionsRepo,
  EvidenceRepo,
  ExperiencesRepo,
  RefreshQueueRepo,
  RouteCompilationRepo,
  WorkSessionRepo,
} from "@solo-compass/data";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@solo-compass/data";
import { getServerEnv } from "./env";

let experiencesRepoCache: ExperiencesRepo | null = null;
let completionsRepoCache: CompletionsRepo | null = null;
let evidenceRepoCache: EvidenceRepo | null = null;
let refreshQueueRepoCache: RefreshQueueRepo | null = null;
let workSessionRepoCache: WorkSessionRepo | null = null;
let routeCompilationRepoCache: RouteCompilationRepo | null = null;
let serviceClientCache: SupabaseClient<Database> | null = null;

function getServiceClient(): SupabaseClient<Database> {
  if (serviceClientCache) return serviceClientCache;
  const env = getServerEnv();
  serviceClientCache = createClient<Database>(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });
  return serviceClientCache;
}

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
  // Service-role — needed to upsert anon users + completions without auth.
  completionsRepoCache = new CompletionsRepo(getServiceClient());
  return completionsRepoCache;
}

export function getEvidenceRepo(): EvidenceRepo {
  if (evidenceRepoCache) return evidenceRepoCache;
  evidenceRepoCache = new EvidenceRepo(getServiceClient());
  return evidenceRepoCache;
}

export function getRefreshQueueRepo(): RefreshQueueRepo {
  if (refreshQueueRepoCache) return refreshQueueRepoCache;
  refreshQueueRepoCache = new RefreshQueueRepo(getServiceClient());
  return refreshQueueRepoCache;
}

export function getWorkSessionRepo(): WorkSessionRepo {
  if (workSessionRepoCache) return workSessionRepoCache;
  workSessionRepoCache = new WorkSessionRepo(getServiceClient(), getEvidenceRepo());
  return workSessionRepoCache;
}

export function getRouteCompilationRepo(): RouteCompilationRepo {
  if (routeCompilationRepoCache) return routeCompilationRepoCache;
  routeCompilationRepoCache = new RouteCompilationRepo(getServiceClient());
  return routeCompilationRepoCache;
}

export async function authenticatedUserId(request: Request): Promise<string | null> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return null;
  const token = authorization.slice("Bearer ".length).trim();
  if (!token) return null;
  const { data, error } = await getServiceClient().auth.getUser(token);
  if (error || !data.user) return null;
  return data.user.id;
}
