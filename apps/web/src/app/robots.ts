import type { MetadataRoute } from "next";

/**
 * robots.txt — Next.js App Router auto-generates /robots.txt
 * Doc: SEO_STRATEGY.md §6
 */

const SITE_URL = "https://solocompass.app";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        disallow: ["/api/", "/app/"],
      },
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
    host: SITE_URL,
  };
}
