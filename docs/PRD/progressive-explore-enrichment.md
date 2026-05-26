# PRD: 渐进式 Explore + 多渠道交叉编译富集

> Status: Draft · Owner: iOS · Supersedes the deep-dive bits of `pro-radial-explore.md`
> 关联实现入口: `MapViewModel.exploreNearby` → `EnrichmentAgent`

## 1. 一句话

用户点 "Explore here"（或选了咖啡/美食）后，agent 从 **5km 内**开始按用户的兴趣类目跨多个数据源采集，**边搜边在地图上标记**，对每一条做**跨渠道交叉编译**补全详情；如果 5km 数据不足，自动**渐进扩展到 10 → 25 → 100km**，直到拿到足够数据。

## 2. 为什么（问题）

当前 `exploreNearby` 有三个体验缺陷：

1. **半径固定**：要么 3km 单环、要么 Pro 的 1.5/3/6/12km 一次性全打。空旷地区 3km 没数据就直接报 "nothing found"，用户无从知道"再远一点就有"。
2. **一次性出结果**：所有 POI 跑完 synthesis 才一次性刷地图。慢，且没有"正在为你找"的过程感。
3. **每条数据浅**：单条 experience 只用了它自己 POI 的 tag，没有跨渠道交叉验证 —— 一个咖啡馆在 OSM、Foursquare、Apple Maps、网络上各有一部分信息，从不汇总。

本 PRD 把 explore 重构为一个**有状态、渐进、增量、可交叉验证**的 agent 流程。

## 3. 用户故事

- **US-PE-01** 作为独自旅行者，我点 Explore，希望优先看到**离我最近**的好去处，远的稍后补上。
- **US-PE-02** 当我已经选了"咖啡"，Explore 只找咖啡相关的地方，不要把所有类目都铺上来。
- **US-PE-03** 我在一个冷门小镇，5km 内没什么 —— 我希望 app **自动往外找**到有数据为止，并告诉我"为你扩大到了 25km"。
- **US-PE-04** 我希望看到地图上的标记**一个一个浮现**（边找边标），而不是盯着转圈等到最后。
- **US-PE-05** 我点开一条详情，希望看到**评分、营业时间、价格、为何值得**这些被多个来源交叉印证过的信息，而不是"这是个咖啡馆，到了自己看"。

## 4. 核心设计

### 4.1 渐进式半径扩展（Progressive Radius Ladder）

替换"固定半径/一次性多环"为**阶梯式扩展**，每一阶达到"足够"门槛就停：

```
阶梯：5km → 10km → 25km → 100km
门槛：每阶产出的"可用 experience"数 ≥ enoughThreshold（默认 8）就停止扩展
```

伪逻辑：

```
results = []
for radius in [5_000, 10_000, 25_000, 100_000]:
    batch = enrichmentAgent.collect(center, radius, categories)   # 见 4.3
    results += dedupe(batch, against: results)                    # 跨阶去重
    publishIncrementally(results)                                 # 见 4.4，边搜边标
    if results.count >= enoughThreshold: break
    # 否则继续下一阶；UI 告知"附近较少，正在扩大到 Nkm"
if results.isEmpty:
    fallbackToCachedOrError()                                     # 复用现有 cache 回退
```

要点：
- **只在不够时才扩**。5km 就够时永远不会去打 100km —— 省配额、省时延、保持"近"的语义。
- 每阶**只采集该阶新增的环形区域**（`prevRadius..<radius`），避免重复打内圈（用 Overpass 的环形 query 或对结果按距离过滤）。
- **跨阶去重**：以坐标 cell（4 位小数 ≈11m）+ osmId 双重去重，新阶不重复已发布的点。
- 扩展原因要可见：每次跨阶把进度态切到 `.expanding(toRadiusKm:)`，UI 显示 "附近较少 · 正在扩大到 25km"。

### 4.2 类目意图（Category Intent）

Explore 的采集范围由"用户意图"驱动，优先级：

1. **显式单选**：用户当前点了某个类目 pill（`selectedCategory`）→ 只采该类目。
2. **初始多选偏好**：没有单选但 onboarding 选过 `preferences.preferredCategories`（如 [咖啡, 美食, 文化]）→ 采这几类的并集。
3. **全部**：两者皆空 → 采全类目（现状行为）。

每个数据源都已有类目映射（`OverpassService` 的 query 分支、`FoursquareService.categoryToFoursquareIds`、`MapKitPOIService.poiFilter`），意图层只需把"要采哪些类目"下发给各源。

### 4.3 多渠道采集 + 交叉编译（Cross-Channel Compilation）

每一阶的 `collect` 内部，对每个类目并发打所有可用源，然后**按地点把碎片信息缝合成一条**：

