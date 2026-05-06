"use client";

/**
 * Scenario C — `/trip/[slug]`
 * Public, shareable trip recap. 760-wide article, magazine-style.
 *
 * Layout:
 *   - Browser bar mock with Share button
 *   - Hero: eyebrow / Fraunces serif title / intro / 4-col stats row
 *   - Pull quote with accent left-border
 *   - Day cards (60 / 1fr / 80 grid)
 *   - Dark CTA panel
 *   - Footer credit
 */

import Link from "next/link";
import { notFound, useParams, useSearchParams } from "next/navigation";
import { useMemo } from "react";
import { findTripBySlug, type Trip } from "@/lib/trips-data";

const FONT_DISPLAY = '-apple-system, "SF Pro Display", "Inter", system-ui, sans-serif';
const FONT_MONO = '"JetBrains Mono", "SF Mono", ui-monospace, monospace';
const FONT_SERIF = '"Fraunces", Georgia, "Cormorant Garamond", serif';
const FONT_CN = '"PingFang SC", "Hiragino Sans GB", system-ui, sans-serif';

type Lang = "zh" | "en";

export default function TripPage() {
  const params = useParams<{ slug: string }>();
  const search = useSearchParams();
  const lang: Lang = search.get("lang") === "en" ? "en" : "zh";
  const trip = useMemo(() => findTripBySlug(params.slug), [params.slug]);
  if (!trip) notFound();
  return <TripRecap trip={trip} lang={lang} />;
}

