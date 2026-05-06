"use client";

/**
 * Scenario A — `/lisbon`
 * Desktop research view. Linear/Arc/Raycast software-tool aesthetic.
 *
 * Layout:  [TopBar] / [ListColumn (480) | RightSurface map + DetailDock] / [StatusBar]
 *
 * Language toggle stored in URL: `?lang=zh|en` (default zh).
 */

import Link from "next/link";
import { useMemo, useState } from "react";
import { useSearchParams, useRouter, usePathname } from "next/navigation";
import {
  WEB_CATS,
  WEB_CITY,
  WEB_EXPS,
  type WebCategoryId,
  type WebExperience,
} from "@/lib/lisbon-data";
import { WebLisbonMap } from "@/components/lisbon/WebLisbonMap";

const FONT_DISPLAY = '-apple-system, "SF Pro Display", "Inter", system-ui, sans-serif';
const FONT_MONO = '"JetBrains Mono", "SF Mono", ui-monospace, monospace';
const FONT_CN = '"PingFang SC", "Hiragino Sans GB", system-ui, sans-serif';

type Lang = "zh" | "en";
type Sort = "curated" | "recent" | "distance";

interface Strings {
  nearby: string;
  search: string;
  sortBy: string;
  recent: string;
  curated: string;
  distance: string;
  sources: string;
  forYou: string;
  allCats: string;
  verified: string;
  lastEdit: string;
  edition: string;
  walk: string;
  best: string;
  stay: string;
  price: string;
  crowd: string;
  addToPlan: string;
  pinned: string;
  tram: string;
}

function strings(lang: Lang): Strings {
  return lang === "zh"
    ? {
        nearby: `${WEB_CITY.zh} · ${WEB_CITY.experienceCount} 个体验`,
        search: "搜地点、心情、时间…",
        sortBy: "排序",
        recent: "最近编辑",
        curated: "编辑精选",
        distance: "距离",
        sources: "来源",
        forYou: "为你",
        allCats: "全部",
        verified: "核实于",
        lastEdit: "今天 14:22",
        edition: "2026 春",
        walk: "步行",
        best: "时段",
        stay: "时长",
        price: "价",
        crowd: "人",
        addToPlan: "加入计划",
        pinned: "体验",
        tram: "28 路",
      }
    : {
        nearby: `${WEB_CITY.en} · ${WEB_CITY.experienceCount} experiences`,
        search: "Search places, moods, times…",
        sortBy: "Sort",
        recent: "Recent",
        curated: "Curated",
        distance: "Distance",
        sources: "Sources",
        forYou: "For you",
        allCats: "All",
        verified: "Verified",
        lastEdit: "Today 14:22",
        edition: "Spring 2026",
        walk: "Walk",
        best: "Best",
        stay: "Stay",
        price: "Price",
        crowd: "Crowd",
        addToPlan: "Add to plan",
        pinned: "pinned",
        tram: "Tram 28",
      };
}

export default function LisbonPage() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();
  const lang: Lang = searchParams.get("lang") === "en" ? "en" : "zh";
  const T = useMemo(() => strings(lang), [lang]);
  const fontStack = lang === "zh" ? FONT_CN : FONT_DISPLAY;

  const [hoverId, setHoverId] = useState<string | null>(null);
  const [focusedId, setFocusedId] = useState<string | null>("miradouro-graca");
  const [activeCat, setActiveCat] = useState<WebCategoryId | null>(null);
  const [activeSort, setActiveSort] = useState<Sort>("curated");

  const filtered = useMemo(
    () => (activeCat ? WEB_EXPS.filter((e) => e.cat === activeCat) : WEB_EXPS),
    [activeCat],
  );
  const focused = useMemo(() => WEB_EXPS.find((e) => e.id === focusedId) ?? null, [focusedId]);

  const setLang = (next: Lang) => {
    const params = new URLSearchParams(searchParams.toString());
    if (next === "en") params.set("lang", "en");
    else params.delete("lang");
    const qs = params.toString();
    router.replace(qs ? `${pathname}?${qs}` : pathname);
  };

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "var(--dark-bg)",
        color: "var(--dark-fg)",
        fontFamily: fontStack,
        display: "flex",
        flexDirection: "column",
        overflow: "hidden",
      }}
    >
      <TopBar T={T} lang={lang} setLang={setLang} fontStack={fontStack} />
      <div style={{ flex: 1, display: "flex", minHeight: 0 }}>
        <ListColumn
          T={T}
          lang={lang}
          exps={filtered}
          activeCat={activeCat}
          setActiveCat={setActiveCat}
          activeSort={activeSort}
          setActiveSort={setActiveSort}
          hoverId={hoverId}
          setHoverId={setHoverId}
          focusedId={focusedId}
          setFocusedId={setFocusedId}
        />
        <RightSurface
          T={T}
          lang={lang}
          hoverId={hoverId}
          setHoverId={setHoverId}
          focusedId={focusedId}
          setFocusedId={setFocusedId}
          focused={focused}
        />
      </div>
      <StatusBar T={T} lang={lang} />
    </div>
  );
}

