"use client";

/**
 * CapabilityMocks — six live-DOM iPhone content mocks, one per capability.
 * Each is meant to be rendered inside <IPhoneFrame>. Dimensions match
 * DayPageMock (264×540). Editorial motion via CSS keyframes only.
 *
 * Called from: marketing/sections.tsx (Capabilities section)
 */

import type { Copy } from "./copy";

type Kind = "askSolo" | "blindbox" | "capsule" | "omen" | "bestNow" | "brag";

export function CapabilityMock({ kind, copy }: { kind: Kind; copy: Copy }) {
  switch (kind) {
    case "askSolo":
      return <AskSoloMock copy={copy} />;
    case "blindbox":
      return <BlindboxMock copy={copy} />;
    case "capsule":
      return <CapsuleMock copy={copy} />;
    case "omen":
      return <OmenMock copy={copy} />;
    case "bestNow":
      return <BestNowMock copy={copy} />;
    case "brag":
      return <BragMock copy={copy} />;
  }
}

function ScreenFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex h-[540px] w-[264px] flex-col bg-bg-warm text-fg-primary">
      <div className="flex items-center justify-between px-6 pt-3 pb-1">
        <span className="font-body text-[11px] font-semibold">9:41</span>
        <span className="flex items-center gap-1 font-body text-[10px] font-medium">
          <span aria-hidden>●●●●</span>
        </span>
      </div>
      {children}
    </div>
  );
}

/* 01 · Ask Solo — chat sheet */
function AskSoloMock({ copy }: { copy: Copy }) {
  return (
    <ScreenFrame>
      <div className="px-4 pt-2 pb-3">
        <span className="font-mono text-[8px] font-medium uppercase tracking-[0.16em] text-fg-muted">
          Ask Solo
        </span>
      </div>
      <div className="mx-4 mt-1 flex justify-end">
        <div className="max-w-[85%] rounded-xl rounded-br-sm bg-accent px-3 py-2 text-[10px] leading-snug text-bg-warm">
          {copy.askSolo.demoUser}
        </div>
      </div>
      <div className="mx-4 mt-3 flex items-center gap-1.5">
        <span className="h-1 w-1 rounded-full bg-omen-gold animate-pulse" />
        <span className="font-mono text-[7px] uppercase tracking-[0.14em] text-fg-muted">
          Reasoning · 3 sources · 12 candidates
        </span>
      </div>
      <div className="mx-4 mt-2">
        <div className="max-w-[92%] rounded-xl rounded-bl-sm border border-border-subtle bg-surface-white px-3 py-2">
          <p className="text-[10px] font-medium leading-snug">{copy.askSolo.demoAgent}</p>
          <p className="mt-1 text-[9px] leading-snug text-fg-muted">{copy.askSolo.demoReason}</p>
        </div>
      </div>
      <div className="mx-4 mt-3 flex gap-1.5 overflow-hidden">
        {[
          { hue: "linear-gradient(135deg,#F7DEB0,#C9A677)", name: "Ristr8to", meta: "8 min · 4.8" },
          { hue: "linear-gradient(135deg,#EAD9B8,#B18F5B)", name: "Akha Ama", meta: "6 min · 4.7" },
          { hue: "linear-gradient(135deg,#F0CC8B,#A07F4B)", name: "Graph.", meta: "11 min · 4.6" },
        ].map((c, i) => (
          <div
            key={i}
            className="flex w-[76px] shrink-0 flex-col overflow-hidden rounded-md border border-border-subtle bg-surface-white shadow-xs"
          >
            <div className="h-8" style={{ background: c.hue }} />
            <div className="px-1.5 py-1">
              <div className="text-[8px] font-medium leading-tight">{c.name}</div>
              <div className="mt-0.5 font-mono text-[6.5px] uppercase text-fg-muted">{c.meta}</div>
            </div>
          </div>
        ))}
      </div>
      <div className="grow" />
      <div className="mx-4 mb-3 flex items-center gap-2 rounded-full border border-accent-border bg-accent-soft px-3 py-2">
        <span className="h-2 w-2 rounded-full bg-accent" aria-hidden />
        <span className="text-[10px] text-fg-muted">Hold to talk…</span>
      </div>
    </ScreenFrame>
  );
}

