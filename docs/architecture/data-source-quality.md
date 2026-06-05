# RFC: Data-Source Quality & Activation

**Status:** Draft · **Date:** 2026-06-05 · **Scope:** `packages/sources` + iOS data pipeline · **Theme:** 接通已写好的数据源框架,提升数据质量与透明度

> 用户感受到的"数据太少、AI 处理太浅、质量不够",根因不是接的 API 太少,而是:
> ① 一套设计完整的数据源框架(`packages/sources`)从未通电;
> ② 融合排序只看"信号数量"不看"信号质量";
> ③ AI 在数据缺失时用硬编码占位符"优雅地编造";
> ④ 自家 UGC 信号(`MicroSurveyRecord` 等)没回流成真实 solo 信号。
>
> 本 RFC 聚焦 ①(用户已选定方向),并为 ②③④ 留接口。

---

## 1. 背景:两套数据源体系,一套没通电,一套偏科

### 1.1 TS 框架(`packages/sources`)— 设计完整,零生产调用

已实现且**接口完整**:

| 包                      | 内容                                                                                       | 状态    |
| ----------------------- | ------------------------------------------------------------------------------------------ | ------- |
| `sources/core`          | `SourceAdapter` 接口、`Candidate` 标准化类型、`getActiveAdapters` 注册表                   | ✅ 写好 |
| `sources/osm`           | `OsmAdapter`(weight 0.7,24h 缓存,1 req/s 限流)                                             | ✅ 写好 |
| `sources/wikivoyage`    | `WikivoyageAdapter`(weight 0.8,人工旅游指南,7d 缓存)                                       | ✅ 写好 |
| `sources/google-places` | `GooglePlacesAdapter`(weight 0.9,实时评分/营业时间)+ `BudgetTracker`(每日 $ 上限,UTC 重置) | ✅ 写好 |

**事实(已验证):** 全 codebase 无任何非测试代码调用 `getActiveAdapters` / `new OsmAdapter` / `adapter.fetch`,无 pipeline 脚本调用 adapters。**这是一套从未通电的框架。** seed JSON(`apps/ios/.../Resources/JSON/seed_experiences.json` 等)由其他路径(Ralph / 手工 / 离线脚本)生成,不经过 adapters。

### 1.2 iOS 运行时(`Services/*`)— 独立实现,偏科

实际在跑的另一套,与 TS 共享数据库但**不共享代码**:

| 源                          | 角色                         | 质量                            |
| --------------------------- | ---------------------------- | ------------------------------- |
| `OverpassService`(OSM)      | 唯一权威 POI 源              | 全球覆盖,标签质量不一           |
| `FoursquareService`         | 信号增强                     | 免费层常返回 nil                |
| `MapKitPOIService`          | 信号增强                     | 字段少                          |
| `WebSearchEnrichmentSource` | 验证字段(营业时间/网站/电话) | **默认关**(配额成本,非技术原因) |
| `EnrichmentAgent`           | 多源融合中枢                 | 架构清晰,但排序只看信号数量     |

### 1.3 核心张力:两套是**不同的数据哲学**

这是接通框架前必须想清楚的:

```
TS 框架:   原始源 → Candidate(瘦:title + rawText) → AI 结构化 → Experience
                                    ↑ 富信息全在 rawText,交给 AI 解析

iOS 运行时:多源 → 结构化字段(rating/hours/price)→ 规则融合 → AI 合成 → Experience
                                    ↑ 字段已结构化,AI 只做合成不做解析
```

**`Candidate` 类型(已确认)只有:** `sourceId / sourceName / title / rawText / url? / coordinates? / fetchedAt`。
**它没有结构化的 rating / hours / price** —— 这些在 TS 哲学里属于 `rawText`,等 AI 解析;在 iOS 哲学里是独立字段,直接用。

> **结论:不能简单"把 TS 框架塞进 iOS"。** 要么扩展 `Candidate` 让它能携带结构化信号(推荐),要么明确两套各管一段(见 §4)。

---

## 2. 目标 / 非目标

**目标**

- G1 让 `packages/sources` 框架**通电**:有一条真实 pipeline 调用 `getActiveAdapters` → `fetch` → 落库。
- G2 把 Wikivoyage(指南内容)、Google Places(实时评分/营业时间)两个**已写好但闲置**的源接入数据流。
- G3 让 `Candidate` 能携带**来源元信息**(来自哪个源、权重、新鲜度),为 §4 质量感知融合铺路。
- G4 复用 `BudgetTracker` 控制 Google Places 成本(它已实现,只是没人用)。
- G5 明确 TS 框架与 iOS 运行时的**职责边界**,消除"两套并存"的混乱。

**非目标(本 RFC 不展开,留接口)**

- N1 质量感知融合加权(病灶②)—— 另立小节描述方向,不实现。
- N2 诚实降级 / 信任透明(病灶③)—— 引用,不实现。
- N3 UGC 回流闭环(病灶④)—— 引用 `agent-memory-context.md` 的 L3/L4,不实现。
- N4 真实图片 / 评论 UGC 外部源 —— 未来。