// ───── Top bar ─────
function TopBar({
  T,
  lang,
  setLang,
  fontStack,
}: {
  T: Strings;
  lang: Lang;
  setLang: (n: Lang) => void;
  fontStack: string;
}) {
  return (
    <div
      style={{
        height: 48,
        flexShrink: 0,
        display: "flex",
        alignItems: "center",
        background: "var(--dark-surface)",
        borderBottom: "1px solid var(--dark-border)",
        padding: "0 12px",
      }}
    >
      <Logo />
      <div
        style={{
          width: 1,
          height: 22,
          background: "var(--dark-border)",
          margin: "0 12px",
        }}
      />
      <div style={{ display: "flex", gap: 2 }}>
        {WEB_CITY.cityDeck.map((c, i) => {
          const active = i === 0;
          return (
            <div
              key={c}
              style={{
                padding: "5px 11px",
                borderRadius: 6,
                background: active ? "var(--dark-border)" : "transparent",
                fontFamily: fontStack,
                fontSize: 12.5,
                fontWeight: active ? 600 : 500,
                color: active ? "var(--dark-fg)" : "var(--dark-fg-subtle)",
                cursor: "pointer",
                border: active
                  ? "0.5px solid var(--dark-border-strong)"
                  : "0.5px solid transparent",
                display: "flex",
                alignItems: "center",
                gap: 6,
              }}
            >
              {active && (
                <div
                  style={{
                    width: 5,
                    height: 5,
                    borderRadius: 3,
                    background: "var(--accent-amber)",
                  }}
                />
              )}
              {c}
            </div>
          );
        })}
        <button
          type="button"
          style={{
            padding: "5px 9px",
            borderRadius: 6,
            background: "transparent",
            border: "0.5px dashed var(--dark-border-strong)",
            color: "var(--dark-fg-faint)",
            fontFamily: FONT_MONO,
            fontSize: 11,
            cursor: "pointer",
            marginLeft: 4,
          }}
        >
          + City
        </button>
      </div>
      <div style={{ flex: 1 }} />
      <div
        style={{
          height: 28,
          width: 320,
          background: "var(--dark-bg)",
          border: "0.5px solid var(--dark-border)",
          borderRadius: 6,
          display: "flex",
          alignItems: "center",
          padding: "0 10px",
          gap: 8,
        }}
      >
        <svg width="11" height="11" viewBox="0 0 11 11" fill="none">
          <circle cx="4.5" cy="4.5" r="3" stroke="#5C4F3E" strokeWidth="1.2" />
          <path d="M7 7 L10 10" stroke="#5C4F3E" strokeWidth="1.2" strokeLinecap="round" />
        </svg>
        <span
          style={{
            flex: 1,
            color: "var(--dark-fg-faint)",
            fontFamily: fontStack,
            fontSize: 12,
          }}
        >
          {T.search}
        </span>
        <span
          style={{
            fontFamily: FONT_MONO,
            fontSize: 10,
            color: "var(--dark-fg-faint)",
            padding: "2px 5px",
            border: "0.5px solid var(--dark-border)",
            borderRadius: 3,
          }}
        >
          ⌘ K
        </span>
      </div>
      <div style={{ width: 12 }} />
      <div
        style={{
          display: "flex",
          background: "var(--dark-bg)",
          border: "0.5px solid var(--dark-border)",
          borderRadius: 6,
          padding: 2,
        }}
      >
        {(["zh", "en"] as const).map((l) => {
          const active = l === lang;
          return (
            <button
              key={l}
              type="button"
              onClick={() => setLang(l)}
              style={{
                padding: "3px 8px",
                borderRadius: 4,
                background: active ? "var(--dark-border)" : "transparent",
                border: "none",
                color: active ? "var(--dark-fg)" : "var(--dark-fg-subtle)",
                fontFamily: FONT_MONO,
                fontSize: 11,
                fontWeight: 600,
                cursor: "pointer",
                letterSpacing: 0.5,
              }}
            >
              {l === "zh" ? "中" : "EN"}
            </button>
          );
        })}
      </div>
      <div
        style={{
          width: 24,
          height: 24,
          borderRadius: 12,
          background: "linear-gradient(135deg, #FFE7C4, #C98628 50%, #5D3000)",
          marginLeft: 10,
          border: "1px solid rgba(229,205,160,0.2)",
        }}
      />
    </div>
  );
}

