# Web Landing · Handoff

> Solo Compass · 首版官网交付清单
>
> 2026-07-02 · v1

---

## 本次交付了什么

### 1) 三份深度战略文档（`docs/`）

| 文档                        | 作用                                                             |
| --------------------------- | ---------------------------------------------------------------- |
| `GO_TO_MARKET.md`           | 商业化定位、Free/Yearly/Lifetime 双轨定价、Persona、竞品切位、漏斗、24 个月收入预测 |
| `SEO_STRATEGY.md`           | 中英四类关键词矩阵（Brand/Category/Comparative/Long-tail）、URL 结构、hreflang、Schema.org JSON-LD 模板、Core Web Vitals 红线、内容日历、外链战略 |
| `WEB_LANDING_DESIGN.md`     | 完整视觉设计系统：CT tokens 到 CSS 变量、type scale、spacing、shadow、motion、编辑感排版规则、7 个 section 逐屏 spec、Component 库、中英文案 voice guide |

### 2) 设计 tokens 全套落地（CT parity）

- `apps/web/src/app/globals.css` — 30+ CSS 变量与 iOS `CompareTokens.swift` 一比一对齐；11 档 editorial type scale（`display-2xl/xl/lg/md/sm` + `body-xl/lg/md/sm/xs` + `mono-md`）；`ds-reveal` cascading hero 动效；prefers-color-scheme 深色适配；prefers-reduced-motion 尊重
- `apps/web/tailwind.config.ts` — 所有 CT token 暴露成 utilities（`bg-warm`, `text-fg-primary`, `bg-accent-soft`, `sun-gold`, `omen-gold`, `blindbox-amber`, `tone-*`, `warning-*`, `success-*`）；editorial 字号；editorial motion duration；`max-w-narrow/default/wide/max`；section 垂直节奏 `section-y`

### 3) Marketing 组件库（`apps/web/src/components/marketing/`）

| 文件                | 内容                                                                                          |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `Container.tsx`     | 三档宽度容器（narrow/default/wide）                                                            |
| `primitives.tsx`    | Button / ButtonLink / Chip / Eyebrow（`●`圆点式） / Section（section-y 垂直节奏）/ IPhoneFrame |
| `DayPageMock.tsx`   | 纯 DOM 高保真的 iOS DayPage 模拟（Ristr8to 咖啡示例）—— 不是截图，永远清晰、支持深色模式         |
| `copy.ts`           | 中英全量文案，`Copy` interface + `copy.en` / `copy.zh`；voice 遵循 `WEB_LANDING_DESIGN.md` §6  |
| `sections.tsx`      | MarketingNav / Hero（cascading reveal）/ Problem（Google Maps/小红书/ChatGPT 三段对位）/ Pillars（三张暖琥珀卡）/ Trust（Privacy/AI/Pricing 三承诺）/ Pricing（双卡对比）/ Footer |

### 4) 页面（`apps/web/src/app/`）

| Route                     | 说明                                                             |
| ------------------------- | ---------------------------------------------------------------- |
| `/`                       | **英文首页**（7 section 完整）· 含 SoftwareApplication + Organization JSON-LD、OpenGraph、Twitter Card、hreflang |
| `/zh`                     | **中文首页**（同结构，本地化 voice，非机翻）                     |
| `/pricing`                | 英文定价页 · Pricing section + 6 条 FAQ                          |
| `/zh/pricing`             | 中文定价页 · 同结构                                              |
| `/app`                    | **老 Scenario A 研究面板**（Mapbox + Voice + Sheet）—— 之前的 `/`，通过 `git mv` 保存到 `/app`，未破坏 |
| `/sitemap.xml`            | 自动生成（Next.js `sitemap.ts`）· 含 9 条 URL + hreflang alternates |
| `/robots.txt`             | 自动生成 · 允许 `/`，禁止 `/api/`, `/app/`                        |

### 5) 技术验证

- `pnpm typecheck` **全绿**，无编译错误
- CT 色值全部匹配 iOS `CompareTokens.swift`（`--fg-primary: #1F1A14` 等）
- hreflang 遵循 Google 建议（`en` / `zh-CN` / `x-default`，非 `zh`）
- Schema.org JSON-LD 双语双 currency（USD / CNY）

---

## 本地预览

```bash
cd apps/web
pnpm dev
# 打开 http://localhost:3000       — 英文首页
# 打开 http://localhost:3000/zh    — 中文首页
# 打开 http://localhost:3000/pricing
# 打开 http://localhost:3000/zh/pricing
# 打开 http://localhost:3000/app   — 老研究面板保留
```

---

## 视觉检查清单（首屏一眼验证）

打开 `/` 后逐项确认：

