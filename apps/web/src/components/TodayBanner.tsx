"use client";

import { useMemo, useState } from "react";
import type { NearbyResult } from "@/app/api/experiences/nearby/route";
import { categoryEmoji } from "@/lib/category";

interface TodayBannerProps {
  readonly results: readonly NearbyResult[];
  readonly onSelect: (experienceId: string) => void;
}

/**
 * Dismissable banner under the top nav that surfaces "what's good right now"
 * from the viewer's local hour. Uses only client data — no extra API call.
 * Dismissal persists for the session via sessionStorage.
 */
export function TodayBanner({ results, onSelect }: TodayBannerProps) {
  const [dismissed, setDismissed] = useState(() => readDismissed());

  const { headline, picks } = useMemo(() => pickForNow(results), [results]);

  if (dismissed) return null;
  if (picks.length === 0) return null;

  const handleDismiss = () => {
    setDismissed(true);
    writeDismissed();
  };

  return (
    <div className="pointer-events-none absolute inset-x-0 top-12 z-10 flex justify-center px-3">
      <div className="pointer-events-auto flex max-w-xl items-start gap-3 rounded-2xl bg-deep-teal/95 px-4 py-3 text-paper-cream shadow-lg ring-1 ring-deep-teal/60 backdrop-blur-md">
        <span className="text-xl leading-none" aria-hidden="true">
          ✨
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium leading-snug">{headline}</p>
          <ul className="mt-2 flex flex-wrap gap-1.5">
            {picks.map((p) => (
              <li key={p.experience.id}>
                <button
                  type="button"
                  onClick={() => onSelect(p.experience.id)}
                  className="flex items-center gap-1.5 rounded-full bg-paper-cream/15 px-2.5 py-1 text-xs font-medium text-paper-cream ring-1 ring-paper-cream/20 transition hover:bg-paper-cream/25"
                >
                  <span aria-hidden="true">{categoryEmoji[p.experience.category]}</span>
                  <span className="max-w-[140px] truncate">{p.experience.title}</span>
                  <span className="text-paper-cream/70">
                    {p.experience.soloScore.overall.toFixed(1)}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </div>
        <button
          type="button"
          onClick={handleDismiss}
          aria-label="Dismiss today's picks"
          className="flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-full text-paper-cream/70 transition hover:bg-paper-cream/15 hover:text-paper-cream"
        >
          ×
        </button>
      </div>
    </div>
  );
}

interface Pick {
  readonly experience: NearbyResult["experience"];
  readonly score: number;
}

interface PickResult {
  readonly headline: string;
  readonly picks: readonly Pick[];
}

function pickForNow(results: readonly NearbyResult[]): PickResult {
  if (results.length === 0) return { headline: "", picks: [] };

  const now = new Date();
  const hour = now.getHours();
  const slot = timeSlot(hour);

  const scored: Pick[] = results.map((r) => {
    const exp = r.experience;
    let score = exp.soloScore.overall * 10;
    const fits = exp.bestTimes.some((t) => hourInWindow(hour, t));
    if (fits) score += 25;
    else if (exp.bestTimes.length > 0) score -= 10;
    score -= Math.min(15, r.walkingMinutes * 0.6);
    return { experience: exp, score };
  });

  const picks = scored
    .slice()
    .sort((a, b) => b.score - a.score)
    .slice(0, 3);

  return { headline: headlineFor(slot, picks[0]?.experience.category), picks };
}

function hourInWindow(hour: number, t: { startHour: number; endHour: number }): boolean {
  if (t.startHour <= t.endHour) {
    return hour >= t.startHour && hour < t.endHour;
  }
  // Wrap-around window (e.g. 22→4 = nightlife).
  return hour >= t.startHour || hour < t.endHour;
}

type Slot = "morning" | "afternoon" | "evening" | "night";

function timeSlot(hour: number): Slot {
  if (hour < 6) return "night";
  if (hour < 12) return "morning";
  if (hour < 18) return "afternoon";
  if (hour < 22) return "evening";
  return "night";
}

function headlineFor(slot: Slot, leadCategory: string | undefined): string {
  const base: Record<Slot, string> = {
    morning: "Good for a solo morning",
    afternoon: "What fits this afternoon",
    evening: "Calm pick for tonight",
    night: "Open right now",
  };
  if (!leadCategory) return base[slot];
  const hint: Record<string, Record<Slot, string>> = {
    coffee: {
      morning: "Pick a quiet café before the crowd",
      afternoon: "An afternoon café break, solo-friendly",
      evening: "An evening café for slow reading",
      night: "Late café — open and uncrowded",
    },
    food: {
      morning: "Light bite to start the day",
      afternoon: "A solo-friendly lunch nearby",
      evening: "Dinner without the couples vibe",
      night: "Open kitchen this late",
    },
    nature: {
      morning: "A morning walk while it's cool",
      afternoon: "Park time — shaded picks",
      evening: "Golden-hour outdoors",
      night: "Outdoors that's safe after dark",
    },
  };
  return hint[leadCategory]?.[slot] ?? base[slot];
}

const STORAGE_KEY = "sc_today_banner_dismissed";

function readDismissed(): boolean {
  if (typeof window === "undefined") return false;
  try {
    return sessionStorage.getItem(STORAGE_KEY) === "1";
  } catch {
    return false;
  }
}

function writeDismissed() {
  if (typeof window === "undefined") return;
  try {
    sessionStorage.setItem(STORAGE_KEY, "1");
  } catch {
    // sessionStorage blocked — fall back to in-memory state.
  }
}