function Logo() {
  return (
    <Link
      href="/"
      style={{
        display: "flex",
        alignItems: "center",
        gap: 7,
        padding: "0 6px",
        textDecoration: "none",
      }}
    >
      <svg width="18" height="18" viewBox="0 0 18 18" fill="none">
        <circle cx="9" cy="9" r="7.5" stroke="#C98628" strokeWidth="1.2" />
        <path d="M9 3 L11 9 L9 15 L7 9 Z" fill="#C98628" />
      </svg>
      <span
        style={{
          fontFamily: FONT_DISPLAY,
          fontSize: 13,
          fontWeight: 600,
          color: "var(--dark-fg)",
          letterSpacing: "-0.2px",
        }}
      >
        Solo Compass
      </span>
    </Link>
  );
}

// ───── List column ─────
interface ListColumnProps {
  T: Strings;
  lang: Lang;
  exps: readonly WebExperience[];
  activeCat: WebCategoryId | null;
  setActiveCat: (v: WebCategoryId | null) => void;
  activeSort: Sort;
  setActiveSort: (v: Sort) => void;
  hoverId: string | null;
  setHoverId: (v: string | null) => void;
  focusedId: string | null;
  setFocusedId: (v: string | null) => void;
}

function ListColumn(p: ListColumnProps) {
  return (
    <div
      style={{
        width: 480,
        flexShrink: 0,
        background: "var(--dark-surface)",
        borderRight: "1px solid var(--dark-border)",
        display: "flex",
        flexDirection: "column",
        minHeight: 0,
      }}
    >
      <div
        style={{
          padding: "20px 22px 12px",
          borderBottom: "1px solid var(--dark-border)",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "baseline",
            gap: 8,
            marginBottom: 14,
          }}
        >
          <div
            style={{
              fontFamily: p.lang === "zh" ? FONT_CN : FONT_DISPLAY,
              fontSize: 18,
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
            }}
          >
            {p.T.edition}
          </span>
        </div>
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 10,
            marginBottom: 10,
          }}
        >
          <span
            style={{
              fontFamily: FONT_MONO,
              fontSize: 10,
              color: "var(--dark-fg-faint)",
              letterSpacing: 1,
              textTransform: "uppercase",
            }}
          >
            {p.T.sortBy}
          </span>
          {(
            [
              { id: "curated", label: p.T.curated },
              { id: "recent", label: p.T.recent },
              { id: "distance", label: p.T.distance },
            ] as const
          ).map((s) => {
            const a = p.activeSort === s.id;
            return (
              <button
                key={s.id}
                type="button"
                onClick={() => p.setActiveSort(s.id)}
                style={{
                  background: "transparent",
                  border: "none",
                  fontFamily: p.lang === "zh" ? FONT_CN : FONT_DISPLAY,
                  fontSize: 12,
                  fontWeight: a ? 600 : 500,
                  color: a ? "var(--dark-fg)" : "var(--dark-fg-subtle)",
                  cursor: "pointer",
                  padding: 0,
                  borderBottom: a ? "1.5px solid var(--accent-amber)" : "1.5px solid transparent",
                  paddingBottom: 2,
                }}
              >
                {s.label}
              </button>
            );
          })}
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 5 }}>
          <CatChip
            active={p.activeCat === null}
            onClick={() => p.setActiveCat(null)}
            color="#C98628"
          >
            {p.T.allCats}
          </CatChip>
          {(Object.entries(WEB_CATS) as [WebCategoryId, (typeof WEB_CATS)[WebCategoryId]][]).map(
            ([k, c]) => (
              <CatChip
                key={k}
                active={p.activeCat === k}
                color={c.color}
                onClick={() => p.setActiveCat(p.activeCat === k ? null : k)}
              >
                {p.lang === "zh" ? c.zh : c.en}
              </CatChip>
            ),
          )}
        </div>
      </div>
      <div className="lc-scroll" style={{ flex: 1, overflow: "auto", minHeight: 0 }}>
        {p.exps.map((e, i) => (
          <ListRow
            key={e.id}
            exp={e}
            lang={p.lang}
            hover={p.hoverId === e.id}
            focused={p.focusedId === e.id}
            onMouseEnter={() => p.setHoverId(e.id)}
            onMouseLeave={() => p.setHoverId(null)}
            onClick={() => p.setFocusedId(e.id)}
            index={i}
          />
        ))}
      </div>
    </div>
  );
}

