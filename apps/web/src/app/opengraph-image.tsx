import { ImageResponse } from "next/og";

// Next.js file-based OG image: auto-served at /opengraph-image and
// injected as <meta property="og:image"> for the root page.
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";
export const alt = "Solo Compass — A map for people who travel alone.";

export default function OGImage() {
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
        A map for people who travel alone.
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
        Cross-referenced sources · Honest AI · No ads · No tracking
      </div>
    </div>,
    { ...size },
  );
}
