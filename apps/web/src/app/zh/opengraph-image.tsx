import { ImageResponse } from "next/og";

// Next.js file-based OG image for /zh — auto-served at /zh/opengraph-image
// and injected as <meta property="og:image"> for the ZH root page.
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "Solo Compass — 一款为独自旅行者做的地图 app";

export default function OGImageZh() {
  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        background: "linear-gradient(135deg, #FAF8F6 0%, #F2E7D5 100%)",
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        padding: "80px",
        fontFamily: "sans-serif",
      }}
    >
      <div
        style={{
          fontSize: 24,
          color: "#B8935B",
          fontWeight: 600,
          letterSpacing: 4,
          textTransform: "uppercase",
          marginBottom: 32,
          display: "flex",
        }}
      >
        Solo Compass · iOS
      </div>
      <div
        style={{
          fontSize: 96,
          color: "#171410",
          fontWeight: 700,
          lineHeight: 1.05,
          letterSpacing: -3,
          display: "flex",
          maxWidth: 900,
        }}
      >
        一款为独自旅行者做的地图 app。
      </div>
      <div
        style={{
          fontSize: 32,
          color: "#4A4038",
          marginTop: 40,
          display: "flex",
          maxWidth: 900,
        }}
      >
        跨来源交叉编译 · 诚实的 AI · 无广告 · 无追踪
      </div>
    </div>,
    { ...size },
  );
}