function CatChip({
  children,
  active,
  color,
  onClick,
}: {
  children: React.ReactNode;
  active: boolean;
  color: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        padding: "3px 8px",
        borderRadius: 4,
        background: active ? `${color}22` : "transparent",
        border: `0.5px solid ${active ? color : "var(--dark-border-strong)"}`,
        color: active ? color : "var(--dark-fg-subtle)",
        fontFamily: FONT_DISPLAY,
        fontSize: 11,
        fontWeight: 500,
        cursor: "pointer",
      }}
    >
      {children}
    </button>
  );
}

function ListRow({
  exp,
  lang,
  hover,
  focused,
  onMouseEnter,
  onMouseLeave,
  onClick,
  index,
}: {
  exp: WebExperience;
  lang: Lang;
  hover: boolean;
  focused: boolean;
  onMouseEnter: () => void;
  onMouseLeave: () => void;
  onClick: () => void;
  index: number;
}) {
  const cat = WEB_CATS[exp.cat];
  const title = lang === "zh" ? exp.titleZh : exp.title;
  const place = lang === "zh" ? exp.placeZh : exp.place;
  const tags = lang === "zh" ? exp.tagsZh : exp.tags;
  return (
    <div
      onMouseEnter={onMouseEnter}
      onMouseLeave={onMouseLeave}
      onClick={onClick}
      style={{
        padding: "14px 22px",
        paddingLeft: focused ? 20 : 22,
        borderBottom: "1px solid var(--dark-border-soft)",
        background: focused
          ? "var(--dark-surface-focused)"
          : hover
            ? "var(--dark-surface-hover)"
            : "transparent",
        cursor: "pointer",
        position: "relative",
        borderLeft: focused ? `2px solid ${cat.color}` : "2px solid transparent",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "baseline",
          gap: 8,
          marginBottom: 5,
        }}
      >
        <span
          style={{
            fontFamily: FONT_MONO,
            fontSize: 10,
            color: "var(--dark-fg-faint)",
            minWidth: 22,
          }}
        >
          {String(index + 1).padStart(2, "0")}
        </span>
        <div style={{ display: "inline-flex", alignItems: "center", gap: 5 }}>
          <div
            style={{
              width: 6,
              height: 6,
              borderRadius: 3,
              background: cat.color,
            }}
          />
          <span
            style={{
              fontFamily: FONT_MONO,
              fontSize: 10,
              color: cat.color,
              letterSpacing: 1,
              textTransform: "uppercase",
            }}
          >
            {cat.short}
          </span>
        </div>
        <span style={{ flex: 1 }} />
        <span
          style={{
            fontFamily: FONT_MONO,
            fontSize: 10,
            color: "var(--dark-fg-subtle)",
          }}
        >
          {exp.walkMin} min
        </span>
      </div>
      <div
        style={{
          fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
          fontSize: 14.5,
          fontWeight: 600,
          color: "var(--dark-fg)",
          lineHeight: 1.35,
          marginBottom: 4,
          letterSpacing: lang === "zh" ? "0.1px" : "-0.2px",
        }}
      >
        {title}
      </div>
      <div
        style={{
          fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
          fontSize: 12,
          color: "var(--dark-fg-subtle)",
          marginBottom: 8,
        }}
      >
        {place} · {exp.neighborhood}
      </div>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 5,
          flexWrap: "wrap",
        }}
      >
        {tags.slice(0, 3).map((t) => (
          <span
            key={t}
            style={{
              fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
              fontSize: 10.5,
              color: "var(--dark-fg-subtle)",
              padding: "1.5px 7px",
              borderRadius: 3,
              background: "var(--dark-border-soft)",
              border: "0.5px solid var(--dark-border)",
            }}
          >
            {t}
          </span>
        ))}
        <span style={{ flex: 1 }} />
        <span
          style={{
            fontFamily: FONT_MONO,
            fontSize: 9.5,
            color: "var(--dark-fg-faint)",
          }}
        >
          {exp.sources} src
        </span>
      </div>
    </div>
  );
}