```
            ┌─ Overpass(OSM)   → 名称/坐标/类目/部分 tag
 一个地点 ──┼─ Foursquare       → rating / hours / price / popularity / 电话 / 网址
            ├─ Apple MapKit     → 类目 / 电话 / 网址 / 结构化地址
            └─ Web 搜索(可选)   → 一句话补充 / 营业状态 / 知名度信号
                  │
                  ▼
            cross-compile（按坐标 cell 聚合 → 信号折叠）
                  │
                  ▼
            AIService.synthesize（基于交叉验证后的厚信号深写）
```

**交叉编译规则**（扩展现有 `FoursquareService.enrichMerge`）：
- 同 cell 的多源记录合并为一条 `CompiledPlace`，保留每个字段的**来源标签**。
- 字段冲突时按**来源可信度**排序取值：坐标/名称 OSM 优先；rating/hours/price 取 Foursquare > MapKit；地址取 MapKit 结构化 > 反查地理编码。
- 缺失字段才向下一个源要 —— 不重复覆盖更权威的源。
- **置信度**：被 ≥2 个源印证的地点，confidence 升级（现有 `Confidence.level` + `basedOnCount`），UI 显示"多来源印证"徽标。

**Web 搜索源（新，可选、配额敏感）**：
- 仅对**已通过排序的 top-N**地点触发（不是对所有 POI），把"用真实评分/营业时间挑出的好地方"再补一句网络上的真实细节。
- 走现有 AI 通道或一个轻量搜索 API；无 key/配额耗尽时静默跳过，不阻塞主流程。
- 严格约束：只补**可交叉验证**的客观信息（营业状态、是否网红、是否适合独自前往），不编造菜品/店主故事 —— 沿用现有 prompt 的反幻觉边界。

### 4.4 增量地图标记（Incremental Pin Drop）

把"全部完成才刷地图"改为**边产出边发布**：

- agent 每完成**一个类目 × 一阶**的 synthesis，就把这批 experience **增量 append 到 `visibleExperiences`** 并触发地图刷新。
- 新标记用**淡入 + 轻微下落动画**逐个浮现（复用现有 `MarkerIconView` + annotation fade）。
- 进度态 `ExploreProgress` 扩展：
  ```
  idle
  scanning(radiusKm, channel)        // "正在 5km 内搜索咖啡…"
  compiling(placeCount)              // "交叉核对 12 个地点的信息…"
  expanding(toRadiusKm)              // "附近较少 · 扩大到 25km"
  synthesizing(poiCount)             // 已有，保留
  ```
- 进度胶囊（现有 `ExploreProgressBar`）实时反映当前阶段 + 半径 + 已找到数量。

### 4.5 体验细节（让它感觉"活"）

- **首批最快**：5km + 用户主类目 优先跑、优先标 —— 用户最快看到"离我最近、我最想要的"。
- **地图镜头**：首批落点后轻微 `recenter` 到结果质心；跨阶扩展时若新点在视野外，用一次平滑 zoom-out 提示"范围变大了"。
- **半径可视化**：扩展时在地图上画一个**渐隐的半径圈**（5/10/25/100km），让"正在往外找"有空间感。
- **空结果也优雅**：到 100km 仍无 → 不是冷冰冰的 error，而是"这片区域我们还没有数据，换个城市试试？"+ 城市选择入口（复用现有 browse-city）。
- **可中断**：用户在扩展途中拖动地图/选了别的类目 → 取消当前 agent 任务，按新意图重启（任务取消用 `Task` cancellation）。

## 5. 架构落点

| 层 | 改动 |
|----|------|
| `EnrichmentAgent` | 新增 `exploreProgressively(center, categories, onBatch:)`：阶梯循环 + 跨阶去重 + 增量回调。`enrich` 收敛为单阶 `collect` |
| `EnrichmentAgent` | 新增 `CompiledPlace` 中间模型（带 per-field 来源标签）+ 交叉编译合并逻辑 |
| `WebSearchEnrichmentSource`（新，可选） | top-N 地点的网络补充，配额敏感、可静默降级 |
| `MapViewModel.exploreNearby` | 改为驱动 `exploreProgressively`，`onBatch` 回调里增量更新 `visibleExperiences` + 进度态 |
| `MapViewModel.ExploreProgress` | 加 `scanning(radiusKm,channel)` / `compiling` / `expanding(toRadiusKm)` |
| 意图层 | `exploreNearby` 解析 `selectedCategory` ?? `preferredCategories` ?? 全部，下发给各源 |
| `CompassMapView` | 增量 annotation 淡入；可选半径圈 overlay；进度文案随阶段更新 |
| 数据源 | Overpass/Foursquare/MapKit 已可按类目+半径采；环形采集（`prevR..<R`）需补 |
| Schema | 4.3 的来源标签若要持久化展示 → `ExperienceLocation` 已有 rating/hours 等字段，可加 `dataSources: [String]`（TS+Swift+SwiftData parity） |

