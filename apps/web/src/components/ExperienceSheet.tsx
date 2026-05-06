"use client";

import { useState } from "react";
import { Drawer } from "vaul";
import type { Experience, HealthStatus, TimeWindow } from "@solo-compass/core";
import { categoryEmoji, categoryLabel } from "@/lib/category";
import { healthColor, healthLabel } from "@/lib/health";

interface ExperienceSheetProps {
  readonly result: { readonly experience: Experience; readonly health: HealthStatus; readonly reason: string; readonly walkingMinutes: number } | null;
  readonly onOpenChange: (open: boolean) => void;
  readonly onCheckin: (experienceId: string, rating?: number) => Promise<void> | void;
}

function formatDuration(d: Experience["durationMinutes"]): string {
  return d.min === d.max ? `${d.min} min` : `${d.min}–${d.max} min`;
}

function formatTimeWindow(t: TimeWindow): string {
  const window = `${String(t.startHour).padStart(2, "0")}:00–${String(t.endHour).padStart(2, "0")}:00`;
  return t.note ? `${window} (${t.note})` : window;
}

const DAY_NAMES = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"] as const;

export function ExperienceSheet({ result, onOpenChange, onCheckin }: ExperienceSheetProps) {
  const open = result !== null;
  const [checkinState, setCheckinState] = useState<"idle" | "saving" | "done">("idle");
  const [pendingRating, setPendingRating] = useState<number | undefined>();

  // Reset check-in state when the sheet opens with a different experience.
  const expId = result?.experience.id;
  if (expId && checkinState === "done" && pendingRating !== undefined) {
    // intentional no-op — kept in sync via key prop on parent
  }

  async function handleCheckin(rating?: number) {
    if (!result) return;
    setCheckinState("saving");
    setPendingRating(rating);
    try {
      await onCheckin(result.experience.id, rating);
      setCheckinState("done");
    } catch {
      setCheckinState("idle");
    }
  }

  return (
    <Drawer.Root open={open} onOpenChange={onOpenChange} shouldScaleBackground={false}>
      <Drawer.Portal>
        <Drawer.Overlay className="fixed inset-0 z-30 bg-ink-warm/30 backdrop-blur-[2px]" />
        <Drawer.Content
          className="fixed inset-x-0 bottom-0 z-40 flex max-h-[85vh] flex-col rounded-t-2xl bg-paper-cream shadow-2xl outline-none"
          aria-describedby={undefined}
        >
          <div className="mx-auto mt-2 mb-1 h-1.5 w-12 rounded-full bg-ink-warm/20" aria-hidden="true" />
          {result ? (
            <SheetBody
              result={result}
              checkinState={checkinState}
              pendingRating={pendingRating}
              onCheckin={handleCheckin}
            />
          ) : null}
        </Drawer.Content>
      </Drawer.Portal>
    </Drawer.Root>
  );
}