// ───── Right surface ─────
interface RightSurfaceProps {
  T: Strings;
  lang: Lang;
  hoverId: string | null;
  setHoverId: (v: string | null) => void;
  focusedId: string | null;
  setFocusedId: (v: string | null) => void;
  focused: WebExperience | null;
}

function RightSurface(p: RightSurfaceProps) {
  return (
    <div
      style={{
        flex: 1,
        position: "relative",
        minWidth: 0,
        background: "var(--dark-bg)",
      }}
    >
      <div style={{ position: "absolute", inset: 0 }}>
        <WebLisbonMap
          pins={WEB_EXPS}
          hoverId={p.hoverId}
          focusedId={p.focusedId}
          onHover={p.setHoverId}
          onTap={p.setFocusedId}
          dark
        />
      </div>

      <div
        style={{
          position: "absolute",
          top: 16,
          right: 16,
          display: "flex",
          flexDirection: "column",
          gap: 4,
        }}
      >
        {["+", "−", "⌖"].map((c) => (
          <button
            key={c}
            type="button"
            style={{
              width: 30,
              height: 30,
              borderRadius: 6,
              background: "rgba(21,17,13,0.8)",
              backdropFilter: "blur(8px)",
              border: "0.5px solid var(--dark-border)",
              color: "var(--dark-fg-secondary)",
              fontFamily: FONT_DISPLAY,
              fontSize: 14,
              cursor: "pointer",
            }}
          >
            {c}
          </button>
        ))}
      </div>

      <div
        style={{
          position: "absolute",
          top: 16,
          left: 16,
          background: "rgba(21,17,13,0.85)",
          backdropFilter: "blur(10px)",
          border: "0.5px solid var(--dark-border)",
          borderRadius: 8,
          padding: "10px 14px",
          display: "flex",
          flexDirection: "column",
          gap: 7,
          minWidth: 200,
        }}
      >
        <div
          style={{
            fontFamily: FONT_MONO,
            fontSize: 10,
            color: "var(--dark-fg-faint)",
            letterSpacing: 1.2,
            textTransform: "uppercase",
          }}
        >
          Lisbon · Centro Histórico
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <div
              style={{
                width: 16,
                height: 2,
                background: "rgba(201,134,40,0.55)",
                borderRadius: 1,
              }}
            />
            <span
              style={{
                fontFamily: p.lang === "zh" ? FONT_CN : FONT_DISPLAY,
                fontSize: 11,
                color: "var(--dark-fg-muted)",
              }}
            >
              {p.T.tram}
            </span>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <div
              style={{
                width: 5,
                height: 5,
                borderRadius: 3,
                background: "var(--accent-amber)",
              }}
            />
            <span
              style={{
                fontFamily: p.lang === "zh" ? FONT_CN : FONT_DISPLAY,
                fontSize: 11,
                color: "var(--dark-fg-muted)",
              }}
            >
              {WEB_EXPS.length} {p.T.pinned}
            </span>
          </div>
        </div>
      </div>

      {p.focused && (
        <DetailDock exp={p.focused} lang={p.lang} T={p.T} onClose={() => p.setFocusedId(null)} />
      )}
    </div>
  );
}

