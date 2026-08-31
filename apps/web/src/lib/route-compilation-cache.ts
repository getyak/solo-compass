import { createHash } from "node:crypto";
import type { JsonValue } from "@solo-compass/data";
import type { RoutePlanResult, TransportMode } from "@solo-compass/routing";

export const ROUTE_COMPILER_CACHE_VERSION = "workday-route-v1";

export interface CachedRoutePayload {
  readonly result: RoutePlanResult;
  readonly evidenceCoverage: "fresh" | "partial";
  readonly refreshScheduled: boolean;
}

/** Stable SHA-256 over JSON-compatible compiler inputs. */
export function routeFingerprint(value: unknown): string {
  return createHash("sha256").update(canonicalJson(value)).digest("hex");
}

export function routeCacheExpiry(input: {
  readonly now?: Date;
  readonly mode: TransportMode;
  readonly resultStatus: RoutePlanResult["status"];
  readonly evidenceCoverage: CachedRoutePayload["evidenceCoverage"];
}): string {
  const now = input.now ?? new Date();
  const ttlMinutes =
    input.evidenceCoverage === "partial" || input.resultStatus === "unsatisfiable"
      ? 5
      : input.mode === "auto"
        ? 10
        : 6 * 60;
  return new Date(now.getTime() + ttlMinutes * 60_000).toISOString();
}

export function toJsonValue(payload: CachedRoutePayload): JsonValue {
  return JSON.parse(JSON.stringify(payload)) as JsonValue;
}

export function cachedRoutePayload(value: JsonValue): CachedRoutePayload | null {
  if (!isRecord(value)) return null;
  if (value.evidenceCoverage !== "fresh" && value.evidenceCoverage !== "partial") return null;
  if (typeof value.refreshScheduled !== "boolean" || !isRecord(value.result)) return null;
  if (value.result.status !== "solved" && value.result.status !== "unsatisfiable") return null;
  return value as unknown as CachedRoutePayload;
}

function canonicalJson(value: unknown): string {
  if (value === null) return "null";
  if (typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error("route fingerprint input must be finite JSON");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isRecord(value)) {
    const entries = Object.entries(value)
      .filter(([, entry]) => entry !== undefined)
      .sort(([left], [right]) => left.localeCompare(right));
    return `{${entries.map(([key, entry]) => `${JSON.stringify(key)}:${canonicalJson(entry)}`).join(",")}}`;
  }
  throw new Error("route fingerprint input must be JSON-compatible");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
