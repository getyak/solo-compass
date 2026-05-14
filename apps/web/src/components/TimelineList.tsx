"use client";

import { useMemo } from "react";
import type { CompletionEntry } from "@solo-compass/data";
import { useCompletions } from "@/lib/use-completions";
import { categoryEmoji, categoryLabel } from "@/lib/category";

interface TimelineListProps {
  readonly onSelect?: (experienceId: string) => void;
}

export function TimelineList({ onSelect }: TimelineListProps) {
  const { data, isLoading, isError } = useCompletions();
  const entries = data?.entries ?? [];
  const groups = useMemo(() => groupByRecency(entries), [entries]);

  if (isLoading && entries.length === 0) {
    return <EmptyState>Loading your footprint…</EmptyState>;
  }
  if (isError) {
    return <EmptyState>Could not load your footprint. Try again.</EmptyState>;
  }
  if (entries.length === 0) {
    return (
      <EmptyState>Your footprint will appear here after you mark experiences as done.</EmptyState>
    );
  }

  return (
    <div className="space-y-5">
      {groups.map(({ label, items }) => (
        <section key={label}>
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wider text-ink-warm/50">
            {label}
            <span className="ml-1.5 font-normal normal-case text-ink-warm/40">
              · {items.length}
            </span>
          </h3>
          <ul className="space-y-2">
            {items.map((e) => (
              <li key={`${e.experience.id}-${e.completedAt}`}>
                <TimelineCard entry={e} onSelect={onSelect} />
              </li>
            ))}
          </ul>
        </section>
      ))}
    </div>
  );
}

function TimelineCard({
  entry,
  onSelect,
}: {
  readonly entry: CompletionEntry;
  readonly onSelect?: (experienceId: string) => void;
}) {
  const exp = entry.experience;
  const completed = new Date(entry.completedAt);

  return (
    <button
      type="button"
      onClick={() => onSelect?.(exp.id)}
      className="flex w-full items-start gap-3 rounded-xl bg-paper-cream/70 p-3 text-left ring-1 ring-ink-warm/10 transition hover:bg-paper-cream hover:ring-ink-warm/20"
    >
      <span className="text-2xl leading-none" aria-hidden="true">
        {categoryEmoji[exp.category]}
      </span>
      <div className="min-w-0 flex-1">
        <div className="flex items-baseline justify-between gap-2">
          <h4 className="truncate text-sm font-semibold text-ink-warm">{exp.title}</h4>
          {entry.rating !== null && (
            <span
              className="flex-shrink-0 text-xs text-warm-amber"
              aria-label={`${entry.rating} of 5`}
            >
              {"★".repeat(entry.rating)}
              <span className="text-ink-warm/20">{"★".repeat(5 - entry.rating)}</span>
            </span>
          )}
        </div>
        <p className="mt-0.5 truncate text-xs text-ink-warm/70">{exp.oneLiner}</p>
        <div className="mt-1.5 flex items-center gap-2 text-[11px] text-ink-warm/60">
          <span>{categoryLabel[exp.category]}</span>
          <span className="text-ink-warm/30">·</span>
          <time dateTime={entry.completedAt}>{formatRelative(completed)}</time>
        </div>
        {entry.note && (
          <p className="mt-1.5 rounded-md bg-paper-cream px-2 py-1 text-xs italic text-ink-warm/80 ring-1 ring-ink-warm/5">
            "{entry.note}"
          </p>
        )}
      </div>
    </button>
  );
}

function EmptyState({ children }: { readonly children: React.ReactNode }) {
  return (
    <div className="flex h-32 items-center justify-center text-center text-sm text-ink-warm/50">
      {children}
    </div>
  );
}

interface Group {
  readonly label: string;
  readonly items: readonly CompletionEntry[];
}

function groupByRecency(entries: readonly CompletionEntry[]): readonly Group[] {
  const now = new Date();
  const startOfToday = atMidnight(now);
  const startOfThisWeek = startOfIsoWeek(now);
  const startOfLastWeek = addDays(startOfThisWeek, -7);
  const startOfThisMonth = new Date(now.getFullYear(), now.getMonth(), 1);

  const today: CompletionEntry[] = [];
  const thisWeek: CompletionEntry[] = [];
  const lastWeek: CompletionEntry[] = [];
  const thisMonth: CompletionEntry[] = [];
  const earlier: CompletionEntry[] = [];

  for (const e of entries) {
    const t = new Date(e.completedAt);
    if (t >= startOfToday) today.push(e);
    else if (t >= startOfThisWeek) thisWeek.push(e);
    else if (t >= startOfLastWeek) lastWeek.push(e);
    else if (t >= startOfThisMonth) thisMonth.push(e);
    else earlier.push(e);
  }

  const groups: Group[] = [];
  if (today.length > 0) groups.push({ label: "Today", items: today });
  if (thisWeek.length > 0) groups.push({ label: "This week", items: thisWeek });
  if (lastWeek.length > 0) groups.push({ label: "Last week", items: lastWeek });
  if (thisMonth.length > 0) groups.push({ label: "Earlier this month", items: thisMonth });
  if (earlier.length > 0) groups.push({ label: "Earlier", items: earlier });
  return groups;
}

function atMidnight(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

// ISO week: Monday is the first day. JS getDay(): Sun=0, Mon=1, ..., Sat=6.
function startOfIsoWeek(d: Date): Date {
  const midnight = atMidnight(d);
  const dow = midnight.getDay();
  const daysFromMonday = (dow + 6) % 7;
  return addDays(midnight, -daysFromMonday);
}

function addDays(d: Date, n: number): Date {
  const copy = new Date(d);
  copy.setDate(copy.getDate() + n);
  return copy;
}

function formatRelative(date: Date): string {
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMin = Math.round(diffMs / 60_000);
  if (diffMin < 1) return "just now";
  if (diffMin < 60) return `${diffMin} min ago`;
  const diffHr = Math.round(diffMin / 60);
  if (diffHr < 24) return `${diffHr} hr ago`;
  const diffDays = Math.round(diffHr / 24);
  if (diffDays < 7) return `${diffDays}d ago`;
  return date.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
