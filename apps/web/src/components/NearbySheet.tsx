"use client";

import { useMemo, useState } from "react";
import { Drawer } from "vaul";
import type { NearbyResult } from "@/app/api/experiences/nearby/route";
import { categoryEmoji, categoryLabel } from "@/lib/category";
import { healthColor, healthLabel } from "@/lib/health";
import { TimelineList } from "@/components/TimelineList";

export type SheetTab = "nearby" | "timeline";

interface NearbySheetProps {
  readonly cityName: string;
  readonly results: readonly NearbyResult[];
  readonly loading: boolean;
  readonly degraded: boolean;
  readonly selectedId: string | null;
  readonly onSelect: (id: string) => void;
}

// Three snap points: peek (collapsed pill, ~120px), mid (half), full (95%).
const SNAP_POINTS = ["120px", 0.55, 0.95] as const;

export function NearbySheet({
  cityName,
  results,
  loading,
  degraded,
  selectedId,
  onSelect,
}: NearbySheetProps) {
  const [snap, setSnap] = useState<number | string | null>(SNAP_POINTS[0]);
  const [tab, setTab] = useState<SheetTab>("nearby");

  const isPeek = snap === SNAP_POINTS[0];

  return (
    <Drawer.Root
      open
      modal={false}
      dismissible={false}
      snapPoints={SNAP_POINTS as unknown as (number | string)[]}
      activeSnapPoint={snap}
      setActiveSnapPoint={setSnap}
    >
      <Drawer.Portal>
        <Drawer.Content
          className="fixed inset-x-0 bottom-0 z-20 mx-auto flex h-full max-h-[95dvh] flex-col rounded-t-2xl bg-paper-cream shadow-2xl outline-none ring-1 ring-ink-warm/10"
          aria-describedby={undefined}
        >
          <Drawer.Title className="sr-only">Solo Compass — nearby & footprint</Drawer.Title>

          {/* Drag handle */}
          <button
            type="button"
            onClick={() => setSnap(snap === SNAP_POINTS[0] ? SNAP_POINTS[1] : SNAP_POINTS[0])}
            className="mx-auto mt-2 mb-1 flex h-6 w-20 flex-shrink-0 cursor-grab items-center justify-center"
            aria-label={isPeek ? "Expand" : "Collapse"}
          >
            <span className="h-1.5 w-12 rounded-full bg-ink-warm/30" aria-hidden="true" />
          </button>

          <PeekHeader
            cityName={cityName}
            results={results}
            loading={loading}
            degraded={degraded}
            isPeek={isPeek}
            onExpand={() => setSnap(SNAP_POINTS[1])}
          />

          {!isPeek && (
            <div className="flex flex-shrink-0 border-b border-ink-warm/10 px-4">
              <TabButton active={tab === "nearby"} onClick={() => setTab("nearby")}>
                Nearby {results.length > 0 ? `· ${results.length}` : ""}
              </TabButton>
              <TabButton active={tab === "timeline"} onClick={() => setTab("timeline")}>
                My footprint
              </TabButton>
            </div>
          )}

          <div className="flex-1 overflow-y-auto overscroll-contain px-4 pb-8 pt-2">
            {tab === "nearby" ? (
              <NearbyList
                results={results}
                loading={loading}
                degraded={degraded}
                selectedId={selectedId}
                onSelect={onSelect}
              />
            ) : (
              <TimelineList onSelect={onSelect} />
            )}
          </div>
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  );
}

function PeekHeader({
  cityName,
  results,
  loading,
  degraded,
  isPeek,
  onExpand,
}: {
  readonly cityName: string;
  readonly results: readonly NearbyResult[];
  readonly loading: boolean;
  readonly degraded: boolean;
  readonly isPeek: boolean;
  readonly onExpand: () => void;
}) {
  const count = results.length;

  return (
    <button
      type="button"
      onClick={onExpand}
      className="flex flex-shrink-0 items-center gap-3 px-5 pb-3 pt-1 text-left"
      aria-label={isPeek ? "Pull up to browse experiences" : "Currently viewing experiences"}
    >
      <span className="text-base" aria-hidden="true">
        📍
      </span>
      <span className="text-sm font-medium text-ink-warm">{cityName}</span>
      <span className="text-ink-warm/40">·</span>
      {loading && count === 0 ? (
        <span className="text-sm text-ink-warm/60">looking…</span>
      ) : count === 0 ? (
        <span className="text-sm text-ink-warm/60">
          {degraded ? "AI paused" : "no experiences nearby"}
        </span>
      ) : (
        <span className="text-sm text-ink-warm">
          {count} experience{count === 1 ? "" : "s"} nearby
        </span>
      )}
      {isPeek && <span className="ml-auto text-xs text-ink-warm/50">pull up ↑</span>}
    </button>
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
        "relative px-4 py-3 text-sm font-medium transition",
        active ? "text-deep-teal" : "text-ink-warm/60 hover:text-ink-warm",
      ].join(" ")}
    >
      {children}
      {active && (
        <span
          className="absolute inset-x-3 bottom-0 h-0.5 rounded-full bg-deep-teal"
          aria-hidden="true"
        />
      )}
    </button>
  );
}

