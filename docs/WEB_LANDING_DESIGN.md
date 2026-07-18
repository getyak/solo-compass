# Web Landing · Deep Design Doc

> Solo Compass · 官网视觉与文案系统 · 满分向
>
> Status: v1 — 2026-07-02。任何 marketing 页面 PR 前来这里对齐。
>
> Sibling docs: `WEB_DESIGN.md`（场景边界，Scenario A/B/C/D）· `GO_TO_MARKET.md`（漏斗）· `SEO_STRATEGY.md`（IA 与关键词）· iOS `Views/Shared/CompareTokens.swift`（色值 SoT）

---

## 0. 设计哲学（一句话）

> **官网是 App 内 DayPage 的自然延伸，不是"营销页"。用户从 Web 到 iOS，视觉体感一致——这是品牌壁垒。**

三条纪律：

1. **不模仿别人。** 不做 Vercel 风、不做 Linear 风、不做 Framer 模板风。做 **Solo Compass 风**。
2. **编辑感，不 SaaS 感。** 参照 Field Mag、Craft、Are.na、Kinfolk Magazine，不参照 SaaS 官网。
3. **每一屏都能截屏当 blog 封面。** 视觉质量 = 内容质量，不允许"占位"式的通用感 hero。

---

## 1. Design Tokens（从 iOS 提取，锁死）

### 1.1 Color System

**核心原则**：所有色值直接对应 `CompareTokens.swift`，命名 kebab-case 化。前端 CSS variable 完全平移。

```css
/* --- Warm Amber Base (== CT.bg* + CT.fg* + CT.surface*) --- */
--bg-warm: #faf8f6; /* 页面底色 - 暖白 */
--surface-white: #ffffff; /* 卡片/表单底色 */
--surface-sunken: #f3eee6; /* 表单沉降/引用块 */

--fg-primary: #1f1a14; /* 正文近黑 */
--fg-muted: #6d6358; /* 二级文本 */
--fg-subtle: #a39a8c; /* 三级、时间戳、caption */

--border-subtle: #ede8df; /* 极细分隔 */
--border-default: #d6cec0; /* 卡片描边 */

/* --- Accent (== CT.accent*) - 深咖 CTA 主色 --- */
--accent: #5d3000; /* 主按钮、link、focus ring */
--accent-hover: #4a2600; /* hover 加深 */
--accent-soft: #fbf1e4; /* 背景高亮、chip fill */
--accent-border: #e8dcca; /* accent 环境的描边 */

/* --- Sun-Gold (== CT.sunGold*) - "此刻"金色 --- */
--sun-gold: #c9a677;
--sun-gold-deep: #a07f4b;
--sun-gold-soft: #f5e9d2;

/* --- Scene tokens (== CT.capsuleGlow/omenGold/blindboxAmber) --- */
--capsule-glow: #f7deb0; /* Ritual 相关 UI */
--omen-gold: #b8925c;
--blindbox-amber: #8a4a14;

/* --- Semantic (== CT.tone*) --- */
--tone-open: #5d3000;
--tone-forming: #b57420;
--tone-closed: #1f7b4d;
--tone-completed: #6d6358;

/* --- Warning / Success --- */
--warning-soft: #fbf2e3;
--warning-text: #b57420;
--success-soft: rgba(47, 164, 106, 0.12);
--success-text: #1f7b4d;

/* --- Dark mode (== CT.warm*Dark) --- */
--dark-sheet: #171410;
--dark-card: #231f19;
--dark-sunken: #2c2720;
--dark-border: #3a3329;
--dark-fg-primary: #f4efe7;
--dark-fg-muted: #b0a697;
```

### 1.2 Typography Scale

**字体家族**：

```
Display  → "Space Grotesk", ui-sans-serif, system-ui
Body     → "Inter", ui-sans-serif, system-ui, -apple-system
Mono     → "JetBrains Mono", ui-monospace, "SF Mono"
Serif    → "Fraunces", ui-serif, Georgia   ← 编辑感 pull-quote 专用
```

**Type Scale**（modular scale 1.25）：