function TripRecap({ trip, lang }: { trip: Trip; lang: Lang }) {
  const fontStack = lang === "zh" ? FONT_CN : FONT_DISPLAY;

  const T =
    lang === "zh"
      ? {
          by: "作者",
          solo: "独自",
          stats: { walked: "走了", places: "体验", favorite: "最爱" },
          dayLabels: ["第一天", "第二天", "第三天", "第四天"],
          cta1: "想做你自己的？",
          cta2: "免费 · 不用账号",
          cta3: "从你在的地方开始",
          poweredBy: "由 Solo Compass 整理 · 你的故事，你拥有",
          share: "分享",
          km: "公里",
        }
      : {
          by: "A trip by",
          solo: "Solo",
          stats: { walked: "Walked", places: "Places", favorite: "Favorite" },
          dayLabels: ["Day 1", "Day 2", "Day 3", "Day 4"],
          cta1: "Want to make yours?",
          cta2: "Free · no account",
          cta3: "Start from where you are",
          poweredBy: "Made with Solo Compass · Your story, yours",
          share: "Share",
          km: "km",
        };

  const monthLabel = lang === "zh" ? trip.monthLabelZh : trip.monthLabel;
  const title = lang === "zh" ? trip.titleZh : trip.titleEn;
  const intro = lang === "zh" ? trip.introZh : trip.intro;
  const quote = lang === "zh" ? trip.quoteZh : trip.quote;

  return (
    <main
      style={{
        minHeight: "100vh",
        background: "#F1ECDF",
        padding: "48px 24px 80px",
        fontFamily: fontStack,
        color: "#1A1612",
      }}
    >
      <article
        style={{
          maxWidth: 760,
          margin: "0 auto",
          background: "#F8F4ED",
          borderRadius: 12,
          overflow: "hidden",
          boxShadow: "0 1px 3px rgba(0,0,0,0.05)",
          border: "0.5px solid #E5DDCD",
        }}
      >
        {/* Top bar */}
        <div
          style={{
            padding: "12px 22px",
            borderBottom: "0.5px solid #E5DDCD",
            display: "flex",
            alignItems: "center",
            gap: 10,
            background: "#FBF7F0",
          }}
        >
          <div
            style={{
              width: 18,
              height: 18,
              borderRadius: 9,
              background: "linear-gradient(135deg, #FFE7C4, #C98628)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <svg width="9" height="9" viewBox="0 0 14 14" fill="none">
              <circle cx="7" cy="7" r="5.5" stroke="#FFF" strokeWidth="1" />
            </svg>
          </div>
          <span
            style={{
              fontFamily: FONT_MONO,
              fontSize: 11,
              color: "#8A7860",
              letterSpacing: 0.5,
            }}
          >
            compass.io / {trip.author.toLowerCase().replace(/\s+/g, "-")} / {trip.slug}
          </span>
          <span style={{ flex: 1 }} />
          <button
            type="button"
            style={{
              padding: "4px 10px",
              borderRadius: 4,
              background: "transparent",
              border: "0.5px solid #D6CEC0",
              fontFamily: fontStack,
              fontSize: 11,
              color: "var(--accent)",
              cursor: "pointer",
            }}
          >
            ↗ {T.share}
          </button>
        </div>

        {/* Hero */}
        <div style={{ padding: "40px 56px 32px" }}>
          <div
            style={{
              fontFamily: FONT_MONO,
              fontSize: 10,
              color: "#A39F99",
              letterSpacing: 2,
              textTransform: "uppercase",
              marginBottom: 18,
            }}
          >
            {T.by} · {trip.author} · {monthLabel}
          </div>
          <h1
            style={{
              fontFamily: lang === "zh" ? FONT_CN : FONT_SERIF,
              fontSize: lang === "zh" ? 44 : 56,
              fontWeight: lang === "zh" ? 600 : 400,
              fontStyle: lang === "zh" ? "normal" : "italic",
              lineHeight: 1.05,
              letterSpacing: lang === "zh" ? "-0.5px" : "-1.5px",
              color: "#1A1612",
              margin: "0 0 14px",
            }}
          >
            {title}
          </h1>
          <div
            style={{
              fontFamily: fontStack,
              fontSize: 16,
              lineHeight: 1.55,
              color: "#5C4F3E",
              maxWidth: 520,
              marginBottom: 26,
            }}
          >
            {intro}
          </div>

          {/* Stats row */}
          <div
            style={{
              display: "flex",
              gap: 0,
              padding: "14px 0",
              borderTop: "0.5px solid #E5DDCD",
              borderBottom: "0.5px solid #E5DDCD",
            }}
          >
            {(
              [
                {
                  label: T.stats.walked,
                  value: `${trip.stats.walkedKm} ${T.km}`,
                  mono: true,
                  accent: false,
                },
                {
                  label: T.stats.places,
                  value: String(trip.stats.places),
                  mono: true,
                  accent: false,
                },
                {
                  label: T.stats.favorite,
                  value: trip.stats.favorite,
                  mono: false,
                  accent: false,
                },
                { label: T.solo, value: "★", mono: false, accent: true },
              ] as const
            ).map((s, i) => (
              <div
                key={s.label}
                style={{
                  flex: 1,
                  borderLeft: i > 0 ? "0.5px solid #E5DDCD" : "none",
                  padding: i === 0 ? "0 16px 0 0" : "0 16px",
                }}
              >
                <div
                  style={{
                    fontFamily: FONT_MONO,
                    fontSize: 9.5,
                    color: "#A39F99",
                    letterSpacing: 1,
                    textTransform: "uppercase",
                    marginBottom: 6,
                  }}
                >
                  {s.label}
                </div>
                <div
                  style={{
                    fontFamily: s.mono ? FONT_MONO : lang === "zh" ? FONT_CN : FONT_SERIF,
                    fontSize: s.mono ? 18 : 16,
                    fontWeight: s.mono ? 500 : 600,
                    fontStyle: !s.mono && lang !== "zh" ? "italic" : "normal",
                    color: s.accent ? "var(--accent-amber)" : "#1A1612",
                    letterSpacing: s.mono ? 0 : "-0.2px",
                  }}
                >
                  {s.value}
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Pull quote */}
        <div style={{ padding: "0 56px 36px" }}>
          <div
            style={{
              fontFamily: lang === "zh" ? FONT_CN : FONT_SERIF,
              fontSize: lang === "zh" ? 20 : 24,
              fontStyle: lang === "zh" ? "normal" : "italic",
              fontWeight: lang === "zh" ? 500 : 400,
              lineHeight: 1.4,
              color: "#1A1612",
              paddingLeft: 18,
              borderLeft: "2px solid var(--accent-amber)",
              letterSpacing: "-0.2px",
            }}
          >
            “{quote}”
          </div>
        </div>

        {/* Day cards */}
        <div style={{ padding: "0 56px 40px" }}>
          {trip.days.map((d, i) => {
            const dayTitle = lang === "zh" ? d.titleZh : d.title;
            const label = T.dayLabels[i] ?? (lang === "zh" ? `第 ${i + 1} 天` : `Day ${i + 1}`);
            return (
              <div
                key={d.title}
                style={{
                  display: "grid",
                  gridTemplateColumns: "60px 1fr 80px",
                  padding: "20px 0",
                  borderTop: "0.5px solid #E5DDCD",
                  alignItems: "flex-start",
                  gap: 18,
                }}
              >
                <div>
                  <div
                    style={{
                      fontFamily: FONT_MONO,
                      fontSize: 10,
                      color: "#A39F99",
                      letterSpacing: 1,
                      marginBottom: 4,
                    }}
                  >
                    {label.toUpperCase()}
                  </div>
                  <div
                    style={{
                      fontSize: 22,
                      color: "var(--accent-amber)",
                      lineHeight: 1,
                    }}
                  >
                    {d.icon}
                  </div>
                </div>
                <div>
                  <div
                    style={{
                      fontFamily: lang === "zh" ? FONT_CN : FONT_SERIF,
                      fontSize: lang === "zh" ? 17 : 20,
                      fontWeight: lang === "zh" ? 600 : 500,
                      fontStyle: lang === "zh" ? "normal" : "italic",
                      color: "#1A1612",
                      marginBottom: 8,
                      letterSpacing: "-0.2px",
                      lineHeight: 1.3,
                    }}
                  >
                    {dayTitle}
                  </div>
                  <div
                    style={{
                      fontFamily: fontStack,
                      fontSize: 13,
                      color: "#5C4F3E",
                      lineHeight: 1.5,
                    }}
                  >
                    {d.places.join(" · ")}
                  </div>
                </div>
                <div style={{ textAlign: "right" }}>
                  <div
                    style={{
                      fontFamily: FONT_MONO,
                      fontSize: 9.5,
                      color: "#A39F99",
                      letterSpacing: 1,
                      marginBottom: 2,
                    }}
                  >
                    KM
                  </div>
                  <div
                    style={{
                      fontFamily: FONT_MONO,
                      fontSize: 16,
                      color: "#1A1612",
                      fontWeight: 500,
                    }}
                  >
                    {d.walkedKm}
                  </div>
                </div>
              </div>
            );
          })}
        </div>

        {/* CTA */}
        <div
          style={{
            margin: "0 56px 40px",
            padding: "28px 32px",
            background: "linear-gradient(135deg, #2A2218 0%, #1A1612 100%)",
            borderRadius: 12,
            color: "var(--dark-fg)",
            display: "flex",
            alignItems: "center",
            gap: 20,
          }}
        >
          <div style={{ flex: 1 }}>
            <div
              style={{
                fontFamily: lang === "zh" ? FONT_CN : FONT_SERIF,
                fontSize: lang === "zh" ? 19 : 22,
                fontWeight: lang === "zh" ? 600 : 400,
                fontStyle: lang === "zh" ? "normal" : "italic",
                color: "var(--dark-fg)",
                marginBottom: 4,
                letterSpacing: "-0.3px",
              }}
            >
              {T.cta1}
            </div>
            <div
              style={{
                fontFamily: fontStack,
                fontSize: 12.5,
                color: "var(--dark-fg-muted)",
              }}
            >
              {T.cta3} · {T.cta2}
            </div>
          </div>
          <Link
            href={`/${trip.citySlug}${lang === "en" ? "?lang=en" : ""}`}
            style={{
              padding: "10px 18px",
              borderRadius: 6,
              background: "var(--accent-amber)",
              border: "none",
              fontFamily: fontStack,
              fontSize: 13,
              fontWeight: 600,
              color: "var(--dark-surface)",
              cursor: "pointer",
              whiteSpace: "nowrap",
              textDecoration: "none",
            }}
          >
            compass.io →
          </Link>
        </div>

        {/* Footer */}
        <div
          style={{
            padding: "16px 22px",
            borderTop: "0.5px solid #E5DDCD",
            background: "#FBF7F0",
            fontFamily: FONT_MONO,
            fontSize: 10,
            color: "#A39F99",
            letterSpacing: 0.5,
            textAlign: "center",
          }}
        >
          {T.poweredBy}
        </div>
      </article>
    </main>
  );
}
