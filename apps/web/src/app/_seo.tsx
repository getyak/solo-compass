/**
 * SEO — JSON-LD Schema.org structured data.
 * Doc: SEO_STRATEGY.md §5
 *
 * Rendered inline via a Server Component so search engines see
 * it on first crawl without hydration.
 */

import type { Locale } from "@/components/marketing/copy";

const SITE_URL = "https://solocompass.app";

export function HomeJsonLd({ locale }: { locale: Locale }) {
  const url = locale === "zh" ? `${SITE_URL}/zh` : SITE_URL;
  const name = locale === "zh" ? "Solo Compass · 独行罗盘" : "Solo Compass";
  const description =
    locale === "zh"
      ? "为独自旅行者做的 iOS 地图应用。跨来源交叉编译，AI 展示不确定性，无广告，无追踪。¥118 一次买断，¥198 每年。"
      : "A map-first companion for solo travelers on iOS. Cross-referenced sources, honest AI, no ads, no tracking. $29 one-time or $50 a year.";

  const softwareApp = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name,
    url,
    operatingSystem: "iOS 17.0+",
    applicationCategory: "TravelApplication",
    description,
    offers: [
      {
        "@type": "Offer",
        price: "0",
        priceCurrency: locale === "zh" ? "CNY" : "USD",
        description: locale === "zh" ? "免费" : "Free",
      },
      {
        "@type": "Offer",
        price: locale === "zh" ? "118" : "29",
        priceCurrency: locale === "zh" ? "CNY" : "USD",
        description: locale === "zh" ? "一次买断" : "Lifetime",
      },
      {
        "@type": "Offer",
        price: locale === "zh" ? "198" : "50",
        priceCurrency: locale === "zh" ? "CNY" : "USD",
        description: locale === "zh" ? "年度订阅" : "Yearly",
      },
    ],
    creator: {
      "@type": "Organization",
      name: "Solo Compass",
      url: SITE_URL,
    },
    inLanguage: locale === "zh" ? "zh-CN" : "en",
  };

  const organization = {
    "@context": "https://schema.org",
    "@type": "Organization",
    name: "Solo Compass",
    url: SITE_URL,
    logo: `${SITE_URL}/icon-512.png`,
    sameAs: [
      "https://twitter.com/solocompassapp",
      "https://github.com/solo-compass",
    ],
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(softwareApp) }}
      />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(organization) }}
      />
    </>
  );
}
