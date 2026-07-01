import { test, expect, request as pwRequest } from "@playwright/test";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/**
 * SEO 100-point rubric — 18 dimensions × 2 locales (/ and /zh).
 * Baseline expectations from Lighthouse SEO, Google Search Central, and
 * schema.org best practices. Writes report to e2e/report/seo-score.{json,md}.
 *
 * Score is (en + zh) / 2, so both locales must be perfect for 100.
 */

interface Result {
  key: string;
  label: string;
  max: number;
  earned: number;
  note: string;
}

interface PageAudit {
  locale: "en" | "zh";
  path: string;
  results: Result[];
}

const LOCALES: { locale: "en" | "zh"; path: string; expectHtmlLang: string }[] = [
  { locale: "en", path: "/", expectHtmlLang: "en" },
  { locale: "zh", path: "/zh", expectHtmlLang: "zh-CN" },
];

test.describe("Solo Compass — SEO 100 rubric", () => {
  test("both locales", async ({ page, baseURL }) => {
    const audits: PageAudit[] = [];

    for (const { locale, path, expectHtmlLang } of LOCALES) {
      const errs: string[] = [];
      page.removeAllListeners("console");
      page.on("console", (msg) => {
        if (msg.type() === "error") errs.push(msg.text());
      });

      const results: Result[] = [];
      const record = (key: string, label: string, max: number, earned: number, note: string) => {
        results.push({ key, label, max, earned, note });
      };

      const resp = await page.goto(path, { waitUntil: "domcontentloaded" });
      void resp;

      /* 1. title 30–60 chars incl. brand */
      const title = await page.title();
      const titleLen = title.length;
      const titleHasBrand = /Solo Compass/i.test(title);
      const titleOk = titleLen >= 30 && titleLen <= 60 && titleHasBrand;
      const titleScore = titleOk ? 5 : titleHasBrand && titleLen > 0 ? 3 : 0;
      record("title", "Title 30–60 chars + brand", 5, titleScore,
        `len=${titleLen} brand=${titleHasBrand} · ${JSON.stringify(title.slice(0, 60))}`);

      /* 2. meta description length appropriate for locale
             — EN target 120–160 chars (Google SERP wraps ~160)
             — ZH target 70–100 chars (each CJK char ~= 2 latin chars visually) */
      const desc = (await page.locator('meta[name="description"]').first().getAttribute("content")) ?? "";
      const descLen = desc.length;
      const [descMin, descMax, descSoftMin, descSoftMax] = locale === "zh"
        ? [70, 100, 55, 130]
        : [120, 160, 80, 200];
      const descOk = descLen >= descMin && descLen <= descMax;
      const descSoft = descLen >= descSoftMin && descLen <= descSoftMax;
      const descScore = descOk ? 5 : descSoft ? 3 : descLen > 0 ? 1 : 0;
      record("description", `Meta description length (${descMin}–${descMax} for ${locale})`, 5, descScore, `len=${descLen}`);

      /* 3. single H1 non-empty */
      const h1s = await page.locator("main h1").allTextContents();
      const h1Ok = h1s.length === 1 && h1s[0]!.trim().length > 8;
      record("h1", "Exactly one H1, non-trivial", 6, h1Ok ? 6 : 0,
        `count=${h1s.length}${h1s[0] ? " · " + h1s[0].slice(0, 40) : ""}`);

      /* 4. heading hierarchy — no forward jumps (H1→H3 skipping H2 is bad;
             going back H3→H2 is fine — that's a new section) */
      const headings = await page.$$eval("main h1, main h2, main h3, main h4, main h5, main h6",
        (nodes) => nodes.map((n) => Number(n.tagName.substring(1))));
      let hierarchyOk = true;
      let deepestSoFar = 0;
      for (const level of headings) {
        if (level > deepestSoFar + 1) { hierarchyOk = false; break; }
        if (level > deepestSoFar) deepestSoFar = level;
      }
      const seenLevels = Array.from(new Set(headings)).sort();
      record("hierarchy", "Heading hierarchy has no forward jumps", 5, hierarchyOk ? 5 : 2,
        `levels seen: h${seenLevels.join(",h")}`);

      /* 5. canonical absolute */
      const canonical = await page.locator('link[rel="canonical"]').first().getAttribute("href");
      const canonicalOk = !!canonical && /^https?:\/\//.test(canonical);
      record("canonical", "Canonical link (absolute URL)", 6, canonicalOk ? 6 : 0,
        `canonical=${canonical}`);

      /* 6. hreflang en + zh-CN + x-default */
      const alt = await page.locator('link[rel="alternate"]').evaluateAll((els) =>
        els.map((e) => ({ hreflang: e.getAttribute("hreflang"), href: e.getAttribute("href") }))
      );
      const hasEn = alt.some((a) => a.hreflang === "en");
      const hasZh = alt.some((a) => a.hreflang === "zh-CN");
      const hasXDefault = alt.some((a) => a.hreflang === "x-default");
      const hreflangScore = (hasEn ? 3 : 0) + (hasZh ? 3 : 0) + (hasXDefault ? 2 : 0);
      record("hreflang", "hreflang en + zh-CN + x-default", 8, hreflangScore,
        `en=${hasEn} zh-CN=${hasZh} x-default=${hasXDefault}`);

      /* 7. Open Graph full set */
      const ogFields = ["og:title", "og:description", "og:image", "og:url", "og:type", "og:site_name"];
      let ogHit = 0;
      const ogMissing: string[] = [];
      for (const f of ogFields) {
        const v = await page.locator(`meta[property="${f}"]`).first().getAttribute("content").catch(() => null);
        if (v && v.length > 0) ogHit += 1;
        else ogMissing.push(f);
      }
      const ogScore = Math.round((ogHit / ogFields.length) * 6);
      record("og", "Open Graph (title/desc/image/url/type/site_name)", 6, ogScore,
        `${ogHit}/${ogFields.length}${ogMissing.length ? " missing " + ogMissing.join(",") : ""}`);

      /* 8. Twitter Card */
      const twFields = ["twitter:card", "twitter:title", "twitter:description", "twitter:image"];
      let twHit = 0;
      for (const f of twFields) {
        const v = await page.locator(`meta[name="${f}"]`).first().getAttribute("content").catch(() => null);
        if (v && v.length > 0) twHit += 1;
      }
      const twScore = Math.round((twHit / twFields.length) * 4);
      record("twitter", "Twitter Card (card/title/desc/image)", 4, twScore,
        `${twHit}/${twFields.length}`);

      /* 9. JSON-LD SoftwareApplication + Organization (parseable) */
      const jsonldRaw = await page.locator('script[type="application/ld+json"]').allTextContents();
      let hasSoftwareApp = false;
      let hasOrg = false;
      let parseOk = jsonldRaw.length > 0;
      for (const raw of jsonldRaw) {
        try {
          const obj = JSON.parse(raw);
          const arr = Array.isArray(obj) ? obj : [obj];
          for (const o of arr) {
            if (o?.["@type"] === "SoftwareApplication") hasSoftwareApp = true;
            if (o?.["@type"] === "Organization") hasOrg = true;
          }
        } catch { parseOk = false; }
      }
      const jsonldScore = (hasSoftwareApp ? 4 : 0) + (hasOrg ? 2 : 0) + (parseOk ? 2 : 0);
      record("jsonld", "JSON-LD SoftwareApp + Org parseable", 8, jsonldScore,
        `softwareApp=${hasSoftwareApp} org=${hasOrg} parseOk=${parseOk}`);

      /* 10. robots.txt valid & references sitemap */
      const rc = await pwRequest.newContext({ baseURL: baseURL! });
      const robotsResp = await rc.get("/robots.txt");
      const robotsText = robotsResp.ok() ? await robotsResp.text() : "";
      const hasSitemap = /Sitemap:/i.test(robotsText);
      const hasUserAgent = /User-Agent:/i.test(robotsText);
      const robotsScore = (robotsResp.ok() ? 2 : 0) + (hasSitemap ? 1 : 0) + (hasUserAgent ? 1 : 0);
      record("robots", "robots.txt 200 + Sitemap: + User-Agent:", 4, robotsScore,
        `status=${robotsResp.status()} sitemap=${hasSitemap} ua=${hasUserAgent}`);

      /* 11. sitemap.xml 200 + every URL 200 */
      const smResp = await rc.get("/sitemap.xml");
      let smUrls: string[] = [];
      if (smResp.ok()) {
        const text = await smResp.text();
        smUrls = Array.from(text.matchAll(/<loc>([^<]+)<\/loc>/g)).map((m) => m[1]!);
      }
      let smAllOk = smResp.ok() && smUrls.length > 0;
      const brokenSm: string[] = [];
      if (smAllOk) {
        for (const u of smUrls) {
          const p = u.replace(/^https?:\/\/[^/]+/, "");
          const r = await rc.get(p);
          if (!r.ok()) { smAllOk = false; brokenSm.push(`${p}=${r.status()}`); }
        }
      }
      const smScore = smResp.ok() ? Math.max(0, 6 - brokenSm.length) : 0;
      record("sitemap", "sitemap.xml 200 + all URLs 200", 6, smScore,
        `urls=${smUrls.length}${brokenSm.length ? " broken=" + brokenSm.slice(0, 3).join(",") : ""}`);

      /* 12. all img have meaningful alt */
      const imgs = await page.locator("img").evaluateAll((els) =>
        els.map((e) => ({
          alt: e.getAttribute("alt"),
          role: e.getAttribute("role"),
          src: e.getAttribute("src")?.slice(0, 60) || "",
        }))
      );
      const missingAlt = imgs.filter((i) => i.alt === null).length;
      const emptyAltNonDecor = imgs.filter((i) => i.alt === "" && i.role !== "presentation").length;
      const imgScore = imgs.length === 0
        ? 6
        : Math.max(0, 6 - missingAlt * 2 - emptyAltNonDecor);
      record("img-alt", "All <img> have meaningful alt", 6, imgScore,
        `imgs=${imgs.length} missing=${missingAlt} emptyNonDecor=${emptyAltNonDecor}`);

      /* 13. semantic landmarks main + nav + footer + section */
      const hasMain = (await page.locator("main").count()) >= 1;
      const hasNav = (await page.locator("nav").count()) >= 1;
      const hasFooter = (await page.locator("footer").count()) >= 1;
      const hasSection = (await page.locator("section, article").count()) >= 1;
      const semScore = (hasMain ? 2 : 0) + (hasNav ? 1 : 0) + (hasFooter ? 1 : 0) + (hasSection ? 1 : 0);
      record("semantics", "Semantic landmarks main/nav/footer/section", 5, semScore,
        `main=${hasMain} nav=${hasNav} footer=${hasFooter} section=${hasSection}`);

      /* 14. no broken internal links + anchors */
      const hrefs = await page.locator("a[href]").evaluateAll((els) =>
        els.map((e) => e.getAttribute("href")!).filter(Boolean)
      );
      const internalHrefs = Array.from(new Set(hrefs.filter((h) => h.startsWith("/") && !h.startsWith("//"))));
      const anchorHrefs = Array.from(new Set(hrefs.filter((h) => h.startsWith("#") && h.length > 1)));
      const brokenLinks: string[] = [];
      for (const h of internalHrefs) {
        const cleanPath = h.split("#")[0]!;
        if (!cleanPath) continue;
        const r = await rc.get(cleanPath);
        if (!r.ok()) brokenLinks.push(`${cleanPath}=${r.status()}`);
      }
      const brokenAnchors: string[] = [];
      for (const a of anchorHrefs) {
        const id = a.slice(1);
        const found = await page.locator(`[id="${id}"]`).count();
        if (found === 0) brokenAnchors.push(a);
      }
      const linkScore = Math.max(0, 6 - brokenLinks.length * 2 - brokenAnchors.length);
      record("links", "No broken internal links or dead anchors", 6, linkScore,
        `internal=${internalHrefs.length} anchors=${anchorHrefs.length} brokenLinks=${brokenLinks.length} brokenAnchors=${brokenAnchors.length}${brokenLinks.length ? " · " + brokenLinks.slice(0, 2).join(",") : ""}${brokenAnchors.length ? " · " + brokenAnchors.slice(0, 3).join(",") : ""}`);

      /* 15. LCP + viewport meta + no console errors */
      const viewport = await page.locator('meta[name="viewport"]').first().getAttribute("content");
      const hasViewport = !!viewport && /width=device-width/i.test(viewport);
      const lcp = await page.evaluate(
        () =>
          new Promise<number>((resolve) => {
            let v = 0;
            try {
              const po = new PerformanceObserver((list) => {
                const entries = list.getEntries();
                const last = entries[entries.length - 1] as PerformanceEntry & { startTime: number };
                if (last) v = last.startTime;
              });
              po.observe({ type: "largest-contentful-paint", buffered: true });
              setTimeout(() => { po.disconnect(); resolve(v); }, 3000);
            } catch { resolve(0); }
          })
      );
      const lcpOk = lcp === 0 || lcp < 2500;
      const noConsole = errs.length === 0;
      const perfScore = (hasViewport ? 3 : 0) + (lcpOk ? 3 : lcp < 4000 ? 1 : 0) + (noConsole ? 2 : 0);
      record("perf", "Viewport + LCP<2500ms + no console errors", 8, perfScore,
        `viewport=${hasViewport} lcp=${lcp.toFixed(0)}ms consoleErr=${errs.length}${errs.length ? " · " + errs[0]?.slice(0, 60) : ""}`);

      /* 16. no duplicate title / meta description */
      const titleCount = await page.locator("head title").count();
      const descCount = await page.locator('head meta[name="description"]').count();
      const dupScore = (titleCount === 1 ? 2 : 0) + (descCount === 1 ? 2 : 0);
      record("no-dup", "No duplicate <title> or meta description", 4, dupScore,
        `titles=${titleCount} descs=${descCount}`);

      /* 17. html lang matches locale */
      const htmlLang = await page.locator("html").first().getAttribute("lang");
      const explicitZh = await page.locator(`[lang="${expectHtmlLang}"]`).count();
      const langOk = htmlLang === expectHtmlLang || (locale === "zh" && explicitZh > 0);
      record("html-lang", `<html lang> matches ${expectHtmlLang}`, 4, langOk ? 4 : 1,
        `html.lang=${htmlLang} explicit[lang=${expectHtmlLang}]=${explicitZh}`);

      /* 18. favicon + apple-touch-icon + theme-color */
      const iconHref = await page.locator('link[rel="icon"]').first().getAttribute("href").catch(() => null);
      const apple = await page.locator('link[rel="apple-touch-icon"]').first().getAttribute("href").catch(() => null);
      const themeColor = await page.locator('meta[name="theme-color"]').first().getAttribute("content").catch(() => null);
      let faviconOk = false;
      if (iconHref) {
        const r = await rc.get(iconHref);
        faviconOk = r.ok();
      }
      if (!faviconOk) {
        const r = await rc.get("/favicon.ico");
        if (r.ok()) faviconOk = true;
      }
      let appleOk = false;
      if (apple) {
        const aResp = await rc.get(apple);
        appleOk = aResp.ok();
      }
      const iconScore = (faviconOk ? 2 : 0) + (appleOk ? 1 : 0) + (themeColor ? 1 : 0);
      record("icons", "icon + apple-touch-icon (200) + theme-color", 4, iconScore,
        `favicon=${faviconOk ? "ok" : (iconHref || "missing")} apple=${appleOk ? "ok" : apple || "missing"} themeColor=${themeColor || "missing"}`);

      await rc.dispose();
      audits.push({ locale, path, results });
    }

    /* Aggregate — average of both locales */
    const dimKeys = audits[0]!.results.map((r) => r.key);
    const perDim = dimKeys.map((key) => {
      const label = audits[0]!.results.find((r) => r.key === key)!.label;
      const max = audits[0]!.results.find((r) => r.key === key)!.max;
      const en = audits[0]!.results.find((r) => r.key === key)!;
      const zh = audits[1]!.results.find((r) => r.key === key)!;
      const earned = Math.round((en.earned + zh.earned) / 2);
      return { key, label, max, earned, en, zh };
    });

    const total = perDim.reduce((s, d) => s + d.earned, 0);
    const maxTotal = perDim.reduce((s, d) => s + d.max, 0);
    const pct = (total / maxTotal) * 100;

    const dir = join(process.cwd(), "e2e", "report");
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, "seo-score.json"),
      JSON.stringify({ total, maxTotal, percent: pct, perDim, audits }, null, 2));

    const md = [
      `# Solo Compass — SEO Score`,
      ``,
      `**${total} / ${maxTotal}** (${pct.toFixed(1)}%)  — avg of EN + ZH`,
      ``,
      `| # | Dimension | Max | EN | ZH | Avg |`,
      `|---|-----------|-----|-----|-----|-----|`,
      ...perDim.map((d, i) =>
        `| ${i + 1} | ${d.label} | ${d.max} | ${d.en.earned} | ${d.zh.earned} | ${d.earned} |`
      ),
      ``,
      `## Losing dimensions`,
      ``,
      ...perDim.filter((d) => d.earned < d.max).flatMap((d) => [
        `### ${d.label} — ${d.earned}/${d.max}`,
        `- EN: ${d.en.note}`,
        `- ZH: ${d.zh.note}`,
        ``,
      ]),
    ].join("\n");
    writeFileSync(join(dir, "seo-score.md"), md);
    console.log("\n" + md + "\n");
    console.log(`SEO_SCORE=${total}/${maxTotal} (${pct.toFixed(1)}%)\n`);

    expect(total, `SEO score should be perfect: ${total}/${maxTotal}\n${md}`).toBe(maxTotal);
  });
});
