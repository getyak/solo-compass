"use client";

/**
 * Scenario B — `/mobile-preview`
 * Phone-frame mock of the mobile zero-install web view (390×844).
 *
 * - Full-bleed editorial WebLisbonMap as background.
 * - Glass top header: site URL + "you are near …" + lang toggle.
 * - Blue user pin in the center with double halo.
 * - Tappable bottom sheet (collapsed 360px / expanded 540px) with nearby
 *   experiences sorted by walk time + manual check-in toggles.
 * - After 2 check-ins, soft "iOS app does this automatically" hint.
 *
 * NOT the production mobile route — that's `/`, which uses Mapbox.
 */

import Link from "next/link";
import { useMemo, useState } from "react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import { WEB_CATS, WEB_EXPS, type WebExperience } from "@/lib/lisbon-data";
import { WebLisbonMap } from "@/components/lisbon/WebLisbonMap";

const FONT_DISPLAY = '-apple-system, "SF Pro Display", "Inter", system-ui, sans-serif';
const FONT_MONO = '"JetBrains Mono", "SF Mono", ui-monospace, monospace';
const FONT_CN = '"PingFang SC", "Hiragino Sans GB", system-ui, sans-serif';

type Lang = "zh" | "en";

interface Strings {
  youAreIn: string;
  nearby: string;
  sheetSub: string;
  checkIn: string;
  checkedIn: string;
  hint1: string;
  hint2: string;
  getApp: string;
  maybeLater: string;
  walkMin: string;
  noAccount: string;
  pageTitle: string;
  back: string;
}

function strings(lang: Lang): Strings {
  return lang === "zh"
    ? {
        youAreIn: "你在 BAIRRO ALTO 附近",
        nearby: "走得到的体验",
        sheetSub: "5 个 · 距离排序",
        checkIn: "我到了",
        checkedIn: "到过了",
        hint1: "已经打了 2 个卡。",
        hint2: "iOS 应用会自动记，免费。",
        getApp: "获取应用",
        maybeLater: "以后再说",
        walkMin: "分钟",
        noAccount: "无需账号 · 数据存在浏览器",
        pageTitle: "手机预览",
        back: "← 回到桌面端",
      }
    : {
        youAreIn: "You're near BAIRRO ALTO",
        nearby: "Within walking distance",
        sheetSub: "5 places · sorted by distance",
        checkIn: "I'm here",
        checkedIn: "Checked in",
        hint1: "You've checked in twice.",
        hint2: "The iOS app does this automatically. Free.",
        getApp: "Get the app",
        maybeLater: "Maybe later",
        walkMin: "min",
        noAccount: "No account · data stays in your browser",
        pageTitle: "Mobile preview",
        back: "← Back to desktop",
      };
}

export default function MobilePreviewPage() {
  const params = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const lang: Lang = params.get("lang") === "en" ? "en" : "zh";
  const T = useMemo(() => strings(lang), [lang]);
  const fontStack = lang === "zh" ? FONT_CN : FONT_DISPLAY;

  const [checkedIds, setCheckedIds] = useState<Set<string>>(
    () => new Set(["tasca-do-chico", "a-vida-portuguesa"]),
  );
  const [showHint, setShowHint] = useState(true);
  const [sheetExpanded, setSheetExpanded] = useState(false);

  const sortedExps = useMemo(() => [...WEB_EXPS].sort((a, b) => a.walkMin - b.walkMin), []);

  const toggleCheckin = (id: string) => {
    setCheckedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const setLang = (next: Lang) => {
    const sp = new URLSearchParams(params.toString());
    if (next === "en") sp.set("lang", "en");
    else sp.delete("lang");
    const qs = sp.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname);
  };

  return (
    <div
      style={{
        minHeight: "100vh",
        background: "radial-gradient(ellipse at top, #2C241B 0%, #15110D 60%, #0F0D0B 100%)",
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        padding: "48px 24px",
        fontFamily: fontStack,
        gap: 24,
      }}
    >
      <header
        style={{
          width: "100%",
          maxWidth: 760,
          display: "flex",
          alignItems: "center",
          gap: 12,
          color: "var(--dark-fg-muted)",
        }}
      >
        <Link
          href={`/lisbon${lang === "en" ? "?lang=en" : ""}`}
          style={{
            fontFamily: FONT_MONO,
            fontSize: 11,
            color: "var(--dark-fg-muted)",
            textDecoration: "none",
            padding: "5px 10px",
            border: "0.5px solid var(--dark-border-strong)",
            borderRadius: 5,
            letterSpacing: 0.5,
          }}
        >
          {T.back}
        </Link>
        <span style={{ flex: 1 }} />
        <span
          style={{
            fontFamily: FONT_MONO,
            fontSize: 10,
            letterSpacing: 1.5,
            textTransform: "uppercase",
            color: "var(--dark-fg-faint)",
          }}
        >
          {T.pageTitle} · 390 × 844
        </span>
      </header>

      <PhoneFrame
        T={T}
        lang={lang}
        fontStack={fontStack}
        sortedExps={sortedExps}
        checkedIds={checkedIds}
        toggleCheckin={toggleCheckin}
        showHint={showHint}
        dismissHint={() => setShowHint(false)}
        sheetExpanded={sheetExpanded}
        toggleSheet={() => setSheetExpanded((v) => !v)}
        setLang={setLang}
      />
    </div>
  );
}

