/**
 * DayPageMock — a hand-crafted, faithful mock of the iOS DayPage
 * (warm-amber editorial detail screen), rendered as pure DOM.
 *
 * Displayed inside <IPhoneFrame> in the Hero. Live HTML (not a
 * screenshot) — stays crisp on retina and light/dark-mode aware.
 *
 * Mirrors ExperienceDetailView in iOS
 * (apps/ios/SoloCompass/Views/Experience/ExperienceDetailView.swift).
 */

export function DayPageMock() {
  return (
    <div className="flex h-[540px] w-[264px] flex-col bg-bg-warm text-fg-primary">
      {/* Status bar */}
      <div className="flex items-center justify-between px-6 pt-3 pb-1">
        <span className="font-body text-[11px] font-semibold">9:41</span>
        <span className="flex items-center gap-1 font-body text-[10px] font-medium">
          <span aria-hidden>●●●●</span>
        </span>
      </div>

      {/* Nav row */}
      <div className="flex items-center justify-between px-4 pt-2 pb-3">
        <button className="flex h-7 w-7 items-center justify-center rounded-full bg-surface-white shadow-xs">
          <span className="text-[14px]" aria-hidden>
            ‹
          </span>
        </button>
        <button className="flex h-7 w-7 items-center justify-center rounded-full bg-surface-white shadow-xs">
          <span className="text-[12px]" aria-hidden>
            ♡
          </span>
        </button>
      </div>

      {/* Hero image — warm gradient */}
      <div
        className="mx-4 h-24 rounded-lg"
        style={{
          background: "linear-gradient(135deg, #F7DEB0 0%, #C9A677 45%, #A07F4B 100%)",
        }}
      />

      {/* Title area */}
      <div className="px-4 pt-4">
        <div className="flex items-center gap-1.5">
          <span className="h-1 w-1 rounded-full bg-sun-gold" />
          <span className="font-mono text-[8px] font-medium uppercase tracking-[0.16em] text-sun-gold-deep">
            Café · Chiang Mai
          </span>
        </div>
        <p className="mt-1.5 font-display text-[17px] font-medium leading-tight text-fg-primary">
          Ristr8to
        </p>
        <p className="mt-1 text-[10px] leading-tight text-fg-muted">
          Third-wave espresso worth walking 15 minutes to. Quiet before 10.
        </p>
      </div>

      {/* Trust chips */}
      <div className="mt-3 flex items-center gap-1.5 px-4">
        <span className="inline-flex items-center gap-1 rounded-full border border-success-text/30 bg-success-soft px-1.5 py-0.5 font-mono text-[7px] font-medium uppercase tracking-[0.12em] text-success-text">
          <span className="h-0.5 w-0.5 rounded-full bg-success-text" />
          Verified · 2d
        </span>
        <span className="inline-flex items-center gap-1 rounded-full bg-accent-soft px-1.5 py-0.5 font-mono text-[7px] font-medium uppercase tracking-[0.12em] text-accent">
          Solo · 4.8
        </span>
      </div>

      {/* Solo score heatmap */}
      <div className="mx-4 mt-4 rounded-lg bg-surface-white p-3 shadow-xs">
        <div className="mb-2 flex items-center justify-between">
          <span className="font-mono text-[8px] font-medium uppercase tracking-[0.16em] text-fg-muted">
            Solo · Score
          </span>
          <span className="font-display text-[13px] font-medium">4.8</span>
        </div>
        <div className="space-y-1.5">
          <ScoreBar label="Quiet" value={0.9} />
          <ScoreBar label="Table" value={0.7} tone="sunGold" />
          <ScoreBar label="Wifi" value={0.6} tone="accent" />
        </div>
      </div>

      {/* Best time */}
      <div className="mx-4 mt-3 rounded-lg border border-border-subtle bg-surface-white p-3">
        <div className="flex items-center justify-between">
          <span className="font-mono text-[8px] font-medium uppercase tracking-[0.16em] text-fg-muted">
            Best now
          </span>
          <span className="font-mono text-[8px] font-medium text-fg-primary">8–10 AM</span>
        </div>
        <div className="mt-2 flex h-2 items-end gap-0.5">
          {[3, 6, 8, 7, 4, 2, 2, 3, 3, 4, 5, 3].map((h, i) => (
            <div
              key={i}
              className={`ds-heatmap-breathe flex-1 rounded-t-sm ${
                i === 1 || i === 2 ? "bg-sun-gold" : "bg-border-subtle"
              }`}
              style={{
                height: `${h * 10}%`,
                animationDelay: `${i * 90}ms`,
              }}
            />
          ))}
        </div>
      </div>

      <div className="grow" />

      {/* Ask Solo bar */}
      <div className="mx-4 mb-3 flex items-center gap-2 rounded-full border border-accent-border bg-accent-soft px-3 py-2">
        <span className="h-4 w-4 rounded-full bg-accent" aria-hidden />
        <span className="text-[10px] text-fg-primary">Ask Solo about here…</span>
      </div>
    </div>
  );
}

function ScoreBar({
  label,
  value,
  tone = "success",
}: {
  label: string;
  value: number;
  tone?: "success" | "sunGold" | "accent";
}) {
  const barColor =
    tone === "sunGold" ? "bg-sun-gold" : tone === "accent" ? "bg-accent" : "bg-success-text";
  return (
    <div className="flex items-center gap-2">
      <span className="w-8 font-mono text-[7px] uppercase tracking-[0.12em] text-fg-muted">
        {label}
      </span>
      <div className="relative h-1 flex-1 overflow-hidden rounded-full bg-border-subtle">
        <div
          className={`absolute inset-y-0 left-0 rounded-full ${barColor}`}
          style={{ width: `${value * 100}%` }}
        />
      </div>
      <span className="w-4 text-right font-mono text-[7px] text-fg-muted">
        {Math.round(value * 10) / 10}
      </span>
    </div>
  );
}
