"use client";

/**
 * Scenario D — `/experience/[id]`
 * Magazine-style deep-link page. Optimized for landing from Google.
 *
 * Layout:
 *   - Browser bar mock + breadcrumb
 *   - Title block with serif italic + accent subtitle + lede paragraph
 *   - Two-column body: narrative ("The moment", "When to go") + Quick Facts aside
 *   - "For you" AI block
 *   - Nearby cards (links to other /experience/[id])
 *   - Footer credit
 */

import Link from "next/link";
import { notFound, useParams, useSearchParams } from "next/navigation";
import { useMemo } from "react";
import {
  WEB_CATS,
  WEB_CITY,
  findExperienceById,
  nearbyExperiences,
  type WebExperience,
} from "@/lib/lisbon-data";

const FONT_DISPLAY = '-apple-system, "SF Pro Display", "Inter", system-ui, sans-serif';
const FONT_MONO = '"JetBrains Mono", "SF Mono", ui-monospace, monospace';
const FONT_SERIF = '"Fraunces", Georgia, "Cormorant Garamond", serif';
const FONT_CN = '"PingFang SC", "Hiragino Sans GB", system-ui, sans-serif';

type Lang = "zh" | "en";

export default function ExperiencePage() {
  const params = useParams<{ id: string }>();
  const search = useSearchParams();
  const lang: Lang = search.get("lang") === "en" ? "en" : "zh";
  const exp = useMemo(() => findExperienceById(params.id), [params.id]);
  const nearby = useMemo(() => (exp ? nearbyExperiences(exp, 2) : []), [exp]);
  if (!exp) notFound();
  return <ExperienceView exp={exp} nearby={nearby} lang={lang} />;
}

