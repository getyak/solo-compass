import type { Experience } from "@solo-compass/core";
import type { CompletionWithExperienceId } from "@solo-compass/data";
import { categoryEmoji, categoryLabel } from "@/lib/category";

// ─── Types ─────────────────────────────────────────────────────────────────────

export interface RecapExperience {
  readonly experience: Experience;
  readonly completion: CompletionWithExperienceId;
}

interface TripStatsProps {
  readonly items: readonly RecapExperience[];
}

interface ExperienceCardProps {
  readonly item: RecapExperience;
  readonly handle: string;
  readonly cityCode: string;
}

interface ShareButtonProps {
  readonly title: string;
  readonly url: string;
}

// ─── Helpers ───────────────────────────────────────────────────────────────────

export function formatTripDateRange(completions: readonly CompletionWithExperienceId[]): string {
  if (completions.length === 0) return "";
  const dates = completions.map((c) => c.completedAt).sort();
  const first = new Date(dates[0]!);
  const last = new Date(dates[dates.length - 1]!);
  const opts: Intl.DateTimeFormatOptions = { month: "long", day: "numeric" };
  if (first.getFullYear() !== last.getFullYear()) {
    return `${first.toLocaleDateString("en-US", { ...opts, year: "numeric" })} – ${last.toLocaleDateString("en-US", { ...opts, year: "numeric" })}`;
  }
  if (first.getMonth() !== last.getMonth()) {
    return `${first.toLocaleDateString("en-US", opts)} – ${last.toLocaleDateString("en-US", opts)}`;
  }
  // same month
  return `${first.toLocaleDateString("en-US", { month: "long" })} ${first.getDate()}–${last.getDate()}`;
}

export function countDays(completions: readonly CompletionWithExperienceId[]): number {
  if (completions.length === 0) return 0;
  const dates = completions.map((c) => c.completedAt.slice(0, 10));
  return new Set(dates).size;
}

function uniqueCategories(items: readonly RecapExperience[]): string[] {
  const seen = new Set<string>();
  for (const { experience } of items) {
    seen.add(experience.category);
  }
  return [...seen];
}

// ─── City name & emoji map (extend as cities are seeded) ───────────────────────

const CITY_NAMES: Record<string, string> = {
  cmi: "Chiang Mai",
  bkk: "Bangkok",
  hni: "Hanoi",
  sgn: "Ho Chi Minh City",
  dps: "Bali",
  mel: "Melbourne",
  lis: "Lisbon",
  bcn: "Barcelona",
  mde: "Medellín",
  oax: "Oaxaca",
};

const CITY_EMOJI: Record<string, string> = {
  cmi: "🏯",
  bkk: "🛕",
  hni: "🏮",
  sgn: "🛵",
  dps: "🌺",
  mel: "☕",
  lis: "🚋",
  bcn: "🌊",
  mde: "🌸",
  oax: "🫙",
};

export function cityDisplayName(cityCode: string): string {
  return CITY_NAMES[cityCode] ?? cityCode.toUpperCase();
}

export function cityEmoji(cityCode: string): string {
  return CITY_EMOJI[cityCode] ?? "🗺️";
}

// ─── Sub-components ────────────────────────────────────────────────────────────

export function TripStats({ items }: TripStatsProps) {
  const categories = uniqueCategories(items);
  const days = countDays(items.map((i) => i.completion));

  return (
    <div className="flex flex-wrap items-center gap-4 text-sm text-ink-warm/70">
      <StatPill label="experiences" value={items.length} />
      <StatPill label="days" value={days} />
      <div className="flex flex-wrap gap-1.5">
        {categories.map((cat) => (
          <span
            key={cat}
            className="rounded-full bg-paper-cream px-2.5 py-0.5 text-xs font-medium ring-1 ring-ink-warm/15"
            title={categoryLabel[cat as keyof typeof categoryLabel]}
          >
            {categoryEmoji[cat as keyof typeof categoryEmoji]}{" "}
            {categoryLabel[cat as keyof typeof categoryLabel]}
          </span>
        ))}
      </div>
    </div>
  );
}

function StatPill({ label, value }: { readonly label: string; readonly value: number }) {
  return (
    <span className="flex items-baseline gap-1">
      <span className="text-xl font-bold text-ink-warm">{value}</span>
      <span className="text-xs uppercase tracking-wider text-ink-warm/50">{label}</span>
    </span>
  );
}

export function ExperienceRecapCard({ item, handle, cityCode }: ExperienceCardProps) {
  const { experience: exp, completion } = item;
  const date = new Date(completion.completedAt).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });

  return (
    <a
      href={`/u/${handle}/${cityCode}/${exp.id}`}
      className="block rounded-2xl bg-white shadow-sm ring-1 ring-ink-warm/8 transition hover:shadow-md hover:ring-ink-warm/15"
    >
      {/* Photo placeholder */}
      <div className="flex h-40 items-center justify-center rounded-t-2xl bg-muted-road/30">
        <span className="text-4xl" aria-hidden="true">
          {categoryEmoji[exp.category]}
        </span>
      </div>

      <div className="p-4">
        <div className="mb-1 flex items-center gap-2 text-xs font-medium uppercase tracking-wide text-deep-teal">
          <span>{categoryLabel[exp.category]}</span>
          <span className="text-ink-warm/30">·</span>
          <span className="text-ink-warm/50">{date}</span>
          {completion.rating && (
            <>
              <span className="text-ink-warm/30">·</span>
              <span className="text-warm-amber">{"★".repeat(completion.rating)}</span>
            </>
          )}
        </div>

        <h3 className="mb-1 text-base font-semibold leading-snug text-ink-warm">{exp.title}</h3>
        <p className="text-sm leading-relaxed text-ink-warm/70 line-clamp-2">{exp.oneLiner}</p>

        {completion.note && (
          <p className="mt-3 border-l-2 border-deep-teal/30 pl-3 text-sm italic leading-relaxed text-ink-warm/60 line-clamp-2">
            {completion.note}
          </p>
        )}
      </div>
    </a>
  );
}

export function ShareButton({ title, url }: ShareButtonProps) {
  return (
    <button
      type="button"
      className="inline-flex items-center gap-2 rounded-xl bg-deep-teal px-5 py-2.5 text-sm font-semibold text-paper-cream shadow-sm transition hover:bg-deep-teal/90 active:scale-95"
      onClick={() => {
        if (typeof navigator !== "undefined" && navigator.share) {
          void navigator.share({ title, url });
        } else {
          void navigator.clipboard.writeText(url);
        }
      }}
    >
      <svg
        aria-hidden="true"
        xmlns="http://www.w3.org/2000/svg"
        width="16"
        height="16"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      >
        <circle cx="18" cy="5" r="3" />
        <circle cx="6" cy="12" r="3" />
        <circle cx="18" cy="19" r="3" />
        <line x1="8.59" y1="13.51" x2="15.42" y2="17.49" />
        <line x1="15.41" y1="6.51" x2="8.59" y2="10.49" />
      </svg>
      Share trip
    </button>
  );
}
