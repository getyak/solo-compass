"use client";

import { Suspense, useMemo, useState } from "react";
import type { Experience } from "@solo-compass/core";
import { MapView } from "@/components/MapView";
import { ExperienceCard } from "@/components/ExperienceCard";
import { InfoBar } from "@/components/InfoBar";
import { demoExperiences } from "@/data/demo-experiences";

function HomeInner() {
  const [selected, setSelected] = useState<Experience | null>(null);

  const experiences = useMemo(() => demoExperiences, []);

  return (
    <main className="relative h-screen w-screen overflow-hidden bg-paper-cream">
      <MapView
        experiences={experiences}
        onSelectExperience={setSelected}
        selectedId={selected?.id ?? null}
      />
      {selected && <ExperienceCard experience={selected} onClose={() => setSelected(null)} />}
      <InfoBar cityName="Chiang Mai" count={experiences.length} />
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
