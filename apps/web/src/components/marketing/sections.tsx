/**
 * Marketing sections — Nav / Hero / Problem / Pillars / Trust / Pricing / Footer
 * Doc: WEB_LANDING_DESIGN.md §4
 *
 * All sections take (copy, locale, homePath) as props so they render identically
 * for /en and /zh routes. The page files (app/page.tsx and app/zh/page.tsx) do
 * the composition — sections know nothing about routing.
 */

import Link from "next/link";
import { Container } from "./Container";
import { ButtonLink, Chip, Eyebrow, IPhoneFrame, Section } from "./primitives";
import { DayPageMock } from "./DayPageMock";
import { HeroCanvas } from "./HeroCanvas";
import { CapabilityMock } from "./CapabilityMocks";
import type { Copy, Locale } from "./copy";

// App Store link — replaced when SKU ships.
const APP_STORE_URL = "https://apps.apple.com/app/solo-compass/id0000000000";

interface Props {
  copy: Copy;
  locale: Locale;
  homePath: string; // "/" or "/zh"
  altPath: string;  // "/zh" or "/"
}

/* ============================================================
   Nav
   ============================================================ */

export function MarketingNav({ copy, locale, homePath, altPath }: Props) {
  const items = [
    { href: `${homePath === "/" ? "" : homePath}/#features`, label: copy.nav.features },
    { href: locale === "zh" ? "/zh/pricing" : "/pricing", label: copy.nav.pricing },
    { href: locale === "zh" ? "/zh/city" : "/city", label: copy.nav.cities },
    { href: locale === "zh" ? "/zh/blog" : "/blog", label: copy.nav.blog },
    { href: locale === "zh" ? "/zh/manifesto" : "/manifesto", label: copy.nav.manifesto },
  ];
  return (
    <nav
      className="sticky top-0 z-40 border-b border-border-subtle/50 backdrop-blur-xl"
      style={{ background: "color-mix(in oklab, var(--bg-warm) 82%, transparent)" }}
    >
      <Container width="wide">
        <div className="flex h-[72px] items-center justify-between gap-6">
          <Link href={homePath} className="flex items-center gap-2 font-display text-[20px] font-medium tracking-tight">
            <SoloCompassMark />
            <span>Solo Compass</span>
          </Link>
          <div className="hidden items-center gap-1 md:flex">
            {items.map((it) => (
              <Link
                key={it.href}
                href={it.href}
                className="group relative rounded-md px-3 py-2 font-body text-[14px] font-normal text-fg-muted transition-colors duration-fast hover:text-fg-primary"
              >
                {it.label}
                <span
                  aria-hidden
                  className="absolute inset-x-3 -bottom-[2px] h-[1.5px] origin-left scale-x-0 bg-accent transition-transform duration-normal ease-decel group-hover:scale-x-100"
                />
              </Link>
            ))}
          </div>
          <div className="flex items-center gap-3">
            <Link
              href={altPath}
              className="hidden font-mono text-[11px] font-medium uppercase tracking-[0.16em] text-fg-muted hover:text-fg-primary md:inline"
            >
              {copy.langSwitch}
            </Link>
            <ButtonLink href={APP_STORE_URL} variant="primary" className="hidden md:inline-flex">
              {copy.nav.getApp}
            </ButtonLink>
          </div>
        </div>
      </Container>
    </nav>
  );
}

function SoloCompassMark() {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" aria-hidden>
      <circle cx="12" cy="12" r="11" fill="none" stroke="var(--accent)" strokeWidth="1.4" />
      <circle cx="12" cy="12" r="2.6" fill="var(--sun-gold)" />
      <path d="M12 2 L14 12 L12 22 L10 12 Z" fill="var(--accent)" opacity="0.85" />
    </svg>
  );
}

/* ============================================================
   Hero — cascading reveal
   ============================================================ */

