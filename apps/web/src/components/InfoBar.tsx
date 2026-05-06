"use client";

interface InfoBarProps {
  readonly cityName: string;
  readonly count: number;
  readonly loading?: boolean;
}

export function InfoBar({ cityName, count, loading }: InfoBarProps) {
  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-0 z-10 flex justify-center pb-4">
      <div
        className="pointer-events-auto rounded-full bg-paper-cream/85 px-5 py-2 text-sm text-ink-warm shadow-lg ring-1 ring-ink-warm/10 backdrop-blur-md"
        role="status"
        aria-live="polite"
      >
        <span aria-hidden="true">📍</span> <span className="font-medium">{cityName}</span>
        <span className="mx-2 text-ink-warm/40">·</span>
        {loading ? (
          <span className="text-ink-warm/60">looking…</span>
        ) : count === 0 ? (
          <span className="text-ink-warm/60">no experiences nearby</span>
        ) : (
          <span>
            {count} experience{count === 1 ? "" : "s"} nearby
          </span>
        )}
      </div>
    </div>
  );
}