function NearbyList({
  results,
  loading,
  degraded,
  selectedId,
  onSelect,
}: {
  readonly results: readonly NearbyResult[];
  readonly loading: boolean;
  readonly degraded: boolean;
  readonly selectedId: string | null;
  readonly onSelect: (id: string) => void;
}) {
  const grouped = useMemo(() => groupByWalkBand(results), [results]);

  if (loading && results.length === 0) {
    return <EmptyState>Looking around you…</EmptyState>;
  }
  if (results.length === 0) {
    return (
      <EmptyState>
        {degraded
          ? "AI ranker paused. Move the map to refresh."
          : "Nothing nearby here. Try moving the map."}
      </EmptyState>
    );
  }

  return (
    <div className="space-y-5">
      {grouped.map(({ label, items }) => (
        <section key={label}>
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-ink-warm/50">
            {label}
          </h3>
          <ul className="space-y-2">
            {items.map((r) => (
              <li key={r.experience.id}>
                <NearbyCard
                  result={r}
                  selected={r.experience.id === selectedId}
                  onSelect={onSelect}
                />
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}

function NearbyCard({
  result,
  selected,
  onSelect,
}: {
  readonly result: NearbyResult;
  readonly selected: boolean;
  readonly onSelect: (id: string) => void;
}) {
  const exp = result.experience;
  return (
    <button
      type="button"
      onClick={() => onSelect(exp.id)}
      className={[
        "flex w-full items-start gap-3 rounded-xl p-3 text-left ring-1 transition",
        selected
          ? "bg-warm-amber/10 ring-2 ring-warm-amber"
          : "bg-paper-cream/70 ring-ink-warm/10 hover:bg-paper-cream hover:ring-ink-warm/20",
      ].join(" ")}
    >
      <span className="text-2xl leading-none" aria-hidden="true">
        {categoryEmoji[exp.category]}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-2">
          <h4 className="truncate text-sm font-semibold text-ink-warm">{exp.title}</h4>
          <span className="flex-shrink-0 text-xs font-semibold text-deep-teal">
            {exp.soloScore.overall.toFixed(1)}
          </span>
        </div>
        <p className="mt-0.5 truncate text-xs text-ink-warm/70">{exp.oneLiner}</p>
        <div className="mt-1.5 flex items-center gap-2 text-[11px] text-ink-warm/60">
          <span>{categoryLabel[exp.category]}</span>
          <span className="text-ink-warm/30">·</span>
          <span>{result.walkingMinutes} min walk</span>
          <span className="text-ink-warm/30">·</span>
          <span className="flex items-center gap-1">
            <span
              className="h-1.5 w-1.5 rounded-full"
              style={{ backgroundColor: healthColor[result.health] }}
              aria-hidden="true"
            />
            {healthLabel[result.health]}
          </span>
        </div>
      </div>
    </button>
  );
}

function EmptyState({ children }: { readonly children: React.ReactNode }) {
  return (
    <div className="flex h-32 items-center justify-center text-sm text-ink-warm/50">{children}</div>
  );
}

interface Group {
  readonly label: string;
  readonly items: readonly NearbyResult[];
}

function groupByWalkBand(results: readonly NearbyResult[]): readonly Group[] {
  const close: NearbyResult[] = [];
  const mid: NearbyResult[] = [];
  const far: NearbyResult[] = [];
  for (const r of results) {
    if (r.walkingMinutes < 5) close.push(r);
    else if (r.walkingMinutes < 15) mid.push(r);
    else far.push(r);
  }
  const groups: Group[] = [];
  if (close.length > 0) groups.push({ label: "Within 5 min", items: close });
  if (mid.length > 0) groups.push({ label: "5–15 min walk", items: mid });
  if (far.length > 0) groups.push({ label: "15+ min walk", items: far });
  return groups;
}