/* 02 · Blindbox */
function BlindboxMock({ copy }: { copy: Copy }) {
  return (
    <ScreenFrame>
      <div className="px-4 pt-2 pb-3">
        <span className="font-mono text-[8px] font-medium uppercase tracking-[0.16em] text-fg-muted">
          Blindbox
        </span>
      </div>
      <div
        className="relative mx-4 mt-2 flex flex-col items-center overflow-hidden rounded-xl p-4"
        style={{
          background: "radial-gradient(circle at 50% 40%, #F7DEB0 0%, #C9A677 55%, #6E5432 100%)",
        }}
      >
        <div className="relative flex h-24 w-24 items-center justify-center">
          <div className="absolute inset-0 rounded-full border border-white/40 sc-halo-pulse" />
          <div
            className="absolute inset-2 rounded-full border border-white/30 sc-halo-pulse"
            style={{ animationDelay: "600ms" }}
          />
          <div
            className="absolute inset-4 rounded-full border border-white/20 sc-halo-pulse"
            style={{ animationDelay: "1200ms" }}
          />
          <div className="flex h-14 w-14 items-center justify-center rounded-full bg-bg-warm/90 shadow-lg">
            <span className="font-serif text-[22px] font-medium text-fg-primary">✦</span>
          </div>
        </div>
        <p className="mt-3 text-center font-mono text-[8px] uppercase tracking-[0.14em] text-bg-warm/90">
          {copy.blindbox.cardHint}
        </p>
      </div>
      <div className="mx-4 mt-3 rounded-lg border border-border-subtle bg-surface-white p-3">
        <div className="flex items-center gap-1.5">
          <span className="h-1 w-1 rounded-full bg-omen-gold" />
          <span className="font-mono text-[7px] uppercase tracking-[0.14em] text-omen-gold-deep">
            Revealed
          </span>
        </div>
        <p className="mt-1 font-display text-[13px] leading-tight">{copy.blindbox.cardReveal}</p>
        <p className="mt-1.5 text-[9px] leading-snug text-fg-muted">{copy.blindbox.cardReason}</p>
      </div>
      <div className="grow" />
      <div className="mx-4 mb-3 flex items-center justify-center gap-2 rounded-full bg-fg-primary px-3 py-2">
        <span className="text-[10px] font-medium text-bg-warm">Commit · Take me there</span>
      </div>
    </ScreenFrame>
  );
}

/* 03 · Time Capsule */
function CapsuleMock({ copy }: { copy: Copy }) {
  return (
    <ScreenFrame>
      <div className="px-4 pt-2 pb-3">
        <span className="font-mono text-[8px] font-medium uppercase tracking-[0.16em] text-fg-muted">
          Time Capsule
        </span>
      </div>
      <div
        className="relative mx-4 h-32 overflow-hidden rounded-lg"
        style={{
          background: "linear-gradient(180deg, #EAD9B8 0%, #D6BE93 55%, #B79E70 100%)",
        }}
      >
        <svg className="absolute inset-0 h-full w-full opacity-40" viewBox="0 0 200 128">
          <path d="M 0 40 Q 60 30 120 55 T 200 70" stroke="#A07F4B" strokeWidth="1" fill="none" />
          <path d="M 30 128 Q 70 90 90 60 T 140 0" stroke="#A07F4B" strokeWidth="1" fill="none" />
          <path d="M 0 100 L 200 90" stroke="#A07F4B" strokeWidth="0.6" fill="none" />
        </svg>
        <div className="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2">
          <div className="relative flex flex-col items-center">
            <div className="h-3 w-3 rounded-full bg-fg-primary ring-4 ring-bg-warm/70" />
            <div className="mt-0.5 h-4 w-px bg-fg-primary" />
          </div>
        </div>
        <div className="absolute left-1/2 top-1/2 h-16 w-16 -translate-x-1/2 -translate-y-1/2 rounded-full border border-fg-primary/40 sc-halo-pulse" />
      </div>
      <div className="mx-4 mt-3 rounded-lg border border-border-subtle bg-surface-white p-3 shadow-xs">
        <div className="flex items-center gap-1.5">
          <span className="h-1 w-1 rounded-full bg-omen-gold" />
          <span className="font-mono text-[7px] font-medium uppercase tracking-[0.14em] text-omen-gold-deep">
            {copy.capsule.sealTitle}
          </span>
        </div>
        <p className="mt-1 font-mono text-[7px] text-fg-muted">{copy.capsule.sealMeta}</p>
        <p className="mt-2 font-serif text-[11px] italic leading-snug text-fg-primary">
          {copy.capsule.sealBody}
        </p>
      </div>
      <div className="grow" />
      <div className="mx-4 mb-3 flex items-center justify-between rounded-full border border-fg-primary/30 bg-bg-warm px-3 py-2">
        <span className="font-mono text-[8px] uppercase tracking-[0.12em] text-fg-muted">
          Seal for
        </span>
        <div className="flex gap-1">
          <span className="rounded-full bg-surface-white px-1.5 py-0.5 font-mono text-[7px] text-fg-muted">
            1m
          </span>
          <span className="rounded-full bg-fg-primary px-1.5 py-0.5 font-mono text-[7px] text-bg-warm">
            6m
          </span>
          <span className="rounded-full bg-surface-white px-1.5 py-0.5 font-mono text-[7px] text-fg-muted">
            1y
          </span>
        </div>
      </div>
    </ScreenFrame>
  );
}

