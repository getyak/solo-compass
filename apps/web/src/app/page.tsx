"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { MapView } from "@/components/MapView";
import { ExperienceSheet } from "@/components/ExperienceSheet";
import { InfoBar } from "@/components/InfoBar";
import { VoiceIntent } from "@/components/VoiceIntent";
import { DesktopLayout } from "@/components/DesktopLayout";
import { MobileLayout } from "@/components/MobileLayout";
import { useNearby } from "@/lib/use-nearby";
import { track } from "@/lib/analytics";
import type { FilterValue } from "@/components/FilterBar";

const CHIANG_MAI: [number, number] = [98.9853, 18.7883];

function useIsMobile(): boolean {
  const [isMobile, setIsMobile] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(max-width: 1023px)");
    setIsMobile(mq.matches);
    const handler = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    mq.addEventListener("change", handler);
    return () => mq.removeEventListener("change", handler);
  }, []);
  return isMobile;
}

function HomeInner() {
  const isMobile = useIsMobile();
  const router = useRouter();
  const searchParams = useSearchParams();

  const initialFilter = (searchParams.get("filter") ?? "all") as FilterValue;
  const initialSel = searchParams.get("sel");

  const [center, setCenter] = useState<[number, number] | null>(CHIANG_MAI);
  const [intent, setIntent] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(initialSel);
  const [filter, setFilter] = useState<FilterValue>(initialFilter);

  const { data, isLoading } = useNearby({ center, intent: intent ?? undefined });
  const results = data?.results ?? [];

  const selectedResult = useMemo(
    () => results.find((r) => r.experience.id === selectedId) ?? null,
    [results, selectedId],
  );

  const pushUrl = useCallback(
    (nextFilter: FilterValue, nextSel: string | null) => {
      const params = new URLSearchParams();
      if (nextFilter !== "all") params.set("filter", nextFilter);
      if (nextSel) params.set("sel", nextSel);
      const qs = params.toString();
      router.push(qs ? `?${qs}` : "/", { scroll: false });
    },
    [router],
  );

  const handleSelect = useCallback(
    (id: string | null) => {
      setSelectedId(id);
      pushUrl(filter, id);
      if (id) {
        const r = results.find((x) => x.experience.id === id);
        if (r) {
          track({
            name: "marker_view",
            props: { experienceId: id, category: r.experience.category },
          });
          track({
            name: "sheet_open",
            props: { experienceId: id, category: r.experience.category },
          });
        }
      }
    },
    [results, filter, pushUrl],
  );

  const handleFilterChange = useCallback(
    (f: FilterValue) => {
      setFilter(f);
      pushUrl(f, selectedId);
    },
    [selectedId, pushUrl],
  );

  const handleIntentChange = useCallback((next: string | null) => {
    setIntent(next);
    if (next) {
      track({ name: "intent_set", props: { length: next.length, source: "voice" } });
    }
  }, []);

  const handleCheckin = useCallback(async (experienceId: string, rating?: number) => {
    const res = await fetch(`/api/experiences/${experienceId}/checkin`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(rating ? { rating } : {}),
    });
    if (!res.ok) throw new Error(`checkin failed: ${res.status}`);
    track({ name: "checkin", props: { experienceId, rated: rating !== undefined } });
  }, []);

  // Restore selection from URL when results first load
  useEffect(() => {
    if (initialSel && results.length > 0 && selectedId === initialSel) return;
  }, [results, initialSel, selectedId]);

  if (isMobile) {
    return <MobileLayout />;
  }

  return (
    <>
      <DesktopLayout
        results={results}
        isLoading={isLoading}
        selectedId={selectedId}
        filter={filter}
        onSelect={handleSelect}
        onCenterChange={setCenter}
        onFilterChange={handleFilterChange}
      />
      <ExperienceSheet
        key={selectedId ?? "none"}
        result={selectedResult}
        onOpenChange={(open) => !open && handleSelect(null)}
        onCheckin={handleCheckin}
      />
    </>
  );
}

export default function Home() {
  return (
    <Suspense fallback={<div className="h-screen w-screen bg-paper-cream" />}>
      <HomeInner />
    </Suspense>
  );
}