function DetailDock({
  exp,
  lang,
  T,
  onClose,
}: {
  exp: WebExperience;
  lang: Lang;
  T: Strings;
  onClose: () => void;
}) {
  const cat = WEB_CATS[exp.cat];
  const title = lang === "zh" ? exp.titleZh : exp.title;
  const place = lang === "zh" ? exp.placeZh : exp.place;
  const why = lang === "zh" ? exp.whyZh : exp.why;
  const moment = lang === "zh" ? exp.momentZh : exp.moment;
  const aiReason = lang === "zh" ? exp.aiReasonZh : exp.aiReason;
  const tags = lang === "zh" ? exp.tagsZh : exp.tags;
  const detailHref = `/experience/${exp.id}${lang === "en" ? "?lang=en" : ""}`;
  return (
    <div
      style={{
        position: "absolute",
        left: 24,
        right: 24,
        bottom: 24,
        background: "rgba(21,17,13,0.92)",
        backdropFilter: "blur(20px) saturate(180%)",
        border: "0.5px solid var(--dark-border)",
        borderRadius: 12,
        padding: "18px 22px 16px",
        display: "flex",
        gap: 24,
        boxShadow: "0 12px 40px rgba(0,0,0,0.5), 0 1px 0 rgba(229,205,160,0.04) inset",
        minHeight: 220,
      }}
    >
      <button
        type="button"
        onClick={onClose}
        aria-label="Close"
        style={{
          position: "absolute",
          top: 10,
          right: 12,
          width: 22,
          height: 22,
          borderRadius: 11,
          background: "transparent",
          border: "0.5px solid var(--dark-border-strong)",
          color: "var(--dark-fg-subtle)",
          fontFamily: FONT_DISPLAY,
          fontSize: 11,
          cursor: "pointer",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        ✕
      </button>

      <div
        style={{
          width: 140,
          flexShrink: 0,
          display: "flex",
          flexDirection: "column",
          gap: 9,
        }}
      >
        <div style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
          <div
            style={{
              width: 6,
              height: 6,
              borderRadius: 3,
              background: cat.color,
            }}
          />
          <span
            style={{
              fontFamily: FONT_MONO,
              fontSize: 10,
              color: cat.color,
              letterSpacing: 1.2,
              textTransform: "uppercase",
            }}
          >
            {cat.short}
          </span>
        </div>
        <MetaRow k={T.walk} v={`${exp.walkMin} min`} />
        <MetaRow
          k={T.best}
          v={`${exp.bestHours[0]}–${exp.bestHours[exp.bestHours.length - 1]! + 1}h`}
        />
        <MetaRow k={T.stay} v={`${exp.durationMin} min`} />
        <MetaRow k={T.price} v={exp.pricePill} />
        <MetaRow k={T.crowd} v={exp.crowd} />
        <div style={{ flex: 1 }} />
        <div
          style={{
            fontFamily: FONT_MONO,
            fontSize: 9.5,
            color: "var(--dark-fg-faint)",
            lineHeight: 1.5,
          }}
        >
          {T.verified} {exp.lastVerified}
          <br />
          {exp.sources} {T.sources.toLowerCase()}
        </div>
      </div>

      <div style={{ flex: 1, minWidth: 0 }}>
        <div
          style={{
            fontFamily: FONT_MONO,
            fontSize: 10,
            color: "var(--dark-fg-subtle)",
            letterSpacing: 1.2,
            textTransform: "uppercase",
            marginBottom: 6,
          }}
        >
          {place} · {exp.neighborhood}
        </div>
        <div
          style={{
            fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
            fontSize: 22,
            fontWeight: 600,
            color: "var(--dark-fg)",
            letterSpacing: lang === "zh" ? "0.2px" : "-0.4px",
            lineHeight: 1.25,
            marginBottom: 12,
          }}
        >
          <Link href={detailHref} style={{ color: "inherit", textDecoration: "none" }}>
            {title}
          </Link>
        </div>
        <div
          style={{
            fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
            fontSize: 13.5,
            color: "var(--dark-fg-tertiary)",
            lineHeight: 1.55,
            marginBottom: 14,
          }}
        >
          {why}
        </div>
        <div
          style={{
            fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
            fontSize: 13,
            color: "var(--dark-fg-muted)",
            lineHeight: 1.5,
            paddingLeft: 10,
            borderLeft: "2px solid var(--accent-amber)",
            marginBottom: 14,
            fontStyle: lang === "zh" ? "normal" : "italic",
          }}
        >
          “{moment}”
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 5 }}>
          {tags.map((t) => (
            <span
              key={t}
              style={{
                fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
                fontSize: 11,
                color: "var(--dark-fg-muted)",
                padding: "2px 8px",
                borderRadius: 3,
                background: "var(--dark-border-soft)",
                border: "0.5px solid var(--dark-border)",
              }}
            >
              {t}
            </span>
          ))}
        </div>
      </div>

      <div
        style={{
          width: 240,
          flexShrink: 0,
          background: "rgba(201,134,40,0.06)",
          border: "0.5px solid rgba(201,134,40,0.2)",
          borderRadius: 8,
          padding: 13,
          display: "flex",
          flexDirection: "column",
        }}
      >
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 6,
            marginBottom: 9,
          }}
        >
          <div
            style={{
              width: 16,
              height: 16,
              borderRadius: 8,
              background: "linear-gradient(135deg, #FFE7C4, #C98628)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <span style={{ fontSize: 9, color: "#FFF" }}>✦</span>
          </div>
          <span
            style={{
              fontFamily: FONT_MONO,
              fontSize: 10,
              color: "var(--accent-amber)",
              letterSpacing: 1.2,
              textTransform: "uppercase",
            }}
          >
            {T.forYou}
          </span>
        </div>
        <div
          style={{
            fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
            fontSize: 12.5,
            color: "var(--dark-fg-secondary)",
            lineHeight: 1.55,
            flex: 1,
          }}
        >
          {aiReason}
        </div>
        <div style={{ display: "flex", gap: 6, marginTop: 12 }}>
          <button
            type="button"
            style={{
              flex: 1,
              padding: "7px 0",
              borderRadius: 5,
              background: "var(--accent-amber)",
              border: "none",
              color: "var(--dark-surface)",
              fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
              fontSize: 12,
              fontWeight: 600,
              cursor: "pointer",
            }}
          >
            {T.addToPlan}
          </button>
          <Link
            href={detailHref}
            style={{
              padding: "7px 12px",
              borderRadius: 5,
              background: "transparent",
              border: "0.5px solid var(--dark-border-strong)",
              color: "var(--dark-fg-muted)",
              fontFamily: lang === "zh" ? FONT_CN : FONT_DISPLAY,
              fontSize: 12,
              cursor: "pointer",
              textDecoration: "none",
              display: "inline-flex",
              alignItems: "center",
            }}
          >
            {lang === "zh" ? "详情" : "Details"} →
          </Link>
        </div>
      </div>
    </div>
  );
}

