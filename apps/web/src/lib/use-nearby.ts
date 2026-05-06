"use client";

import { useQuery } from "@tanstack/react-query";
import type { NearbyResponse } from "@/app/api/experiences/nearby/route";

export interface UseNearbyParams {
  /** [longitude, latitude] — quantised to keep the cache key stable while panning. */
  readonly center: readonly [number, number] | null;
  readonly intent?: string;
  readonly radius?: number;
}

/**
 * Quantise lng/lat to ~50m so micro-pans don't spam the API. Refetches
 * happen at the call-site by re-keying when the user pans >500m.
 */
function quantise(coord: number): number {
  return Math.round(coord * 2000) / 2000; // ~55m at the equator
}

async function fetchNearby(
  center: readonly [number, number],
  intent: string | undefined,
  radius: number,
  signal: AbortSignal,
): Promise<NearbyResponse> {
  const params = new URLSearchParams({
    lng: String(center[0]),
    lat: String(center[1]),
    radius: String(radius),
  });
  if (intent) params.set("intent", intent);
  const res = await fetch(`/api/experiences/nearby?${params.toString()}`, { signal });
  if (!res.ok) {
    throw new Error(`nearby ${res.status}: ${await res.text().catch(() => "")}`);
  }
  return (await res.json()) as NearbyResponse;
}

export function useNearby({ center, intent, radius = 1500 }: UseNearbyParams) {
  const key = center ? [quantise(center[0]), quantise(center[1])] : null;

  return useQuery<NearbyResponse>({
    queryKey: ["nearby", key, intent ?? "", radius],
    queryFn: ({ signal }) => fetchNearby(center as [number, number], intent, radius, signal),
    enabled: !!center,
    placeholderData: (prev) => prev, // keep markers visible while next batch loads
  });
}