interface PhoneFrameProps {
  T: Strings;
  lang: Lang;
  fontStack: string;
  sortedExps: readonly WebExperience[];
  checkedIds: Set<string>;
  toggleCheckin: (id: string) => void;
  showHint: boolean;
  dismissHint: () => void;
  sheetExpanded: boolean;
  toggleSheet: () => void;
  setLang: (l: Lang) => void;
}

function PhoneFrame(p: PhoneFrameProps) {
  const sheetHeight = p.sheetExpanded ? 540 : 360;

  return (
    <div
      style={{
        width: 390,
        height: 844,
        borderRadius: 38,
        overflow: "hidden",
        background: "var(--dark-bg)",
        color: "var(--dark-fg-secondary)",
        fontFamily: p.fontStack,
        position: "relative",
        border: "6px solid #1A1714",
        boxShadow: "0 30px 80px rgba(0,0,0,0.5)",
      }}
    >
      {/* Status bar */}
      <div
        style={{
          position: "absolute",
          top: 0,
          left: 0,
          right: 0,
          height: 50,
          zIndex: 10,
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          padding: "0 28px",
        }}
      >
        <span
          style={{
            fontFamily: FONT_DISPLAY,
            fontSize: 15,
            fontWeight: 600,
            color: "var(--dark-fg)",
          }}
        >
          9:41
        </span>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 5,
            color: "var(--dark-fg)",
          }}
        >
          <svg width="16" height="10" viewBox="0 0 16 10" fill="currentColor">
            <path d="M1 8 h2 v2 h-2 z M5 6 h2 v4 h-2 z M9 4 h2 v6 h-2 z M13 2 h2 v8 h-2 z" />
          </svg>
          <svg width="22" height="10" viewBox="0 0 22 10" fill="none">
            <rect x="1" y="1" width="18" height="8" rx="2" stroke="currentColor" />
            <rect x="3" y="3" width="14" height="4" fill="currentColor" />
            <rect x="20" y="3" width="1" height="4" fill="currentColor" />
          </svg>
        </div>
      </div>

      {/* Map */}
      <div style={{ position: "absolute", inset: 0 }}>
        <WebLisbonMap pins={WEB_EXPS} dark />
      </div>

      {/* User pin */}
      <div
        style={{
          position: "absolute",
          left: "47.8%",
          top: "50%",
          transform: "translate(-50%,-50%)",
          zIndex: 4,
          pointerEvents: "none",
        }}
      >
        <div
          style={{
            width: 14,
            height: 14,
            borderRadius: 7,
            background: "#3B82F6",
            boxShadow: "0 0 0 4px rgba(59,130,246,0.3), 0 0 0 12px rgba(59,130,246,0.15)",
          }}
        />
      </div>

      {/* Top header glass */}
      <div
        style={{
          position: "absolute",
          top: 60,
          left: 16,
          right: 16,
          zIndex: 6,
          background: "rgba(21,17,13,0.85)",
          backdropFilter: "blur(20px)",
          border: "0.5px solid var(--dark-border)",
          borderRadius: 14,
          padding: "11px 14px",
          display: "flex",
          alignItems: "center",
          gap: 10,
        }}
      >
        <div
          style={{
            width: 28,
            height: 28,
            borderRadius: 14,
            background: "linear-gradient(135deg, #FFE7C4, #C98628)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none">
            <circle cx="7" cy="7" r="5.5" stroke="#FFF" strokeWidth="1" />
            <path d="M7 3 L8 7 L7 11 L6 7 Z" fill="#FFF" />
          </svg>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div
            style={{
              fontFamily: FONT_MONO,
              fontSize: 9.5,
              color: "var(--dark-fg-subtle)",
              letterSpacing: 1,
              textTransform: "uppercase",
            }}
          >
            compass.io/lisbon
          </div>
          <div
            style={{
              fontFamily: p.fontStack,
              fontSize: 13,
              color: "var(--dark-fg)",
              fontWeight: 500,
              letterSpacing: p.lang === "zh" ? "0.2px" : "0",
            }}
          >
            {p.T.youAreIn}
          </div>
        </div>
        <button
          type="button"
          onClick={() => p.setLang(p.lang === "zh" ? "en" : "zh")}
          style={{
            padding: "5px 9px",
            borderRadius: 5,
            background: "transparent",
            border: "0.5px solid var(--dark-border-strong)",
            color: "var(--dark-fg-muted)",
            fontFamily: p.fontStack,
            fontSize: 10.5,
            cursor: "pointer",
          }}
        >
          {p.lang === "zh" ? "中文" : "EN"}
        </button>
      </div>

      {/* Bottom sheet */}
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          bottom: 0,
          zIndex: 8,
          height: sheetHeight,
          background: "rgba(15,13,11,0.96)",
          backdropFilter: "blur(24px) saturate(180%)",
          borderTopLeftRadius: 22,
          borderTopRightRadius: 22,
          borderTop: "0.5px solid var(--dark-border)",
          boxShadow: "0 -10px 30px rgba(0,0,0,0.4)",
          display: "flex",
          flexDirection: "column",
          transition: "height 320ms cubic-bezier(.2,.7,.2,1)",
        }}
      >
        <button
          type="button"
          onClick={p.toggleSheet}
          aria-label="Toggle sheet"
          style={{
            padding: "10px 0 6px",
            display: "flex",
            justifyContent: "center",
            cursor: "pointer",
            background: "transparent",
            border: "none",
          }}
        >
          <div
            style={{
              width: 36,
              height: 4,
              borderRadius: 2,
              background: "var(--dark-border-strong)",
            }}
          />
        </button>

        <div
          style={{
            padding: "4px 22px 10px",
            display: "flex",
            alignItems: "baseline",
            gap: 8,
          }}
        >
          <div
            style={{
              fontFamily: p.fontStack,
              fontSize: 17,
              fontWeight: 600,
              color: "var(--dark-fg)",
              letterSpacing: p.lang === "zh" ? "0.2px" : "-0.3px",
            }}
          >
            {p.T.nearby}
          </div>
          <span style={{ flex: 1 }} />
          <span
            style={{
              fontFamily: FONT_MONO,
              fontSize: 10,
              color: "var(--dark-fg-faint)",
              letterSpacing: 0.5,
            }}
          >
            {p.T.sheetSub}
          </span>
        </div>

        {p.showHint && p.checkedIds.size >= 2 && (
          <div
            style={{
              margin: "0 16px 12px",
              padding: "12px 14px",
              background: "linear-gradient(135deg, rgba(201,134,40,0.10), rgba(201,134,40,0.04))",
              border: "0.5px solid rgba(201,134,40,0.3)",
              borderRadius: 10,
              display: "flex",
              alignItems: "flex-start",
              gap: 10,
            }}
          >
            <div
              style={{
                width: 18,
                height: 18,
                borderRadius: 9,
                background: "linear-gradient(135deg, #FFE7C4, #C98628)",
                flexShrink: 0,
                marginTop: 1,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
              }}
            >
              <span style={{ fontSize: 9, color: "#FFF" }}>✦</span>
            </div>
            <div style={{ flex: 1 }}>
              <div
                style={{
                  fontFamily: p.fontStack,
                  fontSize: 12.5,
                  color: "var(--dark-fg)",
                  lineHeight: 1.45,
                  marginBottom: 8,
                }}
              >
                <b style={{ color: "#FFD89E" }}>{p.T.hint1}</b> {p.T.hint2}
              </div>
              <div style={{ display: "flex", gap: 6 }}>
                <button
                  type="button"
                  style={{
                    padding: "5px 11px",
                    borderRadius: 5,
                    background: "var(--accent-amber)",
                    border: "none",
                    color: "var(--dark-surface)",
                    fontFamily: p.fontStack,
                    fontSize: 11,
                    fontWeight: 600,
                    cursor: "pointer",
                  }}
                >
                  {p.T.getApp}
                </button>
                <button
                  type="button"
                  onClick={p.dismissHint}
                  style={{
                    padding: "5px 11px",
                    borderRadius: 5,
                    background: "transparent",
                    border: "0.5px solid var(--dark-border-strong)",
                    color: "var(--dark-fg-subtle)",
                    fontFamily: p.fontStack,
                    fontSize: 11,
                    cursor: "pointer",
                  }}
                >
                  {p.T.maybeLater}
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="lc-scroll" style={{ flex: 1, overflow: "auto", padding: "0 16px 16px" }}>
          {p.sortedExps.slice(0, p.sheetExpanded ? 7 : 4).map((e) => {
            const cat = WEB_CATS[e.cat];
            const checked = p.checkedIds.has(e.id);
            const title = p.lang === "zh" ? e.titleZh : e.title;
            const place = p.lang === "zh" ? e.placeZh : e.place;
            return (
              <div
                key={e.id}
                style={{
                  padding: "12px 4px",
                  borderBottom: "0.5px solid var(--dark-border-soft)",
                  display: "flex",
                  gap: 12,
                  alignItems: "flex-start",
                }}
              >
                <div
                  style={{
                    width: 6,
                    height: 6,
                    borderRadius: 3,
                    background: cat.color,
                    marginTop: 7,
                    flexShrink: 0,
                  }}
                />
                <Link
                  href={`/experience/${e.id}${p.lang === "en" ? "?lang=en" : ""}`}
                  style={{
                    flex: 1,
                    minWidth: 0,
                    textDecoration: "none",
                    color: "inherit",
                  }}
                >
                  <div
                    style={{
                      fontFamily: p.fontStack,
                      fontSize: 13.5,
                      fontWeight: 600,
                      color: "var(--dark-fg)",
                      lineHeight: 1.35,
                      marginBottom: 3,
                      letterSpacing: p.lang === "zh" ? "0.1px" : "-0.2px",
                    }}
                  >
                    {title}
                  </div>
                  <div
                    style={{
                      fontFamily: p.fontStack,
                      fontSize: 11.5,
                      color: "var(--dark-fg-subtle)",
                      display: "flex",
                      alignItems: "center",
                      gap: 6,
                    }}
                  >
                    <span>{place}</span>
                    <span style={{ color: "var(--dark-border-strong)" }}>·</span>
                    <span
                      style={{
                        fontFamily: FONT_MONO,
                        color: "var(--dark-fg-muted)",
                      }}
                    >
                      {e.walkMin} {p.T.walkMin}
                    </span>
                  </div>
                </Link>
                <button
                  type="button"
                  onClick={() => p.toggleCheckin(e.id)}
                  style={{
                    padding: "5px 10px",
                    borderRadius: 5,
                    background: checked ? "rgba(201,134,40,0.15)" : "transparent",
                    border: `0.5px solid ${
                      checked ? "var(--accent-amber)" : "var(--dark-border-strong)"
                    }`,
                    color: checked ? "var(--accent-amber)" : "var(--dark-fg-muted)",
                    fontFamily: p.fontStack,
                    fontSize: 11,
                    fontWeight: 500,
                    cursor: "pointer",
                    whiteSpace: "nowrap",
                    flexShrink: 0,
                  }}
                >
                  {checked ? `✓ ${p.T.checkedIn}` : p.T.checkIn}
                </button>
              </div>
            );
          })}
          <div
            style={{
              fontFamily: FONT_MONO,
              fontSize: 9.5,
              color: "var(--dark-fg-faint)",
              textAlign: "center",
              padding: "14px 0 0",
              letterSpacing: 0.5,
            }}
          >
            {p.T.noAccount}
          </div>
        </div>
      </div>

      {/* Home indicator */}
      <div
        style={{
          position: "absolute",
          bottom: 8,
          left: "50%",
          transform: "translateX(-50%)",
          width: 134,
          height: 5,
          borderRadius: 3,
          background: "var(--dark-fg)",
          zIndex: 20,
        }}
      />
    </div>
  );
}
