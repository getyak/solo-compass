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
import { HomeJsonLd } from "../_seo";

const SITE_URL = "https://solocompass.app";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: "Solo Compass · 一款为独自旅行者做的地图 app",
  description:
    "为独自旅行者做的 iOS 地图 app。以体验为单位而非景点列表，跨来源交叉编译数据，AI 只帮你过滤而不替你决定，无广告无追踪。¥118 一次买断，¥198 每年，可先免费试用。",
  keywords: [
    "独自旅行 app",
    "一个人旅行 app",
    "独行罗盘",
    "Solo Compass",
    "iOS 旅行 app",
    "隐私 旅行 app",
    "AI 旅行规划",
  ],
  openGraph: {
    type: "website",
    url: `${SITE_URL}/zh`,
    siteName: "Solo Compass",
    title: "一款为独自旅行者做的地图 app",
    description:
      "地图为家。以\"体验\"为单位。AI 只过滤，不替你决定。京都独立开发。永不接广告、永不追踪。",
    locale: "zh_CN",
    alternateLocale: "en_US",
    // og image comes from src/app/zh/opengraph-image.tsx (file-based).
  },
  twitter: {
    card: "summary_large_image",
    title: "Solo Compass · 一款为独自旅行者做的地图 app",
    description: "iOS 独行者地图。¥118 一次买断，¥198 每年。无广告，无追踪。",
    // twitter image comes from src/app/zh/opengraph-image.tsx.
  },
  alternates: {
    canonical: `${SITE_URL}/zh`,
    languages: {
      en: SITE_URL,
      "zh-CN": `${SITE_URL}/zh`,
      "x-default": SITE_URL,
    },
  },
  category: "travel",
};

export default function HomeZh() {
  const props = {
    copy: copy.zh,
    locale: "zh" as const,
    homePath: "/zh",
    altPath: "/",
  };
  return (
    <div lang="zh-CN">
      <HomeJsonLd locale="zh" />
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
    </div>
  );
}
