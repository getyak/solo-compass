import { setTimeout as delay } from "node:timers/promises";
import {
  createServiceClient,
  EvidenceRepo,
  RefreshQueueRepo,
  RouteCompilationRepo,
} from "@solo-compass/data";
import { OsmAdapter } from "@solo-compass/sources-osm";
import { RefreshWorker } from "./processor";

async function main(): Promise<void> {
  const once = process.argv.includes("--once");
  const batchSize = numericArg("--batch", 10);
  const pollMilliseconds = numericArg("--poll-ms", 5_000);
  const workerId =
    process.env["SC_WORKER_ID"] ??
    `evidence-${process.pid}-${Math.random().toString(36).slice(2, 8)}`;
  const overpassUrl = requiredURL("OVERPASS_URL");
  const client = createServiceClient();
  const routeCompilations = new RouteCompilationRepo(client);
  const worker = new RefreshWorker({
    evidence: new EvidenceRepo(client),
    queue: new RefreshQueueRepo(client),
    // A worker is a production/batch caller. Never silently direct that load
    // at the public community endpoint; operators must choose an approved or
    // self-hosted Overpass instance explicitly.
    adapters: [new OsmAdapter({ overpassUrl })],
  });

  let nextCachePruneAt = 0;
  do {
    if (Date.now() >= nextCachePruneAt) {
      try {
        const pruned = await routeCompilations.pruneExpired();
        if (pruned > 0) {
          console.log(JSON.stringify({ event: "route_compilation_cache_pruned", pruned }));
        }
      } catch (error) {
        console.error("route compilation cache prune failed", error);
      }
      nextCachePruneAt = Date.now() + 60 * 60 * 1_000;
    }
    const result = await worker.runBatch(workerId, batchSize);
    console.log(JSON.stringify({ event: "refresh_worker_batch", workerId, ...result }));
    if (once) return;
    if (result.claimed === 0) await delay(pollMilliseconds);
  } while (true);
}

function requiredURL(name: string): string {
  const raw = process.env[name]?.trim();
  if (!raw) throw new Error(`${name} is required for the evidence worker`);
  try {
    return new URL(raw).toString();
  } catch {
    throw new Error(`${name} must be an absolute URL`);
  }
}

function numericArg(name: string, fallback: number): number {
  const prefix = `${name}=`;
  const raw = process.argv.find((arg) => arg.startsWith(prefix))?.slice(prefix.length);
  if (!raw) return fallback;
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

void main().catch((error: unknown) => {
  console.error(error instanceof Error ? (error.stack ?? error.message) : String(error));
  process.exitCode = 1;
});

export { RefreshWorker } from "./processor";
export type { RefreshBatchResult, RefreshWorkerDependencies } from "./processor";
