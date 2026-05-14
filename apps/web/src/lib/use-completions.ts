"use client";

import { useQuery } from "@tanstack/react-query";
import type { CompletionsResponse } from "@/app/api/me/completions/route";

async function fetchCompletions(signal: AbortSignal): Promise<CompletionsResponse> {
  const res = await fetch("/api/me/completions", { signal, credentials: "same-origin" });
  if (!res.ok) {
    throw new Error(`completions ${res.status}: ${await res.text().catch(() => "")}`);
  }
  return (await res.json()) as CompletionsResponse;
}

export function useCompletions() {
  return useQuery<CompletionsResponse>({
    queryKey: ["me", "completions"],
    queryFn: ({ signal }) => fetchCompletions(signal),
    refetchOnWindowFocus: true,
    staleTime: 30_000,
  });
}