function ExperienceView({
  exp,
  nearby,
  lang,
}: {
  exp: WebExperience;
  nearby: readonly WebExperience[];
  lang: Lang;
}) {
  const cat = WEB_CATS[exp.cat];
  const fontStack = lang === "zh" ? FONT_CN : FONT_DISPLAY;

  const title = lang === "zh" ? exp.titleZh : exp.title;
  const place = lang === "zh" ? exp.placeZh : exp.place;
  const intro = lang === "zh" ? exp.whyZh : exp.why;
  const moment = lang === "zh" ? exp.momentZh : exp.moment;
  const aiReason = lang === "zh" ? exp.aiReasonZh : exp.aiReason;

  const T =
    lang === "zh"
      ? {
          breadcrumb: `${WEB_CITY.zh} · ${cat.zh}`,
          quickFacts: "速览",
          forYou: "为你推荐",
          when: "什么时候去",
          whenLabel: ["位置", "最佳时段", "停留", "人多吗", "一人去合适吗", "花费"],
          why: "那一刻",
          nearby: "附近还有",
          addToTrip: "加进我的行程",
          viewMap: "在地图上看",
          metaSeo:
            "这一页是 Solo Compass 写的——一份只为独自旅行的人做的、由 AI 整理但人去过的指南。",
          backToLisbon: "← 回到 里斯本",
          mins: "分钟",
        }
      : {
          breadcrumb: `${WEB_CITY.en} · ${cat.en}`,
          quickFacts: "Quick facts",
          forYou: "For you",
          when: "When to go",
          whenLabel: ["Where", "Best time", "Stay", "Crowded?", "Solo-friendly?", "Cost"],
          why: "The moment",
          nearby: "Nearby",
          addToTrip: "Add to my trip",
          viewMap: "View on map",
          metaSeo:
            "This page is by Solo Compass — a guide for people traveling alone, organized by AI but written by people who've been there.",
          backToLisbon: "← Back to Lisbon",
          mins: "min",
        };

  const facts: ReadonlyArray<readonly [string, string]> = [
    [T.whenLabel[0]!, `${exp.neighborhood} · ${exp.walkMin} ${T.mins}`],
    [
      T.whenLabel[1]!,
      `${exp.bestHours[0]}:00 – ${exp.bestHours[exp.bestHours.length - 1]! + 1}:00`,
    ],
    [T.whenLabel[2]!, `${exp.durationMin} ${T.mins}`],
    [T.whenLabel[3]!, exp.crowd],
    [T.whenLabel[4]!, lang === "zh" ? "是 · 推荐独自前往" : "Yes · solo recommended"],
    [T.whenLabel[5]!, exp.pricePill],
  ];

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
          background: "#FBF7F0",
          borderRadius: 12,
          overflow: "hidden",
          border: "0.5px solid #E5DDCD",
          boxShadow: "0 1px 3px rgba(0,0,0,0.05)",
        }}
      >
        {/* Browser bar mock */}
        <div
          style={{
            padding: "11px 22px",
            borderBottom: "0.5px solid #E5DDCD",
            display: "flex",
            alignItems: "center",
            gap: 10,
            background: "#F8F4ED",
          }}
        >
          <div style={{ display: "flex", gap: 5 }}>
            {[0, 1, 2].map((i) => (
              <div
                key={i}
                style={{
                  width: 9,
                  height: 9,
                  borderRadius: 4.5,
                  background: "#E5DDCD",
                }}
              />
            ))}
          </div>
          <div
            style={{
              flex: 1,
              padding: "4px 12px",
              borderRadius: 5,
              background: "#FFF",
              border: "0.5px solid #E5DDCD",
              fontFamily: FONT_MONO,
              fontSize: 10.5,
              color: "#5C4F3E",
              letterSpacing: 0.3,
            }}
          >
            compass.io / {WEB_CITY.slug} / {exp.id}
          </div>
          <Link
            href={`/lisbon${lang === "en" ? "?lang=en" : ""}`}
            style={{
              fontFamily: FONT_MONO,
              fontSize: 10.5,
              color: "#5C4F3E",
              textDecoration: "none",
              padding: "4px 10px",
              borderRadius: 5,
              border: "0.5px solid #E5DDCD",
              background: "#FFF",
            }}
          >
            {T.backToLisbon}
          </Link>
        </div>

        {/* Breadcrumb */}
        <div
          style={{
            padding: "20px 56px 0",
            fontFamily: FONT_MONO,
            fontSize: 10,
            color: "#A39F99",
            letterSpacing: 1.5,
            textTransform: "uppercase",
          }}
        >
          {T.breadcrumb}
        </div>

        {/* Title block — soft category color wash on the panel */}
        <div
          style={{
            padding: "14px 56px 30px",
            background: `linear-gradient(180deg, ${cat.color}10, transparent 60%)`,
          }}
        >
          <h1
            style={{
              fontFamily: lang === "zh" ? FONT_CN : FONT_SERIF,
              fontSize: lang === "zh" ? 42 : 52,
              fontWeight: lang === "zh" ? 600 : 400,
              fontStyle: lang === "zh" ? "normal" : "italic",
              letterSpacing: "-1px",
              margin: "0 0 12px",
              lineHeight: 1.05,
              color: "#1A1612",
            }}
          >
            {title}
          </h1>
          <div
            style={{
              fontFamily: lang === "zh" ? FONT_CN : FONT_SERIF,
              fontSize: lang === "zh" ? 18 : 22,
              fontStyle: lang === "zh" ? "normal" : "italic",
              fontWeight: lang === "zh" ? 500 : 400,
              color: cat.color,
              marginBottom: 22,
              letterSpacing: "-0.3px",
            }}
          >
            {place} · {exp.neighborhood}
          </div>
          <div
            style={{
              fontFamily: fontStack,
              fontSize: 17,
              lineHeight: 1.55,
              color: "#1A1612",
              maxWidth: 600,
              letterSpacing: "-0.1px",
            }}
          >
            {intro}
          </div>
        </div>

        {/* Two-column body */}
        <div
          style={{
            padding: "0 56px 32px",
            display: "grid",
            gridTemplateColumns: "1fr 240px",
            gap: 36,
          }}
        >
          <div>
            <h2
              style={{
                fontFamily: lang === "zh" ? FONT_CN : FONT_SERIF,
                fontSize: lang === "zh" ? 22 : 26,
                fontWeight: lang === "zh" ? 600 : 500,
                fontStyle: lang === "zh" ? "normal" : "italic",
                margin: "0 0 12px",
                letterSpacing: "-0.4px",
              }}
            >
              {T.why}
            </h2>
            <p
              style={{
                fontFamily: fontStack,
                fontSize: 15,
                lineHeight: 1.7,
                color: "#3D352A",
                margin: "0 0 28px",
                paddingLeft: 12,
                borderLeft: `2px solid ${cat.color}`,
                fontStyle: lang === "zh" ? "normal" : "italic",
              }}
            >
              “{moment}”
            </p>

            <h2
              style={{
                fontFamily: lang === "zh" ? FONT_CN : FONT_SERIF,
                fontSize: lang === "zh" ? 22 : 26,
                fontWeight: lang === "zh" ? 600 : 500,
                fontStyle: lang === "zh" ? "normal" : "italic",
                margin: "0 0 12px",
                letterSpacing: "-0.4px",
              }}
            >
              {T.when}
            </h2>
            <p
              style={{
                fontFamily: fontStack,
                fontSize: 14.5,
                lineHeight: 1.65,
                color: "#3D352A",
                margin: "0 0 24px",
              }}
            >
              {lang === "zh" ? exp.whyZh : exp.why}
            </p>

            {/* AI for-you */}
            <div
              style={{
                background: "#FFF7EA",
                border: "0.5px solid #EBD9B8",
                borderRadius: 8,
                padding: 16,
                display: "flex",
                gap: 12,
                alignItems: "flex-start",
              }}
            >
              <div
                style={{
                  width: 22,
                  height: 22,
                  flexShrink: 0,
                  borderRadius: 11,
                  background: "linear-gradient(135deg, #FFE7C4, #C98628)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  color: "#FFF",
                  fontSize: 11,
                }}
              >
                ✦
              </div>
              <div style={{ flex: 1 }}>
                <div
                  style={{
                    fontFamily: FONT_MONO,
                    fontSize: 10,
                    color: "#A66A00",
                    letterSpacing: 1.2,
                    textTransform: "uppercase",
                    marginBottom: 6,
                  }}
                >
                  {T.forYou}
                </div>
                <div
                  style={{
                    fontFamily: fontStack,
                    fontSize: 13.5,
                    color: "#3D352A",
                    lineHeight: 1.55,
                  }}
                >
                  {aiReason}
                </div>
              </div>
            </div>
          </div>

          <aside
            style={{
              padding: 18,
              background: "#FFF",
              border: "0.5px solid #E5DDCD",
              borderRadius: 8,
              alignSelf: "start",
            }}
          >
            <div
              style={{
                fontFamily: FONT_MONO,
                fontSize: 9.5,
                color: "#A39F99",
                letterSpacing: 1.5,
                textTransform: "uppercase",
                marginBottom: 14,
                paddingBottom: 10,
                borderBottom: "0.5px solid #E5DDCD",
              }}
            >
              {T.quickFacts}
            </div>
            {facts.map(([k, v], i) => (
              <div key={k} style={{ marginBottom: i === facts.length - 1 ? 0 : 12 }}>
                <div
                  style={{
                    fontFamily: FONT_MONO,
                    fontSize: 9,
                    color: "#A39F99",
                    letterSpacing: 1,
                    textTransform: "uppercase",
                    marginBottom: 3,
                  }}
                >
                  {k}
                </div>
                <div
                  style={{
                    fontFamily: fontStack,
                    fontSize: 12.5,
                    color: "#1A1612",
                    lineHeight: 1.4,
                  }}
                >
                  {v}
                </div>
              </div>
            ))}
            <div
              style={{
                marginTop: 16,
                paddingTop: 14,
                borderTop: "0.5px solid #E5DDCD",
                display: "flex",
                flexDirection: "column",
                gap: 6,
              }}
            >
              <button
                type="button"
                style={{
                  padding: "8px 12px",
                  borderRadius: 5,
                  background: "var(--accent)",
                  border: "none",
                  color: "#FFF7EA",
                  fontFamily: fontStack,
                  fontSize: 12,
                  fontWeight: 600,
                  cursor: "pointer",
                }}
              >
                + {T.addToTrip}
              </button>
              <Link
                href={`/lisbon${lang === "en" ? "?lang=en" : ""}`}
                style={{
                  padding: "8px 12px",
                  borderRadius: 5,
                  background: "transparent",
                  border: "0.5px solid #D6CEC0",
                  color: "var(--accent)",
                  fontFamily: fontStack,
                  fontSize: 12,
                  cursor: "pointer",
                  textAlign: "center",
                  textDecoration: "none",
                }}
              >
                ↗ {T.viewMap}
              </Link>
              <div
                style={{
                  marginTop: 8,
                  fontFamily: FONT_MONO,
                  fontSize: 9,
                  color: "#A39F99",
                  letterSpacing: 0.5,
                  lineHeight: 1.5,
                }}
              >
                {lang === "zh" ? "核实于" : "Verified"} {exp.lastVerified}
                <br />
                {exp.sources} {lang === "zh" ? "来源" : "sources"}
              </div>
            </div>
          </aside>
        </div>

        {/* Nearby */}
        {nearby.length > 0 && (
          <div style={{ padding: "0 56px 36px" }}>
            <div
              style={{
                fontFamily: FONT_MONO,
                fontSize: 10,
                color: "#A39F99",
                letterSpacing: 2,
                textTransform: "uppercase",
                paddingTop: 24,
                marginBottom: 14,
                borderTop: "0.5px solid #E5DDCD",
              }}
            >
              {T.nearby}
            </div>
            <div
              style={{
                display: "grid",
                gridTemplateColumns: "1fr 1fr",
                gap: 12,
              }}
            >
              {nearby.map((it) => {
                const ncat = WEB_CATS[it.cat];
                const ntitle = lang === "zh" ? it.titleZh : it.title;
                const nplace = lang === "zh" ? it.placeZh : it.place;
                return (
                  <Link
                    key={it.id}
                    href={`/experience/${it.id}${lang === "en" ? "?lang=en" : ""}`}
                    style={{
                      padding: 16,
                      background: "#FFF",
                      border: "0.5px solid #E5DDCD",
                      borderRadius: 8,
                      cursor: "pointer",
                      textDecoration: "none",
                      color: "inherit",
                      display: "block",
                    }}
                  >
                    <div
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 6,
                        marginBottom: 6,
                      }}
                    >
                      <div
                        style={{
                          width: 6,
                          height: 6,
                          borderRadius: 3,
                          background: ncat.color,
                        }}
                      />
                      <span
                        style={{
                          fontFamily: FONT_MONO,
                          fontSize: 9.5,
                          color: ncat.color,
                          letterSpacing: 1,
                          textTransform: "uppercase",
                          fontWeight: 600,
                        }}
                      >
                        {lang === "zh" ? ncat.zh : ncat.en}
                      </span>
                    </div>
                    <div
                      style={{
                        fontFamily: lang === "zh" ? FONT_CN : FONT_SERIF,
                        fontSize: lang === "zh" ? 16 : 19,
                        fontWeight: lang === "zh" ? 600 : 500,
                        fontStyle: lang === "zh" ? "normal" : "italic",
                        color: "#1A1612",
                        marginBottom: 4,
                        letterSpacing: "-0.2px",
                      }}
                    >
                      {ntitle}
                    </div>
                    <div
                      style={{
                        fontFamily: fontStack,
                        fontSize: 12,
                        color: "#5C4F3E",
                        lineHeight: 1.45,
                      }}
                    >
                      {nplace} · {it.walkMin} {T.mins}
                    </div>
                  </Link>
                );
              })}
            </div>
          </div>
        )}

        {/* Footer */}
        <div
          style={{
            padding: "20px 56px",
            borderTop: "0.5px solid #E5DDCD",
            background: "#F8F4ED",
            display: "flex",
            alignItems: "center",
            gap: 14,
          }}
        >
          <div
            style={{
              width: 22,
              height: 22,
              borderRadius: 11,
              background: "linear-gradient(135deg, #FFE7C4, #C98628)",
              flexShrink: 0,
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <svg width="11" height="11" viewBox="0 0 14 14" fill="none">
              <circle cx="7" cy="7" r="5.5" stroke="#FFF" strokeWidth="1" />
              <path d="M7 3 L8 7 L7 11 L6 7 Z" fill="#FFF" />
            </svg>
          </div>
          <div
            style={{
              flex: 1,
              fontFamily: fontStack,
              fontSize: 11.5,
              color: "#5C4F3E",
              lineHeight: 1.5,
            }}
          >
            {T.metaSeo}
          </div>
        </div>
      </article>
    </main>
  );
}
