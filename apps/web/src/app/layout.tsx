import type { Metadata, Viewport } from "next";
import "./globals.css";
import { QueryProvider } from "@/lib/query-client";
import { AnalyticsBoot } from "@/lib/analytics";

export const metadata: Metadata = {
  title: "Solo Compass",
  description: "A map-first, experience-as-unit, AI-curated companion for solo travelers.",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  themeColor: "#F5F1E8",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  // suppressHydrationWarning silences mismatches caused by browser extensions
  // (e.g. Immersive Translate) that inject attributes onto <html>/<body>
  // before React hydrates. Scoped to these two elements only — descendant
  // hydration checks remain strict.
  return (
    <html lang="en" suppressHydrationWarning>
      <body suppressHydrationWarning>
        <QueryProvider>
          <AnalyticsBoot />
          {children}
        </QueryProvider>
      </body>
    </html>
  );
}
