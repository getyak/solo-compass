import { ImageResponse } from "next/og";

// Next.js file-based apple-touch-icon: auto-served at /apple-icon and
// injected as <link rel="apple-touch-icon"> in <head>.
export const size = { width: 180, height: 180 };
export const contentType = "image/png";

export default function AppleIcon() {
  return new ImageResponse(
    <div
      style={{
        fontSize: 120,
        background: "#FAF8F6",
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        color: "#B8935B",
        fontFamily: "sans-serif",
        fontWeight: 700,
        letterSpacing: -4,
        borderRadius: 40,
      }}
    >
      SC
    </div>,
    { ...size },
  );
}