| Token         | Size | Line | Weight | Use                                   |
| ------------- | ---- | ---- | ------ | ------------------------------------- |
| `display-2xl` | 96px | 1.02 | 500    | Hero H1 (仅 hero)                     |
| `display-xl`  | 72px | 1.05 | 500    | 大标题                                |
| `display-lg`  | 56px | 1.08 | 500    | 分区标题 (section header)             |
| `display-md`  | 40px | 1.15 | 500    | 卡片标题、blog h2                     |
| `display-sm`  | 32px | 1.2  | 500    | h3                                    |
| `body-xl`     | 22px | 1.55 | 400    | Hero 副标题、pull-quote               |
| `body-lg`     | 18px | 1.6  | 400    | 主正文（blog）                        |
| `body-md`     | 16px | 1.6  | 400    | 常规正文                              |
| `body-sm`     | 14px | 1.5  | 400    | 元数据、caption                       |
| `body-xs`     | 12px | 1.4  | 500    | tag、chip、超小注解                   |
| `mono-md`     | 14px | 1.5  | 400    | 代码、data label、"since 2026" 类装饰 |

**响应式规则**：`display-*` 在 md 断点以下（< 768px）自动降一级；hero H1 移动端顶格 56px。

### 1.3 Spacing Scale (4px baseline)

```
--space-0:   0
--space-1:   4px
--space-2:   8px
--space-3:   12px
--space-4:   16px
--space-5:   20px
--space-6:   24px
--space-8:   32px
--space-10:  40px
--space-12:  48px
--space-16:  64px
--space-20:  80px
--space-24:  96px
--space-32:  128px
--space-40:  160px
--space-48:  192px
```

**Section 垂直节奏**：桌面 `space-40`（160px），移动 `space-24`（96px）。这是编辑感杂志感的关键。

### 1.4 Radius

```
--radius-sm:   6px    /* chip, small button */
--radius-md:   10px   /* input, small card */
--radius-lg:   14px   /* card */
--radius-xl:   20px   /* section container */
--radius-2xl:  32px   /* hero image, phone frame */
--radius-full: 9999px /* pill button */
```

### 1.5 Shadow（极简）

```
--shadow-xs:  0 1px 2px 0 rgba(31, 26, 20, 0.04)
--shadow-sm:  0 1px 3px 0 rgba(31, 26, 20, 0.06), 0 1px 2px -1px rgba(31, 26, 20, 0.06)
--shadow-md:  0 4px 6px -1px rgba(31, 26, 20, 0.06), 0 2px 4px -2px rgba(31, 26, 20, 0.06)
--shadow-lg:  0 10px 15px -3px rgba(31, 26, 20, 0.06), 0 4px 6px -4px rgba(31, 26, 20, 0.05)
--shadow-2xl: 0 25px 50px -12px rgba(31, 26, 20, 0.10)
```

**注意**：阴影用 `fg-primary` 的 rgba 而不是 `black`——阴影本身带暖色，与暖白底融合。

### 1.6 Motion

```
--ease-standard: cubic-bezier(0.4, 0, 0.2, 1)
--ease-decel:    cubic-bezier(0, 0, 0.2, 1)   /* 入场 */
--ease-accel:    cubic-bezier(0.4, 0, 1, 1)   /* 离场 */

--dur-instant:   80ms
--dur-fast:      160ms
--dur-normal:    240ms
--dur-slow:      420ms
--dur-editorial: 640ms   /* hero 揭幕、section reveal */
```

**纪律**：不用弹簧动画（spring）。编辑感是"从容"，spring 是"活泼"，方向不对。

---

## 2. Layout Grid

### 2.1 Container Widths

```
--container-narrow:   680px   /* blog 单栏正文 */
--container-default:  1120px  /* 常规 section */
--container-wide:     1360px  /* hero 全屏、地图展示 */
--container-max:      1440px  /* 极限，不能再宽 */
```

### 2.2 Column Grid

- 桌面：12 列，gutter `space-6`（24px）
- 平板：8 列，gutter `space-4`（16px）
- 移动：4 列，gutter `space-4`（16px）

### 2.3 编辑感排版规则

