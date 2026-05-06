"use client";

/**
 * WebLisbonMap — pure SVG hand-drawn map for Scenario A (`/lisbon`).
 *
 * 1000 × 700 viewBox. Same DNA as the iOS map but darker by default to fit
 * the Linear/Arc software-tool aesthetic. Pin coordinates are in the same
 * canvas space (see `WebExperience.x` / `.y`).
 *
 * Not Mapbox. Not geographic. Editorial.
 */

import type { CSSProperties } from "react";
import { WEB_CATS, type WebCategoryId, type WebExperience } from "@/lib/lisbon-data";

interface WebLisbonMapProps {
  readonly pins: readonly WebExperience[];
  readonly hoverId?: string | null;
  readonly focusedId?: string | null;
  readonly onHover?: (id: string | null) => void;
  readonly onTap?: (id: string) => void;
  readonly dark?: boolean;
  readonly style?: CSSProperties;
}

export function WebLisbonMap({
  pins,
  hoverId = null,
  focusedId = null,
  onHover,
  onTap,
  dark = true,
  style,
}: WebLisbonMapProps) {
  const bg = dark ? "#1A1714" : "#F4ECDD";
  const water = dark ? "#221C16" : "#E6D8B6";
  const land = dark ? "#28221B" : "#EFE5CB";
  const street = dark ? "rgba(229,205,160,0.12)" : "rgba(93,48,0,0.16)";
  const streetMain = dark ? "rgba(229,205,160,0.22)" : "rgba(93,48,0,0.30)";
  const label = dark ? "rgba(229,205,160,0.55)" : "rgba(43,30,12,0.55)";
  const sub = dark ? "rgba(229,205,160,0.32)" : "rgba(43,30,12,0.32)";
  const dustOpacity = dark ? "rgba(229,205,160,0.025)" : "rgba(93,48,0,0.04)";
  const riverEdge = dark ? "rgba(229,205,160,0.25)" : "rgba(93,48,0,0.30)";
  const waveStroke = dark ? "rgba(229,205,160,0.10)" : "rgba(93,48,0,0.12)";
  const contour = dark ? "rgba(229,205,160,0.06)" : "rgba(93,48,0,0.08)";
  const tramStroke = dark ? "rgba(201,134,40,0.45)" : "rgba(201,134,40,0.55)";
  const pinHole = dark ? "#1A1714" : "#F4ECDD";

  return (
    <svg
      viewBox="0 0 1000 700"
      preserveAspectRatio="xMidYMid slice"
      style={{
        width: "100%",
        height: "100%",
        display: "block",
        background: bg,
        ...style,
      }}
    >
      <defs>
        <radialGradient id="webMapVignette" cx="50%" cy="55%" r="65%">
          <stop offset="0%" stopColor={bg} stopOpacity="0" />
          <stop offset="100%" stopColor={bg} stopOpacity={dark ? 0.6 : 0.3} />
        </radialGradient>
        <pattern id="webPaper" width="3" height="3" patternUnits="userSpaceOnUse">
          <rect width="3" height="3" fill={bg} />
          <circle cx="1" cy="1" r="0.4" fill={dustOpacity} />
        </pattern>
      </defs>

      <rect width="1000" height="700" fill="url(#webPaper)" />

      {/* River Tagus */}
      <path
        d="M -20 540 C 200 530, 380 555, 560 590 C 720 620, 880 640, 1020 645 L 1020 720 L -20 720 Z"
        fill={water}
      />
      <path
        d="M -20 540 C 200 530, 380 555, 560 590 C 720 620, 880 640, 1020 645"
        fill="none"
        stroke={riverEdge}
        strokeWidth="1"
      />

      {[0, 1, 2, 3, 4, 5, 6, 7, 8].map((i) => (
        <path
          key={i}
          d={`M ${50 + i * 110} ${640 + (i % 2) * 8} q 12 -3 24 0 t 24 0`}
          fill="none"
          stroke={waveStroke}
          strokeWidth="0.8"
        />
      ))}

      {/* Land overlay */}
      <path
        d="M -20 -20 L 1020 -20 L 1020 600 C 880 600, 720 580, 560 555 C 380 525, 200 500, -20 510 Z"
        fill={land}
        opacity="0.5"
      />

      {/* Av da Liberdade spine */}
      <path
        d="M 480 100 L 470 280 L 460 380"
        fill="none"
        stroke={streetMain}
        strokeWidth="3"
        strokeLinecap="round"
      />
      <path
        d="M 460 380 L 440 420 L 380 460"
        fill="none"
        stroke={streetMain}
        strokeWidth="2"
        strokeLinecap="round"
      />

      {/* Tram 28 */}
      <path
        d="M 240 410 Q 380 380 480 410 Q 580 430 700 360 Q 760 320 800 250"
        fill="none"
        stroke={tramStroke}
        strokeWidth="1.5"
        strokeDasharray="3 4"
        strokeLinecap="round"
      />

      <g stroke={street} strokeWidth="1" strokeLinecap="round" fill="none">
        <path d="M 200 200 L 720 220" />
        <path d="M 180 280 L 760 300" />
        <path d="M 220 340 L 740 360" />
        <path d="M 260 410 L 720 420" />
        <path d="M 300 470 L 700 470" />
        <path d="M 350 200 L 340 540" />
        <path d="M 420 180 L 410 540" />
        <path d="M 530 200 L 540 555" />
        <path d="M 600 180 L 620 545" />
        <path d="M 670 200 L 690 530" />
      </g>

      {/* Castelo de São Jorge */}
      <g transform="translate(640 290)">
        <path
          d="M -16 0 L -16 -10 L -10 -10 L -10 -14 L -4 -14 L -4 -10 L 4 -10 L 4 -14 L 10 -14 L 10 -10 L 16 -10 L 16 0 Z"
          fill="none"
          stroke={label}
          strokeWidth="1.2"
          strokeLinejoin="round"
        />
      </g>

      <g fill="none" stroke={contour} strokeWidth="0.8">
        <ellipse cx="640" cy="290" rx="80" ry="55" />
        <ellipse cx="640" cy="290" rx="60" ry="42" />
        <ellipse cx="640" cy="290" rx="40" ry="28" />
      </g>

      <rect width="1000" height="700" fill="url(#webMapVignette)" pointerEvents="none" />

      {/* Neighborhood labels */}
      <g
        style={{
          fontFamily: "JetBrains Mono, ui-monospace, monospace",
          fontSize: 9,
          letterSpacing: 1.5,
          textTransform: "uppercase",
          userSelect: "none",
        }}
      >
        <text x="640" y="245" fill={label} textAnchor="middle">
          CASTELO
        </text>
        <text x="430" y="380" fill={label} textAnchor="middle">
          CHIADO
        </text>
        <text x="490" y="450" fill={label} textAnchor="middle">
          BAIRRO ALTO
        </text>
        <text x="700" y="335" fill={label} textAnchor="middle">
          ALFAMA
        </text>
        <text x="610" y="270" fill={label} textAnchor="middle">
          GRAÇA
        </text>
        <text x="240" y="540" fill={sub} textAnchor="middle">
          BELÉM
        </text>
        <text x="800" y="618" fill={sub} textAnchor="middle">
          RIO TEJO
        </text>
      </g>

      {/* Pins */}
      {pins.map((p) => {
        const cat = WEB_CATS[p.cat as WebCategoryId];
        const isHover = hoverId === p.id;
        const isFocus = focusedId === p.id;
        const r = isFocus ? 8 : isHover ? 7 : 5;
        const ringR = isHover || isFocus ? 22 : 14;
        return (
          <g
            key={p.id}
            transform={`translate(${p.x} ${p.y})`}
            style={{ cursor: "pointer" }}
            onMouseEnter={() => onHover?.(p.id)}
            onMouseLeave={() => onHover?.(null)}
            onClick={() => onTap?.(p.id)}
          >
            {(isHover || isFocus) && (
              <circle r={ringR} fill={cat.color} opacity="0.18" className="sc-halo" />
            )}
            <circle r={r + 2} fill={pinHole} />
            <circle r={r} fill={cat.color} />
            {isFocus && (
              <circle r={r + 4} fill="none" stroke={cat.color} strokeWidth="1.2" opacity="0.7" />
            )}
          </g>
        );
      })}
    </svg>
  );
}