export function Hero({ copy }: Props) {
  return (
    <Section className="relative overflow-hidden pt-16 md:pt-24">
      <HeroCanvas />
      <Container width="wide" className="relative">
        <div className="grid grid-cols-1 items-center gap-16 md:grid-cols-12 md:gap-8">
          <div className="md:col-span-7">
            <div className="ds-reveal" style={{ animationDelay: "0ms" }}>
              <Eyebrow dot="sun">{copy.hero.eyebrow}</Eyebrow>
            </div>
            <h1 className="ds-display-2xl mt-10 font-display">
              {copy.hero.h1Lines.map((line, i) => (
                <span
                  key={i}
                  className="ds-reveal block"
                  style={{ animationDelay: `${200 + i * 180}ms` }}
                >
                  {line}
                </span>
              ))}
            </h1>
            <p
              className="ds-body-xl ds-reveal mt-10 max-w-xl"
              style={{ animationDelay: "800ms" }}
            >
              {copy.hero.sub}
            </p>
            <div
              className="ds-reveal mt-12 flex flex-wrap items-center gap-6"
              style={{ animationDelay: "1040ms" }}
            >
              <ButtonLink href={APP_STORE_URL} variant="primary">
                <AppleGlyph />
                <span className="ml-2">{copy.hero.ctaPrimary}</span>
              </ButtonLink>
              <a
                href="#features"
                className="font-body text-[16px] font-medium text-fg-primary underline-offset-4 hover:underline"
              >
                {copy.hero.ctaSecondary} →
              </a>
            </div>
          </div>
          <div className="md:col-span-5">
            <div className="ds-reveal-scale flex justify-center md:justify-end" style={{ animationDelay: "200ms" }}>
              <IPhoneFrame tilt>
                <DayPageMock />
              </IPhoneFrame>
            </div>
          </div>
        </div>
      </Container>
    </Section>
  );
}

function AppleGlyph() {
  return (
    <svg width="18" height="20" viewBox="0 0 18 20" fill="currentColor" aria-hidden>
      <path d="M14.7 15.4c-.2.5-.4 1-.7 1.4-.4.6-.7 1-1 1.3-.4.5-.9.7-1.4.7-.4 0-.8-.1-1.4-.3-.6-.2-1.1-.3-1.5-.3-.5 0-1 .1-1.6.3-.6.2-1.1.3-1.4.3-.5 0-1-.2-1.5-.7-.3-.3-.7-.7-1.1-1.4C3.6 15.9 3.3 15 3 14 2.6 12.9 2.5 11.9 2.5 10.9c0-1.1.2-2.1.7-2.9.4-.7.9-1.2 1.5-1.6.6-.4 1.3-.6 2.1-.6.4 0 .9.1 1.5.3.6.2 1 .3 1.2.3.1 0 .5-.1 1.3-.4.7-.3 1.3-.4 1.8-.3 1.4.1 2.5.7 3.2 1.7-1.3.8-1.9 1.9-1.9 3.3 0 1.1.4 2 1.2 2.8.4.3.7.6 1.1.8-.1.2-.2.5-.4.8Zm-3.5-11c0 .8-.3 1.6-.9 2.3-.7.8-1.6 1.3-2.6 1.2 0-.9.3-1.7.9-2.4.3-.4.7-.7 1.2-.9.4-.2.8-.3 1.2-.3.1.1.1.1.2.1Z" />
    </svg>
  );
}

/* ============================================================
   Problem — editorial monologue
   ============================================================ */

export function Problem({ copy }: Props) {
  return (
    <Section className="border-t border-border-subtle/50">
      <Container width="narrow">
        <Eyebrow dot="omen">{copy.problem.eyebrow}</Eyebrow>
        <div className="mt-12 space-y-8">
          {copy.problem.paragraphs.map((p, i) => (
            <p
              key={i}
              className={`font-body text-[22px] leading-[1.7] ${
                i === copy.problem.paragraphs.length - 1
                  ? "text-fg-primary font-medium"
                  : i < 2
                  ? "text-fg-primary"
                  : "text-fg-muted"
              }`}
            >
              {renderMuted(p.text, p.muted)}
            </p>
          ))}
        </div>
      </Container>
    </Section>
  );
}

