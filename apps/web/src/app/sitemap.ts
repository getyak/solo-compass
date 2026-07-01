import type { MetadataRoute } from "next";

/**
 * Sitemap — Next.js App Router auto-generates /sitemap.xml
 * Doc: SEO_STRATEGY.md §6 (Technical SEO)
 *
 * Phase 1 covers: home (EN + ZH), pricing (EN + ZH), manifesto,
 * privacy, download. City / experience / blog pages will be added
 * once those routes exist.
 */

const SITE_URL = "https://solocompass.app";
const NOW = new Date();

type Freq = MetadataRoute.Sitemap[number]["changeFrequency"];

export default function sitemap(): MetadataRoute.Sitemap {
  const staticPaths: { path: string; priority: number; freq: Freq }[] = [
    { path: "/", priority: 1.0, freq: "weekly" },
    { path: "/zh", priority: 1.0, freq: "weekly" },
    { path: "/pricing", priority: 0.9, freq: "monthly" },
    { path: "/zh/pricing", priority: 0.9, freq: "monthly" },
    { path: "/manifesto", priority: 0.7, freq: "monthly" },
    { path: "/zh/manifesto", priority: 0.7, freq: "monthly" },
    { path: "/privacy", priority: 0.6, freq: "monthly" },
    { path: "/zh/privacy", priority: 0.6, freq: "monthly" },
    { path: "/download", priority: 0.8, freq: "monthly" },
  ];

  return staticPaths.map((s) => ({
    url: `${SITE_URL}${s.path}`,
    lastModified: NOW,
    changeFrequency: s.freq,
    priority: s.priority,
    alternates: s.path.startsWith("/zh")
      ? {
          languages: {
            en: `${SITE_URL}${s.path.replace(/^\/zh/, "") || "/"}`,
            "zh-CN": `${SITE_URL}${s.path}`,
          },
        }
      : {
          languages: {
            en: `${SITE_URL}${s.path}`,
            "zh-CN": `${SITE_URL}/zh${s.path === "/" ? "" : s.path}`,
          },
        },
  }));
}