/* 04 · Daily Omen */
function OmenMock({ copy }: { copy: Copy }) {
  return (
    <ScreenFrame>
      <div className="px-4 pt-2 pb-3">
        <span className="font-mono text-[8px] font-medium uppercase tracking-[0.16em] text-fg-muted">
          Daily Omen
        </span>
      </div>
      <div
        className="mx-4 mt-4 flex flex-col items-stretch overflow-hidden rounded-xl border border-omen-gold-soft"
        style={{
          background: "linear-gradient(160deg, #FFF6E4 0%, #F7DEB0 55%, #E5C48A 100%)",
        }}
      >
        <div className="flex items-center justify-between border-b border-omen-gold-soft/60 px-3 py-1.5">
          <span className="font-mono text-[7px] uppercase tracking-[0.14em] text-omen-gold-deep">
            {copy.omen.cardDate}
          </span>
          <span className="font-serif text-[10px] text-omen-gold-deep">✦</span>
        </div>
        <div className="px-4 py-4">
          <p className="font-serif text-[15px] font-medium leading-tight text-fg-primary">
            {copy.omen.cardTitle}
          </p>
          <p className="mt-2 text-[10px] leading-snug text-fg-muted">{copy.omen.cardLine}</p>
        </div>
        <div className="flex items-center justify-end gap-1 px-3 pb-2">
          <span className="h-0.5 w-0.5 rounded-full bg-omen-gold" />
          <span className="font-mono text-[7px] uppercase tracking-[0.12em] text-omen-gold-deep">
            drawn 7:12 am
          </span>
        </div>
      </div>
      <div className="mx-4 mt-3 flex items-center gap-2 rounded-lg border border-border-subtle bg-surface-white px-3 py-2 opacity-70">
        <span className="font-mono text-[7px] uppercase tracking-[0.14em] text-fg-muted">
          Yesterday
        </span>
        <span className="text-[9px] text-fg-muted">Notice the color of doors.</span>
      </div>
      <div className="grow" />
      <div className="mx-4 mb-3 flex items-center gap-2 rounded-full border border-border-subtle bg-bg-warm px-3 py-2">
        <span className="h-2 w-2 rounded-full bg-omen-gold" />
        <span className="text-[10px] text-fg-muted">Tomorrow at 7:00 AM · next omen</span>
      </div>
    </ScreenFrame>
  );
}