- **留白比内容重要**。Hero 上下留白 `space-24`（96px）×2 = 192px；section 之间 `space-40`（160px）。
- **不居中所有东西**。左对齐 > 居中。左对齐给读者"这不是广告，是文章"的心理暗示。
- **每屏最多一个视觉焦点**。Hero = 一段文字 + 一张 phone screenshot，不塞 3 张卡、5 个 logo。

---

## 3. Information Architecture（首页 EN）

首页 7 个 section，垂直流动：

```
0. Sticky nav (72px)
1. HERO                                  ← 3 秒说服
   "A map where every dot is worth
    a solo detour."
   [Get on App Store] [See how it works]
   → iPhone screenshot mock

2. THE PROBLEM                           ← 场景带入
   "It's 4 PM. You're alone..."

3. THREE PILLARS                         ← 差异化
   Map-First · Experience-as-Unit · AI doesn't decide

4. THE APP · scroll storytelling         ← Feature 深度
   4 个 App 界面 sticky-scroll

5. TRUST                                 ← 疑虑消除
   Privacy · AI transparency · Pricing honesty

6. PRICING                               ← 转化
   Lifetime $29 · Yearly $50

7. FOOTER                                ← 立场
   "Made by one person. Answerable to you."
```

---

## 4. Section Design Spec（逐屏）

### 4.1 Nav

- 72px tall，`sticky top-0`，`backdrop-blur-xl bg-warm/80`
- 左：logo 字标（`Space Grotesk 500 20px`，字符间距 `-0.01em`）
- 中：`Features · Pricing · Cities · Blog · Manifesto`
- 右：`Sign in`（text link）+ **Get on App Store**（primary button）
- 移动端：右侧 hamburger，展开为全屏暖白 sheet
- 滚动 40px 后 nav 底部加 `1px --border-subtle`

### 4.2 Hero（最重要的一屏）

**桌面（1440 × 900）**:

```
●  since 2026 · made for iOS 17+           ← mono-md, fg-muted

A map where                                ← display-2xl (96px)
every dot is worth                            fg-primary
a solo detour.                                line 1.02

Solo Compass is a map-first companion for  ← body-xl (22px)
people traveling alone. No feed. No ads.      fg-muted
Just experiences worth your afternoon.        max-w 640px

[ Get on App Store ]   See how it works →  ← primary + text link

                             ┌──────────┐
                             │  iPhone  │
                             │ DayPage  │
                             └──────────┘
```

**关键要素**：

- H1 左对齐、96px、只有 3 行；右侧 iPhone frame 展示 App 内 DayPage 真截图（不是设计稿）
- 上方 `● since 2026` 是**信任信号**：告诉读者"不是又一个昨天冒出来的 wrapper AI"
- CTA 是 primary button，标签 `Get on App Store`（不是 `Download` / `Try now`），第二 CTA 是 text link 不用第二个按钮抢焦点
- iPhone frame 用 iPhone 15 Pro mockup，`radius-2xl` = 32px，`shadow-2xl`，微 3° 倾斜

**中文版差异**：

- H1 混排 `Space Grotesk 500 + PingFang SC Semibold`
- 文案："每一个点，都值得你独自绕路一趟"
- 副标题："Solo Compass 是为独自旅行者做的地图。没有信息流，没有广告，只有值得你度过一个下午的体验。"
- CTA："App Store 下载"

**动效**：

- Hero 加载：H1 每行 `display-md` fade-up 60px + `dur-editorial` (640ms) 依次入场
- iPhone frame `dur-editorial` (640ms) `scale-95 → 1 + fade-in`
- **不用 spring**。iOS Home Screen 是 spring，Web hero 是 editorial

### 4.3 The Problem（Scenario 带入）

一整屏留白 + 一段极长的、编辑体、左对齐的文字。

```
It's 4 PM.

You're alone in a city you don't know.

You could open Google Maps —
      but the top-rated café will be full of couples on dates.

You could open 小红书 —
      but the "instagrammable" spot is a queue of tripods.

You could ask ChatGPT —
      but it will confidently invent a place that closed last year.

We built Solo Compass because none of those
felt like what an old friend
who knew the city would tell you.
```

**样式**：