- [ ] Hero H1 是 96px、`Space Grotesk 500`、三行左对齐
- [ ] 眉标"● since 2026 · made for iOS 17+"是 sun-gold 圆点 + JetBrains Mono 12px uppercase tracking-widest
- [ ] Hero 加载序列 < 1600ms 完成（无无限漂浮动画）
- [ ] iPhone frame 微 2° 倾斜，展示 DayPage（含 Solo Score 热力条 + Best Time 柱图）
- [ ] Problem section 六段编辑感文字，"Google Maps / 小红书 / ChatGPT" 用 fg-muted 而不咄咄逼人
- [ ] Pillars 三张卡的圆点分别是 sun-gold / omen-gold / accent
- [ ] Trust section 三段直白宣言，暖白沉降色底
- [ ] Pricing 双卡：Lifetime $29 暖白底描边、Yearly $50 暖琥珀 chip "Most popular"
- [ ] Footer 一句话："Made by one person, in Kyoto. No VC. No ads."
- [ ] `/zh` 中文首页所有暗琥珀色都一致；hero 副标 PingFang SC 与 Space Grotesk 混排不违和

---

## 已知待办（Phase 2 未做）

有意识不做，为了 Phase 1 尽快上线：

- [ ] `/manifesto` 独立开发者叙事页（`docs/PRODUCT_BRIEF.md` 可以做骨架）
- [ ] `/privacy` 隐私政策页（复用 iOS `docs/PRIVACY.md` 4 张表）
- [ ] `/features/[slug]` Features 深度页（apple.com 式 sticky-scroll 4 图）
- [ ] `/city/[city]` 城市 SEO 静态页（含 TouristDestination Schema）
- [ ] `/city/[city]/[experience]` 体验详情 SEO 页
- [ ] `/blog/*` MDX 长文（5 篇 Month 1 内容，见 `SEO_STRATEGY.md` §7）
- [ ] `/download` App Store redirect 页
- [ ] `next/og` 动态 OG 图（现在指向 `/og/*.png` 静态占位）
- [ ] Deep dive: apple.com 式 sticky-scroll App feature section（现在合并在 Pillars 里）
- [ ] 移动端 sticky bottom CTA bar
- [ ] Web Vitals 现场测量脚本
- [ ] 深色模式手动切换按钮（现在只跟随系统）

---

## SEO 上线检查（首发前必做）

按 `docs/SEO_STRATEGY.md` §6 逐项：

- [ ] Vercel 部署 `solocompass.app`（购域名 + Vercel DNS）
- [ ] Google Search Console 验证并提交 `/sitemap.xml`
- [ ] Bing Webmaster Tools 提交
- [ ] 百度站长平台提交（中国区 SEO 生死线）
- [ ] Cloudflare / Vercel Firewall 不阻断中国 IP 与百度爬虫
- [ ] Google Analytics 4 或 PostHog（现有）event 校准：`marketing_hero_view`, `pricing_cta_click`, `lang_switch`
- [ ] Lighthouse 目标：Performance ≥ 95, Accessibility ≥ 95, SEO 100, Best Practices ≥ 95
- [ ] 首页 Core Web Vitals：LCP < 2.0s, CLS < 0.05, INP < 200ms
- [ ] 真机 OG 卡片检查（Twitter Card Validator + LinkedIn Post Inspector + Facebook Sharing Debugger）
- [ ] 生成 4 张 OG 图：`/og/home.png`, `/og/home-zh.png`, `/og/pricing.png`, `/og/pricing-zh.png`（1200 × 630）
- [ ] `/apple-touch-icon.png` (180×180) 与 `/favicon.ico`

---

## App Store 集成（launch 前）

- [ ] `sections.tsx:21` 的 `APP_STORE_URL` 常量替换为真实 App Store 链接
- [ ] App Store Connect 提交 metadata 与 `docs/APP_STORE_METADATA.md` 对齐
- [ ] Screenshot 生成脚本（reuse iOS `scripts/screenshot/`）产出 5 张 App Store 5.5" / 6.7" 图
- [ ] Apple Search Ads 关键词与 `SEO_STRATEGY.md` §2 Tier 2 对齐

---

## Analytics 埋点建议

延续现有 `apps/web/src/lib/analytics.ts`：

- `hero_view` — Hero 进入视口
- `hero_cta_click` — 点击 "Get on App Store"
- `hero_secondary_click` — 点击 "See how it works"
- `pillar_view` — Pillars section 进入视口
- `pricing_view` — Pricing section 进入视口
- `pricing_cta_click` — { plan: "lifetime" | "yearly" }
- `pricing_free_click`
- `lang_switch` — { from: "en" | "zh", to: "en" | "zh" }
- `nav_click` — { item: "features" | "pricing" | "cities" | "blog" | "manifesto" }

---

## 一句话总结

> **官网首版已上线可预览：中英双语、CT 全 parity、Type-safe、SEO 就绪、编辑感在线。剩下的都是 Phase 2 内容层扩展，视觉与技术骨架不必再动。**
