import { ImageResponse } from "next/og";

// Next.js file-based icon: auto-served at /icon and injected as <link rel="icon">.
export const size = { width: 32, height: 32 };
export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          fontSize: 22,
          background: "#FAF8F6",
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          color: "#B8935B",
          fontFamily: "sans-serif",
          fontWeight: 700,
          letterSpacing: -1,
        }}
      >
        SC
      </div>
    ),
    { ...size }
  );
}