- 全屏高度，垂直居中
- `body-xl` (22px)，`line-height 1.9`，`max-w-2xl`（640px）
- 每段之间 `mt-8`（32px）
- 关键词（Google Maps / 小红书 / ChatGPT）用 `text-fg-muted`
- 最后一段回到 `text-fg-primary`，重心落地

**中文版差异**：

- 保留韵律（每两段一个"你可以..."）
- "old friend" → "本地熟人"

### 4.4 Three Pillars

三张暖琥珀色卡片，横排（移动端纵排）。每张卡：

```
●                             ← 12px 圆点（三张卡不同色）
Map-First                     ← display-sm (32px)

The map is the home screen.   ← body-md (16px)
No tabs. No drawer. No           fg-muted, line 1.6
onboarding. Everything
happens on the map.

┌───────────────────────┐    ← 小 iPhone 缩略图，占卡 40%
│  map screenshot       │
└───────────────────────┘

  Background: --surface-white
  Border: 1px --border-subtle
  Radius: 14px
  Padding: 40px 32px 32px
  Hover: --shadow-md + translateY(-4px), 240ms
```

三张卡的圆点用不同色：

- Map-First → `--sun-gold`
- Experience-as-Unit → `--omen-gold`
- AI doesn't decide → `--accent`

### 4.5 The App · Scroll Storytelling

Sticky-scroll 结构，参考 apple.com/iphone。

左侧 `sticky top-24`：iPhone frame 展示当前 feature 的 App 截图，`radius-2xl`
右侧滚动：4 段长文字，每段一个 feature：

1. **Cross-referenced sources.** 每条建议追溯到 Wikivoyage / OSM / 独行者报告
2. **Time-aware.** "下午 3 点 + 雨天 + 周三"是动态的，不是静态 city guide
3. **Voice-first drift.** 说话"帮我找一个安静能读书两小时的地方"，AI 转成搜索
4. **Rituals, not gamification.** Daily Omen / Time Capsule / Blindbox — 不是徽章

每段进入视口时，左侧 iPhone 通过 `crossfade + dur-slow` 换图。

**< md 断点降级**为纵向列表，每 feature 一图一段，不 sticky。

### 4.6 Trust

三段直白文字，无花哨视觉。

```
Privacy is a promise, not a checkbox.

Your location never leaves your phone.
No accounts required to try. No email.
No "sign up with Google". Anonymous by default.

──────────

AI is a filter, not an oracle.

Every AI suggestion shows its sources
and how confident it is. We show freshness:
🟢 verified this month  🟡 fading  🔴 questioned.

──────────

Pricing is honest.

$29 one-time, or $50 a year. That's it.
No ads ever. No selling your data ever.
No free-then-paywall bait.
```

- `body-xl` (22px)，`max-w-xl` (36em)，居中对齐
- 三段之间用 `border-b-1 border-border-subtle + my-16`（64px）分隔
- 每段第一行"大声宣言"用 `display-sm`，后面用 `body-lg`

### 4.7 Pricing

两张卡横排，第三卡 Free 用较小的形式点缀。

```
┌────────────────────────┐  ┌────────────────────────┐
│                        │  │  MOST POPULAR          │
│  Pro Lifetime          │  │  Pro Yearly            │
│                        │  │                        │
│  $29 one time          │  │  $50 / year            │
│                        │  │                        │
│  Every feature today.  │  │  Every feature, plus  │
│  Forever yours.        │  │  everything we ship   │
│                        │  │  in the future.       │
│                        │  │                        │
│  ✓ AI cross-referencing│  │  ✓ Everything in      │
│  ✓ Custom routes       │  │    Lifetime           │
│  ✓ Rituals             │  │  ✓ First access to    │
│  ✓ Print export        │  │    new features       │
│  ✓ Cloud sync          │  │  ✓ New AI models      │
│                        │  │  ✓ Cloud sync         │
│  [ Buy Once ]          │  │  [ Start Yearly ]     │
│                        │  │                        │
└────────────────────────┘  └────────────────────────┘

           Free · try before you install →
```