---

## 3. 通电方案:让框架跑起来

### 3.1 选址:pipeline 放哪

框架是 Node/TS,**不在 iOS 进程内**。两个落点:

| 方案                        | 形态                                                                                               | 优点                                          | 缺点                                   |
| --------------------------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------- | -------------------------------------- |
| **A. 离线/批处理 pipeline** | 一个 `scripts/compile-experiences.ts`,定期跑 `getActiveAdapters → fetch → AI 结构化 → 落 Supabase` | 成本可控、可缓存、不阻塞用户;符合 PRD"编译腿" | 数据非实时(但体验发现本就不需秒级实时) |
| **B. 后端按需 pipeline**    | Edge Function / API route 实时调 adapters                                                          | 实时                                          | 成本失控风险、延迟、和 iOS 运行时重叠  |

**推荐 A(批处理编译)。** 理由:

- 体验发现(café/景点)的数据**变化慢**,不需要实时拉取。
- 批处理天然适合 `BudgetTracker`(每日 $ 上限)和限流。
- 与 PRD v2 的"三腿数据引擎(编译 + 编辑 + 用户信号)"中的**编译腿**对齐。
- iOS 运行时(Overpass 实时)继续负责"用户当下视口的即时 POI",两者**互补不重叠**(见 §5)。

### 3.2 Pipeline 骨架(伪代码,基于已确认接口)

```ts
// scripts/compile-experiences.ts —— 让框架通电的第一个真实消费者
import { getActiveAdapters } from "@solo-compass/sources-core";
import { OsmAdapter } from "@solo-compass/sources-osm";
import { WikivoyageAdapter } from "@solo-compass/sources-wikivoyage";
import { GooglePlacesAdapter } from "@solo-compass/sources-google-places";
import { structureExperience } from "@solo-compass/ai";

const adapters = getActiveAdapters({
  adapters: [new OsmAdapter(), new WikivoyageAdapter(), new GooglePlacesAdapter({ budget })],
  enabled: process.env.SOURCES_ENABLED?.split(","), // 灰度开关
});

for (const cityCode of targetCities) {
  // 1. 多源并发召回 Candidate[]
  const candidates = (
    await Promise.all(adapters.map((a) => a.fetch({ cityCode, maxResults: 50 }).catch(() => [])))
  ).flat();

  // 2. 按 coordinates/title 去重(复用 dedup,见 §4)
  const deduped = dedupeCandidates(candidates);

  // 3. AI 结构化:Candidate.rawText → Experience(structureExperience 已存在)
  //    关键:把 sourceName/fetchedAt 作为 attribution 一路带进 Experience.sources
  const experiences = await Promise.all(deduped.map((c) => structureExperience({ candidate: c })));

  // 4. 落库 Supabase(复用 seed-load 的 upsert 逻辑)
}
```

**注意:** `structureExperience` 已存在(`packages/ai`),但当前签名吃的是 raw text,需确认/适配让它接收 `Candidate` 并把 `sourceName` 写进 `Experience.sources`(attribution)。

### 3.3 扩展 `Candidate` 携带来源元信息(G3 关键)

当前 `Candidate` 太瘦,融合后丢失"来自哪个源、多新、权重多高"。**最小扩展(提议,未实现):**

```ts
interface Candidate {
  // ...现有字段...
  readonly sourceWeight?: number; // 来自 adapter.weight,用于质量加权(§4)
  readonly signals?: {
    // 结构化信号(Google Places 有,OSM 没有)
    readonly rating?: number;
    readonly ratingCount?: number; // 样本量 —— 质量加权的关键
    readonly priceLevel?: number;
    readonly openingHours?: string;
    readonly liveStatus?: "open" | "closed" | "unknown";
  };
}
```

这一步**调和了 §1.3 的两套哲学**:`rawText` 仍走 AI 解析(Wikivoyage 指南),`signals` 走结构化直用(Google Places),`Candidate` 同时承载两者。

---

## 4. 为后续病灶预留的接口(本 RFC 不实现,但通电时按此设计)

### 4.1 病灶②:质量感知融合(预留)

当前 iOS `EnrichmentAgent.signalScore` 数"字段个数"。框架通电后,融合应改为**质量加权**:

```
score = Σ(field 存在) × sourceWeight × freshness(fetchedAt) × sampleSize(ratingCount)
```

`Candidate.sourceWeight` + `signals.ratingCount` + `fetchedAt`(§3.3 已加)正是为此预留。

### 4.2 病灶③:诚实降级(预留)

AI 缺数据时**不再硬编码占位符**(`"9-21"` / `7.0-8.0`),而是:

- 字段缺失 → 标记 `null` + UI 显示"未验证",不编造。
- 置信度徽章从"等级数字 `L1`"升级为用户能懂的"AI 推测 / 多源印证"。
- 复用 `packages/core/confidence.ts` 的 5 级模型 + `healthFromConfidence`(已实现,只是 UI 没充分表达)。

### 4.3 病灶④:UGC 回流(引用)