function renderMuted(text: string, muted?: string[]): React.ReactNode {
  if (!muted?.length) return text;
  const parts: React.ReactNode[] = [text];
  muted.forEach((m, idx) => {
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (typeof part === "string" && part.includes(m)) {
        const [before, ...rest] = part.split(m);
        const after = rest.join(m);
        parts.splice(
          i,
          1,
          before,
          <span key={`m-${idx}`} className="text-fg-muted font-medium">
            {m}
          </span>,
          after,
        );
        break;
      }
    }
  });
  return <>{parts}</>;
}

/* ============================================================
   Pillars — three warm cards
   ============================================================ */

export function Pillars({ copy }: Props) {
  return (
    <Section id="features" className="border-t border-border-subtle/50">
      <Container>
        <div className="max-w-2xl">
          <Eyebrow dot="sun">{copy.pillars.eyebrow}</Eyebrow>
          <h2 className="ds-display-lg mt-6 font-display">{copy.pillars.title}</h2>
          <p className="ds-body-xl mt-6">{copy.pillars.sub}</p>
        </div>
        <div className="mt-16 grid grid-cols-1 gap-6 md:grid-cols-3">
          {copy.pillars.items.map((item, i) => (
            <article
              key={i}
              className="group flex flex-col rounded-lg border border-border-subtle bg-surface-white p-8 pt-10 transition-all duration-editorial ease-decel hover:-translate-y-1 hover:border-border-default hover:shadow-lg"
            >
              <span
                className={`h-3 w-3 rounded-full ${
                  item.dot === "sun"
                    ? "bg-sun-gold"
                    : item.dot === "omen"
                    ? "bg-omen-gold"
                    : "bg-accent"
                }`}
                aria-hidden
              />
              <h3 className="ds-display-sm mt-6 font-display">{item.title}</h3>
              <p className="ds-body-md mt-4 text-fg-muted">{item.body}</p>
            </article>
          ))}
        </div>
      </Container>
    </Section>
  );
}

/* ============================================================
   Capabilities — six product screens (deep app tie-in)
   ============================================================ */

type CapKind = "askSolo" | "blindbox" | "capsule" | "omen" | "bestNow" | "brag";

const CAPABILITY_ORDER: {
  kind: CapKind;
  bulletsKey: "askSolo" | "blindbox" | "capsule" | "omen" | "bestNow" | "brag";
}[] = [
  { kind: "askSolo", bulletsKey: "askSolo" },
  { kind: "blindbox", bulletsKey: "blindbox" },
  { kind: "capsule", bulletsKey: "capsule" },
  { kind: "omen", bulletsKey: "omen" },
  { kind: "bestNow", bulletsKey: "bestNow" },
  { kind: "brag", bulletsKey: "brag" },
];

