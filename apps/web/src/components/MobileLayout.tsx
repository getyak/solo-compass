"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { Drawer } from "vaul";
import { MapView } from "@/components/MapView";
import { ExperienceSheet } from "@/components/ExperienceSheet";
import { IOSPrompt } from "@/components/IOSPrompt";
import { useNearby } from "@/lib/use-nearby";
import { track } from "@/lib/analytics";
import {
  readCheckins,
  writeCheckin,
  isIOSPromptSnoozed,
  type LocalCheckin,
} from "@/lib/checkin-store";
import { categoryEmoji, categoryLabel } from "@/lib/category";
import type { NearbyResult } from "@/app/api/experiences/nearby/route";

// Chiang Mai center as fallback
const DEFAULT_CENTER: [number, number] = [98.9853, 18.7883];

type BottomTab = "nearby" | "done";

interface DoneEntry {
  checkin: LocalCheckin;
  result: NearbyResult | undefined;
}

export function MobileLayout() {
  const [center, setCenter] = useState<[number, number] | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<BottomTab>("nearby");
  const [checkins, setCheckins] = useState<LocalCheckin[]>([]);
  const [showIOSPrompt, setShowIOSPrompt] = useState(false);
  const [sheetOpen, setSheetOpen] = useState(false);

  const { data } = useNearby({ center, intent: undefined });
  const results: readonly NearbyResult[] = data?.results ?? [];

  const selectedResult = useMemo(
    () => results.find((r) => r.experience.id === selectedId) ?? null,
    [results, selectedId],
  );

  // Load checkins from localStorage on mount
  useEffect(() => {
    setCheckins(readCheckins());
  }, []);

  // Request geolocation on first open
  useEffect(() => {
    if (!navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(
      (pos) => setCenter([pos.coords.longitude, pos.coords.latitude]),
      () => setCenter(DEFAULT_CENTER),
    );
  }, []);

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

  const handleCheckin = useCallback(
    async (experienceId: string, rating?: number) => {
      const res = await fetch(`/api/experiences/${experienceId}/checkin`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(rating ? { rating } : {}),
      });
      if (!res.ok) throw new Error(`checkin failed: ${res.status}`);

      const coords = center ?? undefined;
      const updated = writeCheckin({
        experienceId,
        timestamp: new Date().toISOString(),
        coords,
      });
      setCheckins(updated);

      track({ name: "checkin", props: { experienceId, rated: rating !== undefined } });

      if (updated.length >= 2 && !isIOSPromptSnoozed()) {
        setShowIOSPrompt(true);
      }
    },
    [center],
  );

  const doneExperiences = useMemo((): DoneEntry[] => {
    return checkins
      .slice()
      .reverse()
      .map((c) => ({
        checkin: c,
        result: results.find((r) => r.experience.id === c.experienceId),
      }));
  }, [checkins, results]);

  return (
    <main className="relative h-screen w-screen overflow-hidden bg-paper-cream">
      {showIOSPrompt && <IOSPrompt onDismiss={() => setShowIOSPrompt(false)} />}

      <MapView
        results={results}
        onSelect={handleSelect}
        selectedId={selectedId}
        onCenterChange={setCenter}
      />

      {/* Experience detail sheet — only shown when marker selected */}
      <ExperienceSheet
        key={selectedId ?? "none"}
        result={selectedResult}
        onOpenChange={(open) => !open && setSelectedId(null)}
        onCheckin={handleCheckin}
      />

      {/* Bottom sheet — nearby / done tabs */}
      <Drawer.Root
        open={sheetOpen}
        onOpenChange={setSheetOpen}
        shouldScaleBackground={false}
        modal={false}
      >
        <Drawer.Portal>
          <Drawer.Content
            className="fixed inset-x-0 bottom-0 z-20 flex flex-col rounded-t-2xl bg-paper-cream shadow-2xl outline-none"
            style={{ maxHeight: "60vh" }}
            aria-describedby={undefined}
          >
            <Drawer.Title className="sr-only">Nearby experiences</Drawer.Title>
            <button
              type="button"
              onClick={() => setSheetOpen((v) => !v)}
              aria-label={sheetOpen ? "Collapse sheet" : "Expand sheet"}
              className="flex w-full flex-col items-center pt-2 pb-1"
            >
              <div className="h-1.5 w-12 rounded-full bg-ink-warm/20" aria-hidden="true" />
            </button>

            <div className="flex border-b border-ink-warm/10 px-4">
              <TabButton active={activeTab === "nearby"} onClick={() => setActiveTab("nearby")}>
                Nearby ({results.length})
              </TabButton>
              <TabButton active={activeTab === "done"} onClick={() => setActiveTab("done")}>
                Done ({checkins.length})
              </TabButton>
            </div>

            <div className="overflow-y-auto flex-1">
              {activeTab === "nearby" ? (
                <NearbyList
                  results={results}
                  checkins={checkins}
                  onSelect={(id) => {
                    handleSelect(id);
                    setSheetOpen(false);
                  }}
                />
              ) : (
                <DoneList doneExperiences={doneExperiences} />
              )}
            </div>
          </Drawer.Content>
        </Drawer.Portal>
      </Drawer.Root>

      {/* Collapsed sheet peek — always visible when sheet is closed */}
      {!sheetOpen && (
        <button
          type="button"
          onClick={() => setSheetOpen(true)}
          className="fixed bottom-0 inset-x-0 z-20 flex flex-col items-center rounded-t-2xl bg-paper-cream shadow-2xl py-2"
          aria-label="Show nearby experiences"
        >
          <div className="h-1.5 w-12 rounded-full bg-ink-warm/20 mb-2" aria-hidden="true" />
          <p className="text-sm text-ink-warm/70 pb-1">
            {results.length > 0
              ? `${results.length} experiences nearby — swipe up`
              : "Finding experiences…"}
          </p>
        </button>
      )}
    </main>
  );
}

