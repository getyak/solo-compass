# SEO Strategy

> Solo Compass · 搜索引擎获客战略
>
> Status: v1 — 2026-07-02。任何 URL 结构、meta 模板、内容页模板变动前来这里对齐。
>
> Sibling docs: `WEB_DESIGN.md`（Scenario D 是本文档的战术底座）· `GO_TO_MARKET.md`（漏斗）· `WEB_LANDING_DESIGN.md`（视觉）

---

## 1. SEO 目标的诚实定义

Solo Compass 的 SEO 不追求"抢流量"，追求"抢定位"。

**成功定义（12 个月）**:

- 搜索 `"solo travel app"` (US) → 官网出现在 App Store 结果之下的第一屏
- 搜索 `"独自旅行 app"` (CN) → 小红书 / 知乎结果之上出现
- 搜索 `"quiet café Chiang Mai"` / `"清迈 独自 咖啡"` → 我们的城市 + 体验页出现在第一页
- Google 品牌搜索 `"Solo Compass"` 月均 500+ 次

**不追求什么**:

- 不追求 general travel keyword（`"travel to Chiang Mai"` — 竞争红海）
- 不追求 hotel/flight booking keyword — 我们不做这个业务
- 不追求 SEO-driven 的"内容工厂"式站群 — 每篇内容都要有立场

---

## 2. 关键词矩阵（英文）

四类意图分层，每类对应一种页面模板。

### Tier 1 · Brand（首页 + 定价页承接）

| Keyword                            | Monthly Volume (est) | Intent | Target Page      |
| ---------------------------------- | -------------------- | ------ | ---------------- |
| solo compass app                   | -                    | Brand  | `/`              |
| solo compass ios                   | -                    | Brand  | `/`              |
| solo compass pricing               | -                    | Brand  | `/pricing`       |

### Tier 2 · Category（Hero + Features 承接）

| Keyword                            | Vol   | Difficulty | Target Page                    |
| ---------------------------------- | ----- | ---------- | ------------------------------ |
| solo travel app                    | 2,900 | 42         | `/`                            |
| best app for traveling alone       | 720   | 35         | `/`                            |
| solo travel companion              | 480   | 30         | `/`                            |
| solo travel ios app                | 210   | 25         | `/features/ios`                |
| offline solo travel app            | 170   | 22         | `/features/privacy-offline`    |
| privacy-focused travel app         | 210   | 28         | `/features/privacy-offline`    |
| ai travel assistant no ads         | 90    | 20         | `/features/ai-transparency`    |

### Tier 3 · Comparative（Blog 长文承接）

| Keyword                            | Vol   | Diff | Target Page                                |
| ---------------------------------- | ----- | ---- | ------------------------------------------ |
| solo compass vs google maps        | -     | 15   | `/blog/solo-compass-vs-google-maps`        |
| solo compass vs tripadvisor        | -     | 15   | `/blog/solo-compass-vs-tripadvisor`        |
| best alternative to lonely planet  | 320   | 30   | `/blog/lonely-planet-alternatives`         |
| chatgpt travel planner limitations | 140   | 20   | `/blog/why-chatgpt-fails-solo-travelers`   |

### Tier 4 · Long-tail Experience（城市/体验页承接 — SEO 主战场）

模板 `/city/[city-slug]` + `/city/[city-slug]/[experience-slug]`：

| Pattern                              | Example Volume  |
| ------------------------------------ | --------------- |
| quiet café [city]                    | 90-500/city     |
| what to do alone in [city]           | 320-2400/city   |
| best solo travel spots [city]        | 40-320/city     |
| [attraction] sunset time             | 90-700/attraction|
| solo dining [city] no reservation    | 20-200/city     |

**这一层是 SEO 的护城河**。5 个种子城市 (Chiang Mai / Lisbon / Tokyo / Kyoto / Bali) × 平均 50 个 experience/city = 250 个静态页面。每个页面精心 seed 内容，配合 Wikivoyage attribution + 出站信号（AI 会推理"这个站尊重信息来源"）。

---

## 3. 关键词矩阵（中文）

中文搜索生态与英文完全不同：Google 权重 30%，剩下是百度/必应/微信搜一搜/小红书搜索。策略调整：

### Tier 1 · 品牌

| 关键词          | Vol   | Target                     |
| --------------- | ----- | -------------------------- |
| solo compass    | -     | `/zh`                      |
| 独行罗盘 app    | -     | `/zh`                      |

### Tier 2 · 品类

| 关键词                | Vol       | 承接页                                 |
| --------------------- | --------- | -------------------------------------- |
| 独自旅行 app          | 1200      | `/zh`                                  |
| 一个人旅行 app        | 800       | `/zh`                                  |
| 一个人 旅游 推荐 app  | 320       | `/zh`                                  |
| 无广告 旅行 app       | 260       | `/zh/features/privacy-offline`         |
| 隐私 旅行 app         | 90        | `/zh/features/privacy-offline`         |
| ai 旅行规划 app       | 480       | `/zh/features/ai-transparency`         |