## 6. 配额与性能

- **阶梯短路**省掉大部分远距离调用（多数城市 5km 就够）。
- Foursquare/Web 搜索都**配额敏感 + 静默降级**，绝不阻塞。
- 每阶的多源采集**并发**；synthesis 按"类目×阶"小批（≤8）调用，便于增量发布且单次便宜。
- 跨阶去重 + 现有 30 天 synthesis 缓存避免重复 AI 花费。
- `enoughThreshold` / 各阶半径 / top-N for web 全部可配（FeatureFlags 或常量），便于灰度调参。

## 7. 验收标准

- [ ] 5km 内有足够数据时，**不**触发更远阶；toast 不提扩展。
- [ ] 5km 不足时自动扩到 10/25/100km，每次扩展 UI 明示新半径与原因。
- [ ] 100km 仍无 → 友好空态 + 城市切换入口，**不**报技术 error。
- [ ] 选了"咖啡"时，结果只含咖啡类；未选时用 onboarding 偏好；都没有则全类目。
- [ ] 地图标记**增量浮现**（首批 < 全部完成时间），非一次性。
- [ ] 被多源印证的地点 confidence 更高、详情含真实 rating/hours/price 且标来源。
- [ ] 扩展途中用户改类目/拖图 → 旧任务取消、按新意图重启，无脏数据。
- [ ] 全程可在飞行模式优雅降级到缓存（复用现有 offline 回退）。
- [ ] `pnpm parity:check` 绿；`xcodebuild build`+全测试通过；新增渐进/交叉编译单测。

## 9. 对话/语音驱动的 Agent 调度层

前面 §4 把 explore 做成了一个**渐进、交叉编译、增量**的引擎。本章让用户能用**自然语言（对话框/语音）主动驱动**这个引擎 —— explore 不再只是一个按钮，而是一个可被 agent 自主调度的能力。

### 9.1 目标场景

用户在 chat / 语音框里说：
- "帮我找个**高分**的咖啡馆" → 高 rating 过滤 + coffee 类目 + 渐进采集
- "附近有没有**环境不错、适合一个人待着**的地方" → 高 ambianceFit + 高 soloScore + 不限类目
- "我想找**安静**能工作的咖啡馆" → coffee + 高 seatingFriendly + 低 staffPressure
- "**再远一点**也行" → 主动触发下一阶半径扩展
- "把**评分低于 8 分的**从地图上去掉" → 对已标记集合做质量过滤
- "**只看美食**" → 类目过滤（已支持）

agent 自主完成：理解意图 → 转成结构化查询 → 选数据源/设半径 → 调度采集 → 在地图标记 → 用一句话回复解释做了什么。

### 9.2 复用现有 agent 流水线

仓库已有 `Intent → Query → Guide` 流水线（`AgentRouter`）与 `VoiceAgentToolRouter`（7 个工具）。本章是**扩展**，不是重建：

```
用户语音/文字
   │
   ▼
IntentAgent      → FindExperience / GetRecommendation / ChangeSettings / SmallTalk（已有）
   │
   ▼
QueryAgent       → ExperienceFilter（扩展：见 9.3）
   │
   ▼
ToolRouter       → explore_nearby / search_places（扩展：接质量维度 + 渐进，见 9.4）
   │              + filter_visible（新：对已标记集合按质量过滤）
   │              + expand_radius（新：主动扩一阶）
   ▼
EnrichmentAgent.exploreProgressively（§4 引擎）
   │
   ▼
GuideAgent       → 一句话回复："为你找到 3 家 8 分以上的咖啡馆，最近的在 400m。"（已有，流式）
```

### 9.3 扩展 `QueryAgent.ExperienceFilter`：质量与氛围维度

现有 `ExperienceFilter` 只有 `category / maxDistanceMeters / openNow / soloScoreMin`。新增"氛围"维度，对应 `SoloScore.Breakdown` 的子项，让"环境好""安静""适合独处"这类自然语言可被结构化：

```swift
struct ExperienceFilter {
    var category: String?
    var maxDistanceMeters: Double?
    var openNow: Bool
    var soloScoreMin: Double?         // "高分" → 例如 8.0
    var ratingMin: Double?            // 新：来自 §4.3 的真实 provider rating
    // 新：氛围意图 → 映射到 Breakdown 子维度阈值
    var ambianceMin: Double?          // "环境不错" → ambianceFit
    var quietness: Bool?              // "安静" → 高 seatingFriendly + 低 staffPressure
    var soloFriendly: Bool?           // "适合一个人" → 高 soloPatronRatio + 高 soloPortioning
    var priceMax: Double?             // "便宜的" → priceLevel 上限
}
```