function SheetBody({
  result,
  checkinState,
  pendingRating,
  onCheckin,
}: {
  readonly result: NonNullable<ExperienceSheetProps["result"]>;
  readonly checkinState: "idle" | "saving" | "done";
  readonly pendingRating: number | undefined;
  readonly onCheckin: (rating?: number) => void;
}) {
  const exp = result.experience;
  const verifiedDate = new Date(exp.confidence.lastVerifiedAt);

  return (
    <div className="overflow-y-auto px-5 pb-8 pt-3">
      <Drawer.Title className="sr-only">{exp.title}</Drawer.Title>
      <div className="mb-2 flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-deep-teal">
        <span className="text-base leading-none" aria-hidden="true">
          {categoryEmoji[exp.category]}
        </span>
        <span>{categoryLabel[exp.category]}</span>
        <span className="text-ink-warm/40">·</span>
        <span className="text-ink-warm/70">{formatDuration(exp.durationMinutes)}</span>
        <span className="text-ink-warm/40">·</span>
        <span className="text-ink-warm/70">{result.walkingMinutes} min walk</span>
      </div>

      <h2 className="mb-2 text-xl font-semibold leading-snug text-ink-warm">{exp.title}</h2>
      <p className="mb-4 text-sm leading-relaxed text-ink-warm/80">{exp.oneLiner}</p>

      <div className="mb-5 rounded-xl bg-paper-cream/60 p-3 ring-1 ring-ink-warm/10">
        <p className="text-sm italic leading-relaxed text-ink-warm/90">"{result.reason}"</p>
      </div>

      <Section title="Why it matters">
        <p className="text-sm leading-relaxed text-ink-warm/80">{exp.whyItMatters}</p>
      </Section>

      <Section title="How to">
        <ol className="space-y-1.5 text-sm leading-relaxed text-ink-warm/80">
          {exp.howTo.map((step) => (
            <li key={step.order} className="flex gap-2">
              <span className="flex-shrink-0 font-mono text-ink-warm/50">{step.order}.</span>
              <span>{step.text}</span>
            </li>
          ))}
        </ol>
      </Section>

      {exp.realInconveniences.length > 0 && (
        <Section title="Real inconveniences">
          <ul className="space-y-1.5 text-sm leading-relaxed text-ink-warm/80">
            {exp.realInconveniences.map((r, i) => (
              <li key={i} className="flex gap-2">
                <span className="text-ink-warm/50">•</span>
                <span>
                  <span className="text-xs uppercase tracking-wide text-warm-amber">{r.category}</span>{" "}
                  {r.text}
                </span>
              </li>
            ))}
          </ul>
        </Section>
      )}

      {exp.bestTimes.length > 0 && (
        <Section title="Best times">
          <ul className="space-y-1 text-sm text-ink-warm/80">
            {exp.bestTimes.map((t, i) => (
              <li key={i}>
                {formatTimeWindow(t)}
                {t.dayOfWeek && t.dayOfWeek.length > 0 && (
                  <span className="ml-1 text-ink-warm/60">
                    · {t.dayOfWeek.map((d) => DAY_NAMES[d]).join(", ")}
                  </span>
                )}
              </li>
            ))}
          </ul>
        </Section>
      )}

      <Section title="Solo score">
        <div className="flex items-baseline gap-2">
          <span className="text-2xl font-semibold text-ink-warm">{exp.soloScore.overall.toFixed(0)}</span>
          <span className="text-xs text-ink-warm/60">/ 10 · based on {exp.soloScore.basedOnCount} reports</span>
        </div>
        {exp.soloScore.hint && <p className="mt-1 text-sm text-ink-warm/70">{exp.soloScore.hint}</p>}
      </Section>

      <Section title="Confidence">
        <div className="flex items-center gap-2 text-sm text-ink-warm/80">
          <span
            className="h-2.5 w-2.5 rounded-full"
            aria-hidden="true"
            style={{ backgroundColor: healthColor[result.health] }}
          />
          <span className="capitalize">{healthLabel[result.health]}</span>
          <span className="text-ink-warm/50">·</span>
          <span className="text-ink-warm/60">verified {verifiedDate.toISOString().slice(0, 10)}</span>
        </div>
        <p className="mt-1 text-xs text-ink-warm/60">{exp.confidence.reason}</p>
      </Section>

      {exp.sources.length > 0 && (
        <Section title="Sources">
          <ul className="space-y-0.5 text-xs text-ink-warm/60">
            {exp.sources.map((s, i) => (
              <li key={i}>
                <span className="font-medium text-ink-warm/80">{s.type}</span>
                {s.attribution && <> · {s.attribution}</>}
                {s.url && (
                  <>
                    {" · "}
                    <a className="text-deep-teal hover:underline" href={s.url} target="_blank" rel="noopener noreferrer">
                      link
                    </a>
                  </>
                )}
              </li>
            ))}
          </ul>
        </Section>
      )}

      <CheckinControl checkinState={checkinState} pendingRating={pendingRating} onCheckin={onCheckin} />
    </div>
  );
}

function Section({ title, children }: { readonly title: string; readonly children: React.ReactNode }) {
  return (
    <section className="mb-4">
      <h3 className="mb-1 text-xs font-semibold uppercase tracking-wider text-ink-warm/50">{title}</h3>
      {children}
    </section>
  );
}

function CheckinControl({
  checkinState,
  pendingRating,
  onCheckin,
}: {
  readonly checkinState: "idle" | "saving" | "done";
  readonly pendingRating: number | undefined;
  readonly onCheckin: (rating?: number) => void;
}) {
  if (checkinState === "done") {
    return (
      <div className="mt-2 rounded-xl bg-soft-green/30 px-4 py-3 text-center text-sm text-ink-warm">
        Marked as done{pendingRating ? ` · ${pendingRating}/5` : ""}. Thanks — this lifts the confidence dot.
      </div>
    );
  }

  return (
    <div className="mt-2 flex flex-col gap-2">
      <button
        type="button"
        onClick={() => onCheckin()}
        disabled={checkinState === "saving"}
        className="w-full rounded-xl bg-deep-teal py-3 text-sm font-semibold text-paper-cream transition hover:bg-deep-teal/90 disabled:opacity-60"
      >
        {checkinState === "saving" ? "Saving…" : "I did this"}
      </button>
      <div className="flex items-center justify-center gap-2 text-xs text-ink-warm/60">
        <span>Optional rating:</span>
        {[1, 2, 3, 4, 5].map((r) => (
          <button
            key={r}
            type="button"
            onClick={() => onCheckin(r)}
            disabled={checkinState === "saving"}
            aria-label={`Rate ${r} out of 5`}
            className="flex h-7 w-7 items-center justify-center rounded-full text-base hover:bg-ink-warm/10 disabled:opacity-60"
          >
            {r}
          </button>
        ))}
      </div>
    </div>
  );
}
