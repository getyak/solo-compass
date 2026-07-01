import type { Metadata } from "next";
import {
  Capabilities,
  Footer,
  Hero,
  MarketingNav,
  Pillars,
  Pricing,
  Problem,
  Trust,
} from "@/components/marketing/sections";
import { copy } from "@/components/marketing/copy";
import { HomeJsonLd } from "./_seo";

const SITE_URL = "https://solocompass.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Solo Compass · A map for people who travel alone",
  description:
    "A map-first companion for solo travelers on iOS. Cross-referenced sources, honest AI, no ads, no tracking. $29 one-time or $50 a year.",
  keywords: [
    "solo travel app",
    "solo travel companion",
    "iOS travel app",
    "map-first travel",
    "privacy-focused travel app",
    "AI travel assistant",
    "digital nomad app",
  ],
  authors: [{ name: "Solo Compass" }],
  openGraph: {
    type: "website",
    url: SITE_URL,
    siteName: "Solo Compass",
    title: "A map for people who travel alone.",
    description:
      "Map-first. Experience-as-unit. AI that filters — never decides. Made in Kyoto. No ads, no tracking, ever.",
    locale: "en_US",
    alternateLocale: "zh_CN",
    // og image comes from src/app/opengraph-image.tsx (file-based).
  },
  twitter: {
    card: "summary_large_image",
    title: "Solo Compass · A map for people who travel alone",
    description:
      "Map-first companion for solo travelers on iOS. No ads. No tracking. $29 one-time or $50 a year.",
    // twitter image comes from src/app/opengraph-image.tsx (Next reuses it).
  },
  alternates: {
    canonical: SITE_URL,
    languages: {
      en: SITE_URL,
      "zh-CN": `${SITE_URL}/zh`,
      "x-default": SITE_URL,
    },
  },
  category: "travel",
};

export default function Home() {
  const props = {
    copy: copy.en,
    locale: "en" as const,
    homePath: "/",
    altPath: "/zh",
  };
  return (
    <>
      <HomeJsonLd locale="en" />
      <MarketingNav {...props} />
      <main id="main">
        <Hero {...props} />
        <Problem {...props} />
        <Pillars {...props} />
        <Capabilities {...props} />
        <Trust {...props} />
        <Pricing {...props} />
      </main>
      <Footer {...props} />
    </>
  );
}