QueryAgent 的 prompt 增加这些维度的抽取示例，把模糊形容词锚定到可比较的阈值。

### 9.4 扩展工具 schema：让 explore 工具接质量维度 + 渐进

`explore_nearby` / `search_places` 当前只有坐标 + 半径。扩展：

```jsonc
// explore_nearby（扩展后）
{
  "latitude": number, "longitude": number,
  "categories": ["coffee","food", ...],   // 多类目（来自意图，§4.2）
  "solo_score_min": number,                // "高分/适合独处"
  "rating_min": number,                    // 真实评分门槛
  "ambiance_min": number,                  // "环境好"
  "progressive": boolean                   // true=走 5→10→25→100 阶梯（§4.1）
  // radius_meters 仍可显式指定，覆盖 progressive 的起始阶
}
```

新增两个工具：
- **`filter_visible`**：对**已标记**集合按质量维度过滤（不重新采集）。对应"把低于 8 分的去掉""只留环境好的"。纯本地、瞬时。
- **`expand_radius`**：主动触发**下一阶**半径扩展。对应"再远一点""扩大范围"。复用 §4.1 引擎的单步扩展。

ToolRouter 把这些工具的参数翻译成 `ExperienceFilter` + explore 调用，下发给 §4 引擎。

### 9.5 Agent 自主调度（关键）

agent 不是机械执行单个工具，而是**自主编排**多步以满足意图：

- "找高分咖啡馆"且当前可见集里**已有**几家咖啡 → 先 `filter_visible`（瞬时），不够再 `explore_nearby(progressive)` 补。
- 采集后若满足条件的太少 → agent 自主决定 `expand_radius` 或放宽阈值，并在回复里说明权衡（"8 分以上的只有 1 家，放宽到 7.5 分给你多找了 3 家"）。
- 多轮对话保留上下文（`AgentMessage.history`）："刚才那些里**最近的**" → 复用上次结果排序，不重新采集。
- 质量过滤所需的 rating/ambiance 数据由 §4.3 交叉编译保证 —— **agent 能力的上限 = 数据厚度**，所以 §4.3 是 §9 的前提。

### 9.6 体验细节

- **可见的"思考"**：agent 调度时进度胶囊显示当前动作（"在 5km 内找高分咖啡…" → "只有 2 家，扩到 10km…"），让自主决策透明。
- **回复即解释**：GuideAgent 的每句回复都说明"找到了什么 + 为什么这么做"，而非沉默执行。
- **语音/文字对等**：同一套工具与意图层，语音和打字走完全相同的 agent 管道（现有架构已如此）。
- **可纠偏**：用户说"不对，我要的是吃饭不是咖啡" → 新意图覆盖旧任务（任务取消 + 重启，§4.5）。

### 9.7 架构落点（在 §5 基础上追加）

| 层 | 改动 |
|----|------|
| `QueryAgent.ExperienceFilter` | 加 ratingMin / ambianceMin / quietness / soloFriendly / priceMax；prompt 补抽取示例 |
| `VoiceAgentToolRouter` | `explore_nearby`/`search_places` schema 接质量维度 + `progressive`；新增 `filter_visible`、`expand_radius` |
| `EnrichmentAgent` | `exploreProgressively` 接受 `ExperienceFilter`，把质量阈值用于"足够"判定与 top-N 排序 |
| `MapViewModel` | 暴露 `applyQualityFilter(_:)`（filter_visible 落点）与 `expandOneStage()`（expand_radius 落点） |
| `GuideAgent` | 回复模板覆盖"解释自主决策/权衡"的话术 |

## 10. 分期建议（可独立发布）

1. **M1 渐进半径**：5→10→25→100 阶梯 + 短路 + 扩展进度态 + 友好空态。（不依赖新数据源）
2. **M2 增量标记**：`onBatch` 增量发布 + annotation 淡入 + 半径圈 overlay。
3. **M3 交叉编译**：`CompiledPlace` + per-field 来源/可信度 + confidence 升级 + 详情展示来源。
4. **M4 Web 搜索源**：top-N 网络补充（配额敏感、可选）。
5. **M5 Agent 调度（§9）**：QueryAgent 质量维度 + 工具扩展 + filter_visible/expand_radius + 自主编排。依赖 M1–M3（尤其 M3 提供质量数据）。

> 推进顺序：M1+M2 解决"数据少/没过程感"；M3+M4 提升每条数据的"精确与厚度"；M5 把这一切变成用户可用自然语言主动驱动的 agent 能力 —— 这是终态体验。
