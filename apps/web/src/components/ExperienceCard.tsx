"use client";

import type { Experience } from "@solo-compass/core";
import { categoryEmoji, categoryLabel } from "@/lib/category";

interface ExperienceCardProps {
  readonly experience: Experience;
  readonly onClose: () => void;
}

function formatDuration(d: Experience["durationMinutes"]): string {
  if (d.min === d.max) return `${d.min} min`;
  return `${d.min}–${d.max} min`;
}

export function ExperienceCard({ experience, onClose }: ExperienceCardProps) {
  return (
    <div
      className="pointer-events-auto absolute left-1/2 top-6 z-20 w-[min(440px,calc(100vw-2rem))] -translate-x-1/2 rounded-2xl bg-paper-cream/97 p-5 shadow-2xl ring-1 ring-ink-warm/10 backdrop-blur-sm sm:left-6 sm:top-6 sm:translate-x-0"
      role="dialog"
      aria-label={experience.title}
    >
      <button
        type="button"
        onClick={onClose}
        aria-label="Close"
        className="absolute right-3 top-3 flex h-7 w-7 items-center justify-center rounded-full text-ink-warm/60 hover:bg-ink-warm/10 hover:text-ink-warm"
      >
        ×
      </button>

      <div className="mb-2 flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-deep-teal">
        <span className="text-base leading-none">{categoryEmoji[experience.category]}</span>
        <span>{categoryLabel[experience.category]}</span>
        <span className="text-ink-warm/40">·</span>
        <span className="text-ink-warm/70">{formatDuration(experience.durationMinutes)}</span>
        {experience.status === "candidate" && (
          <>
            <span className="text-ink-warm/40">·</span>
            <span className="text-warm-amber">candidate</span>
          </>
        )}
      </div>

      <h2 className="mb-2 pr-6 text-lg font-semibold leading-snug text-ink-warm">
        {experience.title}
      </h2>

      <p className="mb-3 text-sm leading-relaxed text-ink-warm/80">{experience.oneLiner}</p>

      <p className="mb-4 text-sm leading-relaxed text-ink-warm/70">{experience.whyItMatters}</p>

      <div className="flex items-center justify-between border-t border-ink-warm/10 pt-3">
        <div className="text-xs text-ink-warm/60">
          Solo Score{" "}
          <span className="font-semibold text-ink-warm">
            {experience.soloScore.overall.toFixed(0)}
          </span>
          /10
        </div>
        <a
          href={`#/experience/${experience.id}`}
          className="text-sm font-medium text-deep-teal hover:underline"
        >
          View details →
        </a>
      </div>
    </div>
  );
}
