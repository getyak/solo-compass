import { test, expect } from "@playwright/test";
import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/**
 * Landing-quality E2E scoring rubric — 12 dimensions, total 100.
 * Writes score card to e2e/report/score.{json,md}.
 * Config: ../playwright.config.ts (testDir: "./e2e").
 */

interface Result {
  key: string;
  label: string;
  max: number;
  earned: number;
  note: string;
}

const results: Result[] = [];
const record = (key: string, label: string, max: number, earned: number, note: string) => {
  results.push({ key, label, max, earned, note });
};

test.describe("Solo Compass landing — quality rubric", () => {
  test("all dimensions", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });

    /* 1. Homepage 200 */
    const homeResp = await page.goto("/", { waitUntil: "domcontentloaded" });
    const homeOk = homeResp?.status() === 200;
    record("home-200", "Homepage returns 200", 6, homeOk ? 6 : 0,
      `status: ${homeResp?.status()}`);

    /* 2. Hero H1 */
    const h1 = await page.locator("main h1").first().textContent();
    const h1Ok = !!h1 && h1.trim().length > 8;
    record("hero-h1", "Hero H1 present & non-trivial", 8, h1Ok ? 8 : 0,
      `h1: ${JSON.stringify(h1?.slice(0, 60))}`);

    /* 3. Six capabilities */
    const caps = await page.locator("article[data-capability]").all();
    const capKinds = (await Promise.all(caps.map((c) => c.getAttribute("data-capability")))).filter(Boolean) as string[];
    const expected = ["askSolo", "blindbox", "capsule", "omen", "bestNow", "brag"];
    const allPresent = expected.every((k) => capKinds.includes(k));
    const capScore = allPresent ? 12 : Math.round((capKinds.length / 6) * 12);
    record("six-caps", "All 6 capability sections rendered", 12, capScore,
      `found ${capKinds.length}/6: ${capKinds.join(", ")}`);

    /* 4. Mock frames */
    let mockCount = 0;
    for (const kind of expected) {
      const inner = page.locator(`article[data-capability="${kind}"] div.rounded-\\[48px\\]`);
      const has = (await inner.count()) > 0;
      if (has) mockCount += 1;
    }
    const mockScore = Math.round((mockCount / 6) * 12);
    record("caps-mocks", "Each capability renders an iPhone mock", 12, mockScore,
      `${mockCount}/6 iPhone frames present`);

    /* 5. Multiple H2 sections */
    const h2Count = await page.locator("main h2").count();
    const h2Ok = h2Count >= 4;
    const h2Score = h2Ok ? 6 : Math.min(h2Count, 6);
    record("h2-sections", "≥4 H2 sections (Pillars/Caps/Trust/Pricing)", 6, h2Score,
      `h2 count: ${h2Count}`);

    /* 6. Pricing */
    const priceText = await page.locator("main").innerText();
    const has29 = priceText.includes("$29");
    const has50 = priceText.includes("$50");
    const pricingScore = (has29 ? 4 : 0) + (has50 ? 4 : 0);
    record("pricing", "Both price points rendered ($29 & $50)", 8, pricingScore,
      `$29: ${has29}, $50: ${has50}`);

    /* 7. hreflang */
    const alternates = await page.locator('link[rel="alternate"]').evaluateAll((els) =>
      els.map((e) => ({
        hreflang: e.getAttribute("hreflang"),
        href: e.getAttribute("href"),
      }))
    );
    const hasEn = alternates.some((a) => a.hreflang === "en");
    const hasZh = alternates.some((a) => a.hreflang === "zh-CN");
    const hreflangScore = (hasEn ? 3 : 0) + (hasZh ? 3 : 0);
    record("hreflang", "hreflang en + zh-CN present", 6, hreflangScore,
      `en: ${hasEn}, zh-CN: ${hasZh}`);

    /* 8. JSON-LD */
    const jsonld = await page.locator('script[type="application/ld+json"]').allTextContents();
    const combined = jsonld.join("\n");
    const hasSoftwareApp = /SoftwareApplication/.test(combined);
    const hasOrg = /"@type"\s*:\s*"Organization"/.test(combined);
    const jsonldScore = (hasSoftwareApp ? 5 : 0) + (hasOrg ? 3 : 0);
    record("jsonld", "JSON-LD SoftwareApplication + Organization", 8, jsonldScore,
      `SoftwareApp: ${hasSoftwareApp}, Org: ${hasOrg}`);

    /* 9. img alt */
    const imgs = await page.locator("img").evaluateAll((els) =>
      els.map((e) => ({ alt: e.getAttribute("alt") }))
    );
    const missingAlt = imgs.filter((i) => i.alt === null || i.alt === "").length;
    const imgScore = imgs.length === 0 || missingAlt === 0 ? 6 : Math.max(0, 6 - missingAlt * 2);
    record("img-alt", "All <img> have alt", 6, imgScore,
      `${imgs.length} imgs, ${missingAlt} missing alt`);

    /* 10. Console errors */
    await page.waitForTimeout(1200);
    const consoleScore = consoleErrors.length === 0 ? 8 : Math.max(0, 8 - consoleErrors.length * 2);
    record("console", "No console errors", 8, consoleScore,
      `errors: ${consoleErrors.length}${consoleErrors.length ? " · " + consoleErrors[0]?.slice(0, 80) : ""}`);

    /* 11. CN page */
    const zhResp = await page.goto("/zh", { waitUntil: "domcontentloaded" });
    const zhOk = zhResp?.status() === 200;
    const zhText = zhOk ? await page.locator("main").innerText() : "";
    const hasRawKey = /\bcopy\.zh\.|\bnav\.\w+\}|\{\{|undefined/.test(zhText);
    const hasHan = /[一-鿿]/.test(zhText);
    const zhScore = (zhOk ? 3 : 0) + (!hasRawKey ? 3 : 0) + (hasHan ? 2 : 0);
    record("zh", "CN page 200 + real i18n + Chinese chars", 8, zhScore,
      `status: ${zhResp?.status()}, rawKey: ${hasRawKey}, hasHan: ${hasHan}`);

    /* 12. LCP */
    await page.goto("/", { waitUntil: "domcontentloaded" });
    const lcp = await page.evaluate(
      () =>
        new Promise<number>((resolve) => {
          let lcpValue = 0;
          try {
            const po = new PerformanceObserver((list) => {
              const entries = list.getEntries();
              const last = entries[entries.length - 1] as PerformanceEntry & { startTime: number };
              if (last) lcpValue = last.startTime;
            });
            po.observe({ type: "largest-contentful-paint", buffered: true });
            setTimeout(() => {
              po.disconnect();
              resolve(lcpValue);
            }, 3500);
          } catch {
            resolve(0);
          }
        })
    );
    const lcpScore = lcp === 0 ? 6 : lcp < 1500 ? 12 : lcp < 2500 ? 10 : lcp < 4000 ? 6 : 2;
    record("lcp", "LCP < 2500ms", 12, lcpScore, `LCP: ${lcp.toFixed(0)}ms`);

    /* Aggregate */
    const total = results.reduce((s, r) => s + r.earned, 0);
    const maxTotal = results.reduce((s, r) => s + r.max, 0);
    const pct = (total / maxTotal) * 100;

    const dir = join(process.cwd(), "e2e", "report");
    mkdirSync(dir, { recursive: true });
    writeFileSync(
      join(dir, "score.json"),
      JSON.stringify({ total, maxTotal, percent: pct, results }, null, 2)
    );
    const md = [
      `# Solo Compass — Landing Score`,
      ``,
      `**${total} / ${maxTotal}** (${pct.toFixed(1)}%)`,
      ``,
      `| # | Dimension | Score | Note |`,
      `|---|-----------|-------|------|`,
      ...results.map((r, i) => `| ${i + 1} | ${r.label} | ${r.earned}/${r.max} | ${r.note} |`),
    ].join("\n");
    writeFileSync(join(dir, "score.md"), md);
    console.log("\n" + md + "\n");
    console.log(`SCORE=${total}/${maxTotal} (${pct.toFixed(1)}%)\n`);

    expect(total, `Landing score should be perfect: ${total}/${maxTotal}\n${md}`).toBe(maxTotal);
  });
});