/* 05 · Best Now */
function BestNowMock({ copy }: { copy: Copy }) {
  return (
    <ScreenFrame>
      <div className="px-4 pt-2 pb-3">
        <span className="font-mono text-[8px] font-medium uppercase tracking-[0.16em] text-fg-muted">
          Best Now
        </span>
      </div>
      <div className="mx-4 mt-2 rounded-xl bg-fg-primary p-4 text-bg-warm">
        <div className="flex items-center gap-1.5">
          <span className="h-1.5 w-1.5 rounded-full bg-sun-gold animate-pulse" />
          <span className="font-mono text-[7px] uppercase tracking-[0.14em] text-bg-warm/70">
            Live · updated 4s ago
          </span>
        </div>
        <p className="mt-2 font-display text-[22px] font-medium leading-none tracking-tight">
          {copy.bestNow.peakLabel}
        </p>
        <p className="mt-1 font-mono text-[9px] uppercase tracking-[0.14em] text-sun-gold">
          {copy.bestNow.peakWindow}
        </p>
        <p className="mt-2 text-[9px] leading-snug text-bg-warm/80">{copy.bestNow.peakReason}</p>
      </div>
      <div className="mx-4 mt-4">
        <div className="mb-1.5 flex items-center justify-between">
          <span className="font-mono text-[7px] uppercase tracking-[0.14em] text-fg-muted">
            24 hours · Tue
          </span>
          <span className="font-mono text-[7px] text-fg-muted">now</span>
        </div>
        <div className="flex h-6 items-end gap-[2px]">
          {[
            0.1, 0.05, 0.05, 0.05, 0.1, 0.2, 0.4, 0.55, 0.62, 0.5, 0.35, 0.28, 0.32, 0.4, 0.45,
            0.55, 0.7, 0.92, 0.98, 0.85, 0.55, 0.3, 0.18, 0.1,
          ].map((v, i) => {
            const isPeak = i === 17 || i === 18;
            const isNow = i === 16;
            const bg = isPeak
              ? "bg-sun-gold"
              : isNow
                ? "bg-accent"
                : v > 0.5
                  ? "bg-sun-gold-soft"
                  : "bg-border-subtle";
            return (
              <div
                key={i}
                className={`flex-1 rounded-t-sm ${bg}`}
                style={{ height: `${Math.max(6, v * 100)}%` }}
              />
            );
          })}
        </div>
        <div className="mt-1 flex items-center justify-between font-mono text-[6px] uppercase text-fg-muted">
          <span>00</span>
          <span>06</span>
          <span>12</span>
          <span>18</span>
          <span>24</span>
        </div>
      </div>
      <div className="grow" />
      <div className="mx-4 mb-3 flex items-center justify-center gap-2 rounded-full bg-accent px-3 py-2">
        <span className="text-[10px] font-medium text-bg-warm">Walk there · 12 min</span>
      </div>
    </ScreenFrame>
  );
}

/* 06 · Brag Card */
function BragMock({ copy }: { copy: Copy }) {
  return (
    <ScreenFrame>
      <div className="px-4 pt-2 pb-3">
        <span className="font-mono text-[8px] font-medium uppercase tracking-[0.16em] text-fg-muted">
          Brag Card
        </span>
      </div>
      <div className="mx-4 mt-2 overflow-hidden rounded-xl border border-fg-primary/15 bg-surface-white shadow-lg">
        <div
          className="relative px-4 py-3"
          style={{
            background: "linear-gradient(135deg,#F7DEB0 0%,#C9A677 60%,#8B6D3E 100%)",
          }}
        >
          <div className="flex items-center justify-between">
            <span className="font-mono text-[7px] font-semibold uppercase tracking-[0.16em] text-bg-warm">
              Solo Compass · Passport
            </span>
            <span className="font-serif text-[11px] text-bg-warm">✦</span>
          </div>
          <p className="mt-2 font-display text-[15px] font-medium leading-tight text-bg-warm">
            {copy.brag.cardName}
          </p>
          <p className="mt-0.5 font-mono text-[7px] uppercase tracking-[0.14em] text-bg-warm/80">
            {copy.brag.cardMeta}
          </p>
        </div>
        <div className="flex h-2 items-center bg-surface-white">
          <div className="mx-2 flex-1 border-t border-dashed border-fg-primary/25" />
        </div>
        <div className="grid grid-cols-3 gap-1 px-3 pb-3 pt-1">
          {[
            { n: "34", l: copy.brag.cardStat1 },
            { n: "47.2", l: copy.brag.cardStat2 },
            { n: "1", l: copy.brag.cardStat3 },
          ].map((s, i) => (
            <div key={i} className="text-center">
              <div className="font-display text-[18px] font-medium leading-none">{s.n}</div>
              <div className="mt-0.5 font-mono text-[6.5px] uppercase tracking-[0.14em] text-fg-muted">
                {s.l}
              </div>
            </div>
          ))}
        </div>
        <p className="px-3 pb-3 font-serif text-[10px] italic leading-snug text-fg-muted">
          {copy.brag.cardLine}
        </p>
      </div>
      <div className="grow" />
      <div className="mx-4 mb-3 flex items-center justify-between rounded-full border border-border-subtle bg-bg-warm px-3 py-2">
        <span className="font-mono text-[7px] uppercase tracking-[0.14em] text-fg-muted">
          Share as
        </span>
        <div className="flex gap-1">
          <span className="rounded-full bg-fg-primary px-1.5 py-0.5 font-mono text-[7px] text-bg-warm">
            image
          </span>
          <span className="rounded-full bg-surface-white px-1.5 py-0.5 font-mono text-[7px] text-fg-muted">
            print
          </span>
        </div>
      </div>
    </ScreenFrame>
  );
}