function TabButton({
  active,
  onClick,
  children,
}: {
  readonly active: boolean;
  readonly onClick: () => void;
  readonly children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={[
        "flex-1 py-2.5 text-sm font-medium transition",
        active
          ? "border-b-2 border-deep-teal text-deep-teal"
          : "text-ink-warm/50 hover:text-ink-warm/80",
      ].join(" ")}
    >
      {children}
    </button>
  );
}

function NearbyList({
  results,
  checkins,
  onSelect,
}: {
  readonly results: readonly NearbyResult[];
  readonly checkins: readonly LocalCheckin[];
  readonly onSelect: (id: string) => void;
}) {
  if (results.length === 0) {
    return <p className="py-8 text-center text-sm text-ink-warm/50">Looking for experiences…</p>;
  }

  return (
    <ul className="divide-y divide-ink-warm/8">
      {results.map((r) => {
        const done = checkins.some((c) => c.experienceId === r.experience.id);
        return (
          <li key={r.experience.id}>
            <button
              type="button"
              onClick={() => onSelect(r.experience.id)}
              className="w-full px-4 py-3 text-left flex items-start gap-3 hover:bg-ink-warm/5 transition"
            >
              <span className="text-xl leading-none mt-0.5" aria-hidden="true">
                {categoryEmoji[r.experience.category]}
              </span>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <p className="text-sm font-medium text-ink-warm truncate">{r.experience.title}</p>
                  {done && (
                    <span className="flex-shrink-0 text-xs bg-soft-green/30 text-deep-teal rounded px-1.5 py-0.5">
                      Done
                    </span>
                  )}
                </div>
                <p className="text-xs text-ink-warm/60 mt-0.5">
                  {categoryLabel[r.experience.category]} · {r.walkingMinutes} min walk
                </p>
              </div>
              <span className="flex-shrink-0 text-sm font-semibold text-deep-teal mt-0.5">
                {r.experience.soloScore.overall.toFixed(0)}
              </span>
            </button>
          </li>
        );
      })}
    </ul>
  );
}

function DoneList({ doneExperiences }: { readonly doneExperiences: readonly DoneEntry[] }) {
  if (doneExperiences.length === 0) {
    return (
      <div className="py-8 px-6 text-center">
        <p className="text-sm text-ink-warm/50">No check-ins yet.</p>
        <p className="text-xs text-ink-warm/40 mt-1">
          Tap an experience on the map and hit &ldquo;I did this&rdquo;.
        </p>
      </div>
    );
  }

  return (
    <ul className="divide-y divide-ink-warm/8">
      {doneExperiences.map(({ checkin, result }) => {
        const title = result?.experience.title ?? checkin.experienceId;
        const category = result?.experience.category;
        const date = new Date(checkin.timestamp).toLocaleDateString(undefined, {
          month: "short",
          day: "numeric",
        });
        return (
          <li key={checkin.experienceId} className="px-4 py-3 flex items-center gap-3">
            <span className="text-xl leading-none" aria-hidden="true">
              {category ? categoryEmoji[category] : "✓"}
            </span>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-ink-warm truncate">{title}</p>
              {category && (
                <p className="text-xs text-ink-warm/60 mt-0.5">{categoryLabel[category]}</p>
              )}
            </div>
            <span className="flex-shrink-0 text-xs text-ink-warm/50">{date}</span>
          </li>
        );
      })}
    </ul>
  );
}