function MetaRow({ k, v }: { k: string; v: string }) {
  return (
    <div
      style={{
        display: "flex",
        justifyContent: "space-between",
        fontFamily: FONT_MONO,
        fontSize: 11,
      }}
    >
      <span style={{ color: "var(--dark-fg-faint)" }}>{k}</span>
      <span style={{ color: "var(--dark-fg-secondary)" }}>{v}</span>
    </div>
  );
}

function StatusBar({ T, lang }: { T: Strings; lang: Lang }) {
  return (
    <div
      style={{
        height: 26,
        flexShrink: 0,
        background: "var(--dark-surface)",
        borderTop: "1px solid var(--dark-border)",
        display: "flex",
        alignItems: "center",
        gap: 14,
        padding: "0 14px",
        fontFamily: FONT_MONO,
        fontSize: 10,
        color: "var(--dark-fg-faint)",
        letterSpacing: 0.4,
      }}
    >
      <span style={{ color: "var(--accent-amber)" }}>●</span>
      <span>compass.io / lisbon</span>
      <span style={{ color: "var(--dark-border-strong)" }}>·</span>
      <span>
        {WEB_EXPS.length} exp · {Object.keys(WEB_CATS).length} cats · 234 sources
      </span>
      <span style={{ flex: 1 }} />
      <span>{T.lastEdit}</span>
      <span style={{ color: "var(--dark-border-strong)" }}>·</span>
      <span>v0.4.2</span>
      <span style={{ color: "var(--dark-border-strong)" }}>·</span>
      <span>{lang}</span>
    </div>
  );
}