- Lifetime 卡：`bg-surface-white`, `border-1 border-border-default`
- Yearly 卡（推荐）：`bg-accent-soft`, `border-1 border-accent-border`, `MOST POPULAR` chip 顶部
- 两张卡 `radius-xl`（20px），`p-10` 内边距，`gap-6` 之间
- CTA button：Lifetime = secondary button（暖白底 accent 描边），Yearly = primary button（accent 底暖白字）
- 下方 "Free" 是 text link，不是第三张卡——避免决策稀释

### 4.8 Footer

极简，一行叙事：

```
Solo Compass is made by one person, in Kyoto.
No VC. No ads. No tracking. Answerable to you.

──────────────────────────────────────────

Company     Product     Legal
About       Features    Privacy
Manifesto   Pricing     Terms
Contact     Cities      DPA
            Blog

──────────────────────────────────────────

© 2026 Solo Compass · Made with respect for solo travelers.
```

- `bg-surface-sunken`, `pt-24 pb-16`, 4 列 grid, 每列 `body-sm`, header `body-xs uppercase tracking-widest`

---

## 5. Component Library（核心 10 件套）

### 5.1 Button

```
Primary:
  bg-accent · text-bg-warm · h-12 · px-6 · radius-full · body-md 500
  hover: bg-accent-hover
  focus: ring-2 ring-accent-soft ring-offset-2

Secondary:
  bg-transparent · text-fg-primary · border-1 border-border-default · h-12 · px-6 · radius-full · body-md 500
  hover: border-fg-primary

Text link:
  text-accent · underline-offset-2 · hover:underline · body-md
```

### 5.2 Card

- `bg-surface-white` · `border-1 border-border-subtle` · `radius-lg` · `p-8`
- Hover：`shadow-md` + `translateY(-2px)` transition 240ms

### 5.3 Chip / Badge

- `bg-accent-soft` · `text-accent` · `border-1 border-accent-border` · `radius-full` · `px-3 py-1` · `body-xs 500 uppercase tracking-widest`
- 变体：`sun-gold-soft + sun-gold-deep` / `success-soft + success-text` / `warning-soft + warning-text`

### 5.4 iPhone Frame

- iPhone 15 Pro 高质量 mockup
- Wrapper：`radius-2xl` · `overflow-hidden` · `shadow-2xl`
- 内部截图必须是**真机截图**（不是设计稿）

### 5.5 Section Header

```
● Section eyebrow             ← body-xs, uppercase, tracking widest, sun-gold-deep
Section title                 ← display-lg
Optional subheader body-xl    ← fg-muted, max-w-2xl
```

`●` 圆点用 sun-gold，是 Solo Compass 的编辑感 accent。

### 5.6 Pull Quote

- `border-l-2 border-accent` · `pl-6` · `Fraunces serif` · `body-xl italic`
- 用在 Blog 和 Manifesto

### 5.7 Table (Pricing / Feature Compare)

- Header row：`bg-surface-sunken` · `body-xs 500 uppercase tracking-widest`
- Cell：`py-4 px-6` · `border-b-1 border-border-subtle`
- ✓ 用 `text-success-text`, ✕ 用 `text-fg-subtle`
- Highlight column：`bg-accent-soft`

### 5.8 Nav Item

- `text-fg-muted` · `body-md` · `px-3 py-2`
- Active/current: `text-fg-primary` + `border-b-2 border-accent` (offset 4px)

### 5.9 CTA Bar (mobile sticky bottom)

- `fixed bottom-0` · `bg-warm/95 backdrop-blur-xl` · `border-t border-border-subtle` · `p-4`
- primary button + 说明文字, `safe-area-inset-bottom` padding

### 5.10 Screenshot Frame with Caption

- 图 + 图下 `body-sm fg-muted italic` caption

---

## 6. Copy Voice Guide

### 6.1 Voice principles

1. **诚实过度承诺**。写 "$29" 不写 "starting at $29"。
2. **拒绝营销术语**。不用 "revolutionary" / "AI-powered" / "seamless"。
3. **第二人称 you**。不用 "our users"。
4. **短句，编辑标点节奏**。用破折号——、句号。 少用 !。
5. **中文遵循同样节奏**：直白、非营销、编辑感。

### 6.2 Do / Don't