### Tier 3 · 对比

| 关键词                       | Vol  | 承接页                                       |
| ---------------------------- | ---- | -------------------------------------------- |
| 小红书 旅行 替代              | 210  | `/zh/blog/xiaohongshu-vs-solo-compass`       |
| chatgpt 旅行 局限              | 90   | `/zh/blog/why-chatgpt-fails-solo-travelers`  |
| 高德 独自 旅行 局限            | 40   | `/zh/blog/gaode-vs-solo-compass`             |

### Tier 4 · 长尾体验（中国用户的独行目的地）

| 模板                    | 示例                                             |
| ----------------------- | ------------------------------------------------ |
| 独自 咖啡 [城市]         | 独自 咖啡 大理                                    |
| 一个人 [城市] 攻略        | 一个人 松阳 攻略                                  |
| [城市] 独行 安静地方      | 苏州 独行 安静地方                                |
| [景点] 最佳 时间          | 洱海 最佳 拍照时间                                |

**中文 Tier 4 的独特性**：中文用户经常在"小红书搜"而不是"Google 搜"。所以 URL 结构要 shareable to 小红书（短、有 emoji 兼容、复制到小红书 caption 里不掉格式）。

**冷启动种子**：北京 / 上海 / 大理 / 松阳 / 京都（华人游客热门）× 30 experience/city = 150 个中文静态页。

---

## 4. URL 结构（IA 直接绑定）

严格纪律，一次锁死：

```
/                                     Homepage EN
/zh                                   Homepage CN
/features/[slug]                      Feature deep dive EN
/zh/features/[slug]                   Feature deep dive CN
/pricing                              Pricing EN
/zh/pricing                           Pricing CN
/city/[city]                          City guide EN (Chiang Mai, Lisbon...)
/zh/city/[city]                       City guide CN (北京, 大理...)
/city/[city]/[experience]             Experience detail EN
/zh/city/[city]/[experience]          Experience detail CN
/blog                                 Blog index EN
/zh/blog                              Blog index CN
/blog/[slug]                          Blog post EN
/zh/blog/[slug]                       Blog post CN
/download                             Get on App Store (bilingual redirector)
/privacy                              Privacy policy EN (SEO signal)
/zh/privacy                           Privacy policy CN
/manifesto                            "为什么我们做这个" — 独立开发者叙事
/zh/manifesto
```

### slug 规则

- 城市 slug: 拉丁字母，全小写，破折号连接。`chiang-mai`、`tokyo`、`beijing`（**注意**：中文城市也用拼音 slug，不用 URL encode 中文字符——利于分享）
- 体验 slug: 5-8 词 kebab-case，含关键动词。`sunset-at-wat-suan-dok` > `wat-suan-dok`。
- Blog slug: 与关键词矩阵完全对齐。`why-chatgpt-fails-solo-travelers` > `chatgpt-limitations`。

### hreflang（多语言 SEO 生死线）

每个页面的 `<head>` 里输出：

```html
<link rel="alternate" hreflang="en" href="https://solocompass.app/city/chiang-mai" />
<link rel="alternate" hreflang="zh-CN" href="https://solocompass.app/zh/city/chiang-mai" />
<link rel="alternate" hreflang="x-default" href="https://solocompass.app/city/chiang-mai" />
```

**共同错误规避**：`x-default` 必须指英文，不能省略；`hreflang="zh"` 而不是 `hreflang="zh-CN"` 会被 Google 判无效（对中文区域必须显式）。

---

## 5. 结构化数据（Schema.org）

Google Rich Result 的入场券。三类页面三种 schema：

### Homepage & Pricing → `SoftwareApplication`

```json
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "Solo Compass",
  "operatingSystem": "iOS 17.0+",
  "applicationCategory": "TravelApplication",
  "offers": [
    { "@type": "Offer", "price": "0", "priceCurrency": "USD", "description": "Free" },
    { "@type": "Offer", "price": "29", "priceCurrency": "USD", "description": "Lifetime" },
    { "@type": "Offer", "price": "50", "priceCurrency": "USD", "description": "Yearly" }
  ],
  "aggregateRating": {
    "@type": "AggregateRating",
    "ratingValue": "4.8",
    "reviewCount": "127"
  }
}
```

（发布前必须有真实评价数据；虚构 aggregateRating 会被 Google 降权）

### City page → `TouristDestination`

```json
{
  "@context": "https://schema.org",
  "@type": "TouristDestination",
  "name": "Chiang Mai for Solo Travelers",
  "description": "50 hand-picked experiences...",
  "geo": { "@type": "GeoCoordinates", "latitude": 18.7883, "longitude": 98.9853 },
  "includesAttraction": [/* 每个体验的 TouristAttraction 引用 */]
}
```

### Experience page → `TouristAttraction` + `LocalBusiness`（if café / bar）