最高价值的 solo 信号源是**自家用户闭环**,不是外部 API。`MicroSurveyRecord`(comfort/pressure 1-5)、`UserCompletionRecord` 应回流覆盖 AI 猜测的 `soloScore`。
PRD v2 已写"用户验证 ≥5 则覆盖 AI soloScore",但**未实现**。详见 [`agent-memory-context.md`](./agent-memory-context.md) 的 L3/L4 —— 同一批孤岛数据,既喂 memory 也喂数据质量。

---

## 5. 职责边界:消除"两套并存"的混乱(G5)

通电后**明确分工**,而非让 TS 框架和 iOS 运行时打架:

```
┌─ 编译腿(TS 框架,批处理)──────────────────────────┐
│  packages/sources → AI 结构化 → Supabase            │
│  职责:城市级、慢变、高质量的 Experience 主数据       │
│  源:OSM + Wikivoyage(指南)+ Google Places(评分)  │
└─────────────────────────────────────────────────────┘
                        ↓ 落库
┌─ 运行时腿(iOS,实时)──────────────────────────────┐
│  OverpassService → EnrichmentAgent → AI 合成         │
│  职责:用户当下视口的即时 POI 补充(库里没有的)      │
│  源:Overpass + Foursquare + MapKit(实时信号)       │
└─────────────────────────────────────────────────────┘
```

**原则:** 编译腿管"主数据质量",运行时腿管"即时补充"。Google Places 的实时评分/营业时间通过编译腿进库,iOS **不直连 Google Places**(成本可控)。长期可考虑让 iOS 运行时也消费 TS 框架的标准化产物,但**本期不强求统一两套代码**(iOS 是 Swift、不在 workspace,统一成本高)。

---

## 6. 成本与配额

- **Google Places:** `BudgetTracker`(已实现)每日 $ 上限,UTC 重置。批处理 + 缓存(6h)使单位成本远低于按用户实时调用。`GOOGLE_PLACES_DAILY_CAP_USD` 环境变量控制。
- **Wikivoyage / OSM:** 免费,限流已内置(OSM 1 req/s,Wikivoyage 10 req/min)。
- **AI 结构化:** 批处理可用更便宜模型 / 批量调用,不挤占用户端的实时合成配额(30/天)。
- **WebSearchEnrichment(iOS):** 当前默认关因配额成本。编译腿补齐营业时间后,iOS 端对 WebSearch 的需求下降(数据已在库里)。

---

## 7. 实施路线图

| 阶段     | 内容                                                                                                           | 风险     |
| -------- | -------------------------------------------------------------------------------------------------------------- | -------- |
| **P0**   | `scripts/compile-experiences.ts` 调通 `getActiveAdapters → OsmAdapter.fetch → 落库`(先只 OSM,验证 pipeline 通) | 低       |
| **P1**   | 接入 `WikivoyageAdapter`(指南 rawText → AI 结构化)+ attribution 写进 `Experience.sources`                      | 低       |
| **P2**   | 接入 `GooglePlacesAdapter` + `BudgetTracker`,扩展 `Candidate.signals`(结构化评分/营业时间)                     | 中(成本) |
| **P3**   | 质量感知去重 + 融合(§4.1),来源元信息一路带到库                                                                 | 中       |
| **未来** | 诚实降级 UI(§4.2)+ UGC 回流(§4.3,与 memory RFC 合流)                                                           | —        |

每阶段独立可灰度(`SOURCES_ENABLED` 名单开关,复用 `getActiveAdapters` 的 `enabled` 字段)。

---

## 8. 验证

- **P0:** 跑 pipeline,断言 OSM Candidate 落库为有效 Experience;`pnpm parity:check` 确认 schema 一致。
- **P1/P2:** 单测每个 adapter 的 `fetch` mock;集成测 `compile` 脚本 dry-run 不超预算。
- **数据质量回归:** 抽样对比通电前后的 Experience —— 营业时间/评分字段的"真实填充率"(非占位符比例)应显著上升。
- 遵循 `CLAUDE.md`:TS 改动 `pnpm typecheck` + `pnpm test`;触碰 `packages/core/experience.ts`(若扩展 sources 字段)必须 `pnpm parity:check`(TS↔Swift 双向)。

---

## 9. 开放问题

1. 编译腿的目标城市清单从哪来?(当前 seed 是哪些城市?是否复用 `DiscoveredCityRecord`?)
2. `Candidate.signals` 扩展会不会要求 `structureExperience` 改签名?需先确认 `packages/ai` 的现有契约。
3. Google Places 的 `BudgetTracker` 是 in-process(重启清零),批处理脚本若分多次跑,预算是否要持久化?(budget.ts 注释已提示"production 需持久化")
4. iOS 运行时腿长期是否收敛到消费 TS 标准化产物?还是永久双轨?(影响是否值得为 iOS 写 Swift 版 adapter)
5. 与 `agent-memory-context.md` 的 UGC 回流:`MicroSurveyRecord` 同时是 memory 画像源和数据质量信号源 —— 两个 RFC 是否该共用一个"用户信号聚合"组件?