| Don't                                      | Do                                                 |
| ------------------------------------------ | -------------------------------------------------- |
| "Discover amazing hidden gems!"            | "Places worth walking twenty minutes to."          |
| "Powered by AI to plan your perfect trip." | "AI narrows a thousand options to five. You pick." |
| "The ultimate travel companion for 2026"   | "A map for people who travel alone."               |
| "Sign up now, it's free!"                  | "Try it. If you like it, pay once."                |

### 6.3 中文文案纪律

- 不用"绝了 / yyds / 直接封神"这类流行词——目标用户反感
- 不用"深度种草 / 强推 / 无限回购"
- 用书面语但保留韵律："每一个点，都值得你独自绕路一趟"
- 允许每页最多一次古典引用（Manifesto 页可引钱穆或村上春树）

---

## 7. Dark Mode

- 触发：`prefers-color-scheme: dark` + 用户手动切换（存 localStorage）
- 底色：`--dark-sheet`，卡片：`--dark-card`
- 阴影降级：`--shadow-md` → 变为 `border-1 border-dark-border`
- 图片：Hero iPhone frame 换深色壁纸版本
- CTA primary 在 dark 下不变（`--accent` 在 dark 依然对比度足够）

---

## 8. Motion Library

### 8.1 页面级

- **Route transition**：`opacity 0.4 → 1 + translateY(12px → 0)`, `dur-normal`
- **Section reveal**：IntersectionObserver 触发 `opacity + translateY(24px)`, `dur-editorial`, once
- **Image lazy load**：`blur-md → blur-0`, `dur-slow`

### 8.2 交互级

- Button hover：`transform scale(1.02)`, `dur-fast`
- Card hover：`translateY(-4px)` + shadow up, `dur-fast`
- Link hover：`underline underline-offset-4`, no transition

### 8.3 Hero 专属动效

Cascading Reveal 序列：

```
t=0ms       eyebrow fade in
t=200ms     H1 line 1 fade-up
t=380ms     H1 line 2 fade-up
t=560ms     H1 line 3 fade-up
t=800ms     subheader fade-up
t=1040ms    CTA buttons fade-up
t=200ms     iPhone frame fade + scale from 0.94
```

**纪律**：整个序列 < 1600ms 完成，之后**静止**。不做无限循环的漂浮动画。编辑感 ≠ 花里胡哨。

---

## 9. Accessibility 最低标准

- WCAG 2.2 AA 全部通过
- 所有交互元素 keyboard reachable, `outline-2 outline-accent outline-offset-2` on focus
- 色对比：`--fg-primary on --bg-warm` = 15.6:1 ✅；`--fg-muted on --bg-warm` = 5.4:1 ✅；`--accent on --bg-warm` = 12.1:1 ✅
- `--fg-subtle on --bg-warm` = 3.8:1 ⚠️ — 仅用于装饰性 caption
- 所有图片带 `alt`，装饰性 SVG 加 `aria-hidden="true"`
- Hero H1 用 `<h1>`，section header 用 `<h2>`，卡片 header 用 `<h3>`

---

## 10. 首发 Section 清单（Phase 1）

按优先级建，第一批只做**首页 + 定价 + 隐私 + Manifesto**：

- [ ] `/` Homepage EN (7 sections above)
- [ ] `/zh` Homepage CN
- [ ] `/pricing` Pricing EN
- [ ] `/zh/pricing`
- [ ] `/manifesto` (独立开发者叙事)
- [ ] `/zh/manifesto`
- [ ] `/privacy` (SEO + trust)
- [ ] `/zh/privacy`
- [ ] `/download` (App Store redirector)
- [ ] `/sitemap.xml` + `/robots.txt`
- [ ] `next/og` 动态 OG 图

Phase 2 再上：Features 深度页 · Cities 静态页 · Blog · 深色模式切换器

---

## 11. 一句话总结（可以贴在显示器上的）

> **Solo Compass 官网是 App 内 DayPage 的杂志刊。让第一次看到的人以为这是《Kinfolk》独立开发者特刊，不是又一个 SaaS 官网。**

任何视觉决策与此矛盾，重新审视。
