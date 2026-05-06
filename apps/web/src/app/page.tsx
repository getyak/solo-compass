"use client";

import { Suspense, useCallback, useMemo, useState } from "react";
import { MapView } from "@/components/MapView";
import { ExperienceSheet } from "@/components/ExperienceSheet";
import { InfoBar } from "@/components/InfoBar";
import { VoiceIntent } from "@/components/VoiceIntent";
import { useNearby } from "@/lib/use-nearby";
import { track } from "@/lib/analytics";

function HomeInner() {
  const [center, setCenter] = useState<[number, number] | null>(null);
  const [intent, setIntent] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const { data, isLoading } = useNearby({ center, intent: intent ?? undefined });
  const results = data?.results ?? [];

  const selectedResult = useMemo(
    () => results.find((r) => r.experience.id === selectedId) ?? null,
    [results, selectedId],
  );

  const handleSelect = useCallback(
    (id: string | null) => {
      setSelectedId(id);
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
    [results],
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

  return (
    <main className="relative h-screen w-screen overflow-hidden bg-paper-cream">
      <MapView
        results={results}
        onSelect={handleSelect}
        selectedId={selectedId}
        onCenterChange={setCenter}
      />

      <VoiceIntent intent={intent} onIntentChange={handleIntentChange} />

      <ExperienceSheet
        key={selectedId ?? "none"}
        result={selectedResult}
        onOpenChange={(open) => !open && setSelectedId(null)}
        onCheckin={handleCheckin}
      />

      <InfoBar
        cityName={data?.degraded ? "Paused (AI)" : center ? "Here" : "Loading…"}
        count={results.length}
        loading={isLoading && results.length === 0}
      />
    </main>
  );
}

export default function Home() {
  return (
    <Suspense fallback={<div className="h-screen w-screen bg-paper-cream" />}>
      <HomeInner />
    </Suspense>
  );
}