export function Capabilities({ copy }: Props) {
  return (
    <Section id="features" className="relative bg-bg-warm">
      <Container width="wide">
        <div className="max-w-[720px]">
          <Eyebrow dot="sun">{copy.capabilities.eyebrow}</Eyebrow>
          <h2 className="ds-display-xl mt-6 font-display">{copy.capabilities.title}</h2>
          <p className="ds-body-lg mt-6 text-fg-muted">{copy.capabilities.sub}</p>
          <p className="ds-body-md mt-3 font-mono uppercase tracking-[0.14em] text-fg-subtle">
            {copy.capabilities.intro}
          </p>
        </div>

        <div className="mt-20 space-y-32">
          {CAPABILITY_ORDER.map(({ kind }, i) => {
            const block = copy[kind];
            const flip = i % 2 === 1;
            return (
              <article
                key={kind}
                data-capability={kind}
                className="grid grid-cols-1 items-center gap-12 md:grid-cols-2 md:gap-20"
              >
                <div className={flip ? "md:order-2" : ""}>
                  <div className="flex justify-center">
                    <IPhoneFrame tilt={i % 3 === 1} className="max-w-[280px]">
                      <CapabilityMock kind={kind} copy={copy} />
                    </IPhoneFrame>
                  </div>
                </div>
                <div className={flip ? "md:order-1" : ""}>
                  <Chip
                    tone={
                      kind === "askSolo"
                        ? "accent"
                        : kind === "blindbox"
                        ? "warning"
                        : kind === "capsule"
                        ? "accent"
                        : kind === "omen"
                        ? "sun"
                        : kind === "bestNow"
                        ? "success"
                        : "sun"
                    }
                  >
                    {block.eyebrow}
                  </Chip>
                  <h3 className="ds-display-lg mt-6 font-display">{block.title}</h3>
                  <p className="ds-body-lg mt-6 text-fg-muted">{block.body}</p>
                  <ul className="mt-8 space-y-4">
                    {block.bullets.map((b, bi) => (
                      <li key={bi} className="flex gap-3">
                        <span
                          aria-hidden
                          className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-accent"
                        />
                        <span className="ds-body-md text-fg-primary">{b}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              </article>
            );
          })}
        </div>
      </Container>
    </Section>
  );
}

/* ============================================================
   Trust — three promises
   ============================================================ */

export function Trust({ copy }: Props) {
  return (
    <Section
      className="relative bg-surface-sunken"
      style={{
        // Soft warm-white bleed at both edges — no hard border, no fake "card
        // dropped into the page" look. Trust is a valley of quieter light.
        boxShadow:
          "inset 0 24px 32px -32px rgba(31,26,20,0.05), inset 0 -24px 32px -32px rgba(31,26,20,0.05)",
      }}
    >
      <Container width="narrow">
        <Eyebrow dot="accent">{copy.trust.eyebrow}</Eyebrow>
        <h2 className="ds-display-xl mt-6 font-display">{copy.trust.title}</h2>
        <div className="mt-16 space-y-12 divide-y divide-border-subtle">
          {copy.trust.items.map((item, i) => (
            <div key={i} className={i === 0 ? "" : "pt-12"}>
              <h3 className="font-display text-[26px] font-medium leading-tight text-fg-primary">
                {item.heading}
              </h3>
              <p className="ds-body-lg mt-4 text-fg-muted">{item.body}</p>
            </div>
          ))}
        </div>
      </Container>
    </Section>
  );
}

/* ============================================================
   Pricing — two-card comparison
   ============================================================ */

export function Pricing({ copy, locale }: Props) {
  const pricingPath = locale === "zh" ? "/zh/pricing" : "/pricing";
  return (
    <Section id="pricing" className="border-t border-border-subtle/50">
      <Container>
        <div className="mx-auto max-w-2xl text-center">
          <Eyebrow dot="accent" className="justify-center">
            {copy.pricing.eyebrow}
          </Eyebrow>
          <h2 className="ds-display-lg mt-6 font-display">{copy.pricing.title}</h2>
          <p className="ds-body-xl mt-6 text-fg-muted">{copy.pricing.sub}</p>
        </div>

        <div className="mx-auto mt-16 grid max-w-4xl grid-cols-1 gap-6 md:grid-cols-2">
          {/* Lifetime */}
          <article className="flex flex-col rounded-xl border border-border-default bg-surface-white p-10">
            <div className="flex items-baseline justify-between">
              <h3 className="font-display text-[22px] font-medium">{copy.pricing.lifetime.name}</h3>
            </div>
            <div className="mt-6 flex items-baseline gap-2">
              <span className="ds-display-lg font-display">{copy.pricing.lifetime.price}</span>
              <span className="ds-body-sm">{copy.pricing.lifetime.pricePer}</span>
            </div>
            <p className="ds-body-md mt-4 text-fg-muted">{copy.pricing.lifetime.tagline}</p>
            <ul className="mt-8 space-y-3">
              {copy.pricing.lifetime.features.map((f, i) => (
                <li key={i} className="flex items-start gap-3 font-body text-[15px] text-fg-primary">
                  <CheckGlyph />
                  <span>{f}</span>
                </li>
              ))}
            </ul>
            <div className="mt-10">
              <ButtonLink href={APP_STORE_URL} variant="secondary" className="w-full">
                {copy.pricing.lifetime.cta}
              </ButtonLink>
            </div>
          </article>

          {/* Yearly */}
          <article className="relative flex flex-col rounded-xl border border-accent-border bg-accent-soft p-10 shadow-sm">
            <Chip tone="accent" className="absolute -top-3 left-8">
              {copy.pricing.yearly.badge}
            </Chip>
            <div className="flex items-baseline justify-between">
              <h3 className="font-display text-[22px] font-medium">{copy.pricing.yearly.name}</h3>
            </div>
            <div className="mt-6 flex items-baseline gap-2">
              <span className="ds-display-lg font-display">{copy.pricing.yearly.price}</span>
              <span className="ds-body-sm">{copy.pricing.yearly.pricePer}</span>
            </div>
            <p className="ds-body-md mt-4 text-fg-muted">{copy.pricing.yearly.tagline}</p>
            <ul className="mt-8 space-y-3">
              {copy.pricing.yearly.features.map((f, i) => (
                <li key={i} className="flex items-start gap-3 font-body text-[15px] text-fg-primary">
                  <CheckGlyph filled />
                  <span>{f}</span>
                </li>
              ))}
            </ul>
            <div className="mt-10">
              <ButtonLink href={APP_STORE_URL} variant="primary" className="w-full">
                {copy.pricing.yearly.cta}
              </ButtonLink>
            </div>
          </article>
        </div>

        <div className="mt-10 text-center">
          <Link
            href={pricingPath}
            className="font-body text-[15px] text-fg-muted underline-offset-4 hover:text-fg-primary hover:underline"
          >
            {copy.pricing.free} →
          </Link>
        </div>
      </Container>
    </Section>
  );
}

function CheckGlyph({ filled }: { filled?: boolean }) {
  return (
    <span
      aria-hidden
      className={`mt-[3px] flex h-4 w-4 shrink-0 items-center justify-center rounded-full ${
        filled ? "bg-accent text-bg-warm" : "border border-border-default text-fg-primary"
      }`}
    >
      <svg width="9" height="9" viewBox="0 0 9 9" fill="none">
        <path
          d="M1.5 4.5 L3.5 6.5 L7.5 2.5"
          stroke="currentColor"
          strokeWidth="1.6"
          strokeLinecap="round"
          strokeLinejoin="round"
        />
      </svg>
    </span>
  );
}

/* ============================================================
   Footer
   ============================================================ */

export function Footer({ copy }: Props) {
  return (
    <footer className="border-t border-border-subtle bg-surface-sunken pt-24 pb-16">
      <Container>
        <p className="ds-body-lg max-w-2xl text-fg-primary">{copy.footer.tagline}</p>
        <div className="mt-16 grid grid-cols-2 gap-8 md:grid-cols-4">
          <div className="col-span-2 md:col-span-1">
            <div className="flex items-center gap-2 font-display text-[18px] font-medium">
              <SoloCompassMark />
              Solo Compass
            </div>
          </div>
          {copy.footer.columns.map((col) => (
            <div key={col.heading}>
              <h4 className="font-mono text-[11px] font-medium uppercase tracking-[0.16em] text-fg-subtle">
                {col.heading}
              </h4>
              <ul className="mt-4 space-y-3">
                {col.links.map((l) => (
                  <li key={l.href}>
                    <Link
                      href={l.href}
                      className="font-body text-[15px] text-fg-muted hover:text-fg-primary"
                    >
                      {l.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
        <div className="mt-16 border-t border-border-subtle pt-8 font-body text-[13px] text-fg-subtle">
          {copy.footer.bottom}
        </div>
      </Container>
    </footer>
  );
}
