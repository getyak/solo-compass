import { ImageResponse } from "next/og";
import { getCompletionsRepo } from "@/lib/repos";
import { cityDisplayName, cityEmoji, countDays, formatTripDateRange } from "@/components/TripRecap";

export const runtime = "edge";
export const alt = "Solo Compass trip recap";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

interface ImageProps {
  params: Promise<{ handle: string; city: string }>;
}

export default async function OgImage({ params }: ImageProps) {
  const { handle, city } = await params;

  const completionsRepo = getCompletionsRepo();
  const completions = await completionsRepo.findByHandle(handle, city).catch(() => []);

  const cityName = cityDisplayName(city);
  const emoji = cityEmoji(city);
  const dateRange = formatTripDateRange(completions);
  const days = countDays(completions);
  const expCount = completions.length;

  return new ImageResponse(
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        width: "100%",
        height: "100%",
        backgroundColor: "#2C2A26",
        padding: "64px",
        fontFamily: "system-ui, -apple-system, sans-serif",
      }}
    >
      {/* Top label */}
      <div
        style={{
          display: "flex",
          fontSize: 18,
          fontWeight: 600,
          letterSpacing: "0.12em",
          textTransform: "uppercase",
          color: "#F5F1E8",
          opacity: 0.4,
          marginBottom: 24,
        }}
      >
        Solo Compass · Trip Recap
      </div>

      {/* City emoji + name */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 20,
          marginBottom: 16,
        }}
      >
        <span style={{ fontSize: 80 }}>{emoji}</span>
        <div style={{ display: "flex", flexDirection: "column" }}>
          <span
            style={{
              fontSize: 72,
              fontWeight: 700,
              color: "#F5F1E8",
              lineHeight: 1.1,
            }}
          >
            {cityName}
          </span>
        </div>
      </div>

      {/* Handle + dates */}
      <div
        style={{
          display: "flex",
          fontSize: 28,
          color: "#F5F1E8",
          opacity: 0.7,
          marginBottom: 48,
        }}
      >
        {handle}
        {dateRange ? ` · ${dateRange}` : ""}
      </div>

      {/* Stats row */}
      <div style={{ display: "flex", gap: 48, marginTop: "auto" }}>
        <StatBox value={expCount} label="Experiences" />
        <StatBox value={days} label="Days" />
      </div>

      {/* Brand mark */}
      <div
        style={{
          display: "flex",
          position: "absolute",
          bottom: 40,
          right: 64,
          fontSize: 20,
          fontWeight: 600,
          color: "#2F6B6B",
        }}
      >
        solo-compass.com
      </div>
    </div>,
    { ...size },
  );
}

function StatBox({ value, label }: { value: number; label: string }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "flex-start" }}>
      <span style={{ fontSize: 56, fontWeight: 700, color: "#F5F1E8", lineHeight: 1 }}>
        {value}
      </span>
      <span
        style={{
          fontSize: 16,
          fontWeight: 600,
          letterSpacing: "0.1em",
          textTransform: "uppercase",
          color: "#F5F1E8",
          opacity: 0.4,
          marginTop: 4,
        }}
      >
        {label}
      </span>
    </div>
  );
}