```json
{
  "@context": "https://schema.org",
  "@type": ["TouristAttraction", "CafeOrCoffeeShop"],
  "name": "Ristr8to Coffee",
  "address": { "@type": "PostalAddress", "streetAddress": "..." },
  "openingHours": "Mo-Su 07:00-18:00",
  "priceRange": "฿฿"
}
```

### Blog → `Article` + `BreadcrumbList`

标配。用 Next.js `generateMetadata` 自动生成。

---

## 6. 技术 SEO 清单

### 首发必做（launch blocker）

- [ ] Next.js `sitemap.ts` 输出 `/sitemap.xml`，含所有静态路径 + 城市 + 体验
- [ ] Next.js `robots.ts` 输出 `/robots.txt`，`Allow: /`, `Sitemap: https://solocompass.app/sitemap.xml`
- [ ] `<link rel="canonical">` 每页
- [ ] hreflang 全部就绪
- [ ] OpenGraph + Twitter Card `next/og` 动态生成
- [ ] Schema.org JSON-LD 每类页面就位
- [ ] Google Search Console + Bing Webmaster + 百度站长 提交 sitemap
- [ ] Cloudflare（Vercel）不 block 中国爬虫

### 性能 SEO（Core Web Vitals）

Lighthouse 目标：Performance ≥ 95, Accessibility ≥ 95, SEO 100, Best Practices ≥ 95。

**四条红线**:

1. **LCP < 2.0s**：Hero 图 preload，用 `next/image` + AVIF fallback
2. **CLS < 0.05**：所有 image 都写死 width/height，字体用 `next/font` swap 策略
3. **INP < 200ms**：Server Component 优先，客户端 JS < 100KB gzipped
4. **TTFB < 800ms**：Vercel Edge + ISR，重要页面 revalidate 1h

### 首发后 30 天检查项

- [ ] Search Console 覆盖率 > 90%（提交 vs 已收录）
- [ ] Coverage 报错 = 0
- [ ] Core Web Vitals field data 都在"良好"
- [ ] Google Analytics 4 event tracking 就绪（下载 CTA / 定价页浏览 / hreflang 切换）
- [ ] Ahrefs / SEMrush 首个 backlink 分析

---

## 7. 内容日历（前 6 个月）

不是"每周一篇 SEO 文章"，是**每篇内容有真实价值**。

### Month 1 · 5 篇（品牌与立场）

1. `/manifesto` — Why we built Solo Compass（独立开发者叙事，独立域名的护城河）
2. `/blog/why-chatgpt-fails-solo-travelers` — Tier 3 高流量 + 立场
3. `/blog/solo-compass-vs-google-maps` — Tier 3，直接对位
4. `/blog/the-honest-confidence-signal` — Trust 深度技术叙事（fresh/verified/degraded 机制）
5. `/blog/we-dont-do-recommendations` — 反 anti-goal 声明

### Month 2-3 · 城市种子 × 5

Chiang Mai / Lisbon / Tokyo / Kyoto / Bali 全部上线，每城 30-50 个体验静态页。

### Month 4-5 · 长尾 blog × 8

按 Tier 4 关键词矩阵批量做：`quiet-cafes-chiang-mai`, `solo-dining-tokyo`, `budget-solo-lisbon`, etc.

### Month 6+ · 中文全面铺开

北京 / 大理 / 松阳 / 京都 / 苏州 × 30 experience/city。

---

## 8. 外链战略（Off-page SEO）

不做黑帽 backlink。三条正道：

1. **Product Hunt / IndieHackers / MakerLog** — 首发即上，Hunter 用真人独立开发者，不刷票
2. **Reddit `/r/solotravel`, `/r/digitalnomad`, `/r/onebag`** — 真实分享自己造这个 App 的故事（用户 flair 保持诚意），不群发链接
3. **HackerNews Show HN** — 首发选周三 UTC 09:00 发，标题 `Show HN: Solo Compass – A map-first companion for people who travel alone`

中文外链：

1. **V2EX 独立项目板** — 独立开发者叙事
2. **知乎「独自旅行」话题** — 长篇技术+设计思路分享（专栏文章）
3. **少数派** — 完整评测 + 产品哲学文章（付费栏目也可以）

**避坑**：小红书是内容平台，不是外链平台，其外链几乎无 SEO 价值。小红书用来做转化直接引流到 App Store，不指望 SEO。

---

## 9. 内容运营纪律

- 每篇 blog **必须**由独立开发者本人写第一稿（不用 AI 从头生成）
- AI 只用来做：翻译校对、SEO meta 优化、内链推荐
- 每篇文章包含至少 1 个"反直觉观点"（比如"为什么 solo travel 不该看小红书"）
- 每篇文章末尾要有明确的"下一步"：进 App Store，或者读另一篇有关联的内容
- 每篇文章的 hero 图不用 stock photo；用 App 内截图或独立开发者本人拍的照片

---

## 10. 一句话总结

> **SEO 不是流量游戏，是"让搜索 solo travel 的人找到我们"的游戏。** 我们只需要 5% 的人转化，不需要 100% 的人流量。

任何 SEO 提案与这句话冲突，重新审视。
