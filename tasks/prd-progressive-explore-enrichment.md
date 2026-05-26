# PRD: 渐进式 Explore + 多渠道交叉编译 + Agent 调度

> Status: Draft · Owner: iOS · 实现入口: `MapViewModel.exploreNearby` → `EnrichmentAgent`
> 设计原稿: `docs/PRD/progressive-explore-enrichment.md`（本 PRD 是其可实现化展开）
> Supersedes the deep-dive bits of `pro-radial-explore.md`

## 1. Introduction / Overview

把 Solo Compass 的 "Explore" 从「按钮触发的固定半径、一次性、浅数据」流程，升级为一个 **渐进、增量、可交叉验证、可被自然语言驱动** 的 agent 能力。

用户点 Explore（或选了"咖啡/美食"，或在对话/语音框说"找个高分咖啡馆"）后：

1. 从 **5km 内**按用户兴趣类目跨多个数据源采集；
2. **边搜边在地图上逐个标记**；
3. 对每条数据做 **跨渠道交叉编译**（OSM + Foursquare + Apple MapKit + 网络搜索）补全详情；
4. 若 5km 数据不足，**自动渐进扩展 10 → 25 → 100km** 直到足够；
5. 用户可用 **对话/语音** 主动调度（"环境好的""再远一点""只看 8 分以上"），agent 自主编排多步完成。

解决的核心问题：**数据少、没过程感、每条太浅、无法用自然语言主动探索**。

## 2. Goals

- 任意地点都能拿到结果：5km 不足时自动外扩，100km 仍无则给友好空态而非报错。
- 首批结果出现时间显著短于"全部完成时间"（增量标记）。
- 每条 experience 含被 ≥2 源交叉印证的 rating / 营业时间 / 价格 / 地址。
- 用户能用自然语言驱动 explore，并能多轮精炼（"刚才那些里最近的"）。
- agent 自主决策对用户透明（进度态 + 一句话解释做了什么 / 权衡了什么）。
- 配额安全：阶梯短路 + 缓存 + 静默降级，绝不因某个源失败阻塞主流程。

## 3. User Stories

> 标注 **[UI]** 的故事需在模拟器实跑验证（CLAUDE.md 要求：`#Preview` 不足）。

### M1 — 渐进半径阶梯

#### US-PE-01: 半径阶梯引擎

**Description:** 作为开发者，我需要一个阶梯式采集引擎，5→10→25→100km 逐阶扩展，每阶够了就停。

**Acceptance Criteria:**

- [ ] `EnrichmentAgent.exploreProgressively(center:filter:onBatch:)` 按 `[5_000,10_000,25_000,100_000]` 逐阶 collect
- [ ] 每阶产出累计"可用 experience" ≥ `enoughThreshold`（默认 8）即停止，不再打更远阶
- [ ] 每阶只采该阶新增环形（`prevRadius..<radius`），不重复内圈
- [ ] 跨阶按坐标 cell（4 位小数）+ osmId 双重去重
- [ ] 全阶跑完仍空 → 复用现有 cache 回退；无 cache → 友好空态（非 error）
- [ ] 阶梯/门槛走常量或 FeatureFlag，可灰度调参
- [ ] 新增单测覆盖：5km 够则不扩、不足则逐阶扩、去重正确
- [ ] `xcodebuild build` + 全测试通过

#### US-PE-02: 渐进进度态与扩展提示 [UI]

**Description:** 作为用户，当 app 往外扩范围时，我想知道它在做什么、扩到了多远。

**Acceptance Criteria:**

- [ ] `ExploreProgress` 新增 `scanning(radiusKm,channel)` / `expanding(toRadiusKm)`
- [ ] 跨阶时进度胶囊显示"附近较少 · 正在扩大到 25km"
- [ ] 5km 即满足时 toast **不**提扩展
- [ ] 扩展后 toast 注明最终半径（"为你扩大到 25km，找到 N 处"）
- [ ] 模拟器实跑：构造稀疏区域验证逐阶扩展文案
- [ ] Verify in simulator

#### US-PE-03: 友好空态与城市切换 [UI]

**Description:** 作为用户，100km 仍无数据时，我想看到一个有出路的提示而非冷冰冰的错误。

**Acceptance Criteria:**

- [ ] 100km 仍空 → 显示"这片区域我们还没有数据，换个城市试试？"
- [ ] 空态含城市切换入口（复用现有 browse-city）
- [ ] **不**出现技术性 error 文案
- [ ] Verify in simulator

### M2 — 增量地图标记

#### US-PE-04: 增量发布回调

**Description:** 作为开发者，我需要 agent 每完成一批就回调，而不是全部跑完才返回。

**Acceptance Criteria:**

- [ ] `exploreProgressively` 通过 `onBatch: ([Experience]) -> Void` 在每个"类目×阶"synthesis 完成后回调
- [ ] `MapViewModel` 在回调里增量 append 到 `visibleExperiences` 并去重
- [ ] 任务取消（用户中途改意图）时停止后续回调，无脏数据
- [ ] 单测：onBatch 被多次调用、累计集合与最终集合一致

#### US-PE-05: 标记逐个浮现动画 [UI]

**Description:** 作为用户，我想看到地图标记一个个淡入，而不是盯着转圈等到最后一次性出现。

**Acceptance Criteria:**

- [ ] 新增 annotation 用淡入 +（轻微）下落动画逐个出现（复用 `MarkerIconView`/annotation fade）
- [ ] 首批可见时间早于全部完成时间
- [ ] 已存在的标记不重绘/不闪烁
- [ ] Verify in simulator

#### US-PE-06: 半径圈可视化 overlay [UI]

**Description:** 作为用户，扩展范围时我想在地图上看到"正在往外找"的空间感。

**Acceptance Criteria:**

- [ ] 扩展时在地图画渐隐半径圈（对应当前阶 5/10/25/100km）
- [ ] 新点落在视野外时一次平滑 zoom-out 提示范围变大
- [ ] 圈在 explore 结束后淡出
- [ ] Verify in simulator

### M3 — 多渠道交叉编译

#### US-PE-07: CompiledPlace 中间模型与合并

**Description:** 作为开发者，我需要把同一地点在多源的碎片信息缝成一条带来源标签的记录。

**Acceptance Criteria:**

- [ ] 新增 `CompiledPlace`：聚合多源字段，每字段记录来源（osm/foursquare/mapkit/web）
- [ ] 同 cell 多源记录合并为一条；字段冲突按可信度取值（坐标/名 OSM 优先；rating/hours/price 取 Foursquare>MapKit；地址取 MapKit 结构化>反查）
- [ ] 缺失字段才向下个源要，不覆盖更权威源
- [ ] 扩展现有 `FoursquareService.enrichMerge` 或新建合并器，保留单测
- [ ] 单测：冲突取值、缺失回填、来源标签正确

#### US-PE-08: 多源置信度升级 [UI]

**Description:** 作为用户，被多个来源印证过的地点我想一眼看出更可信。

**Acceptance Criteria:**

- [ ] 被 ≥2 源印证的地点 `Confidence.level` + `basedOnCount` 提升
- [ ] 详情页显示"多来源印证"徽标 + 来源列表
- [ ] 详情页展示真实 rating / 营业时间 / 价格（来自 §M3 数据）
- [ ] Verify in simulator

#### US-PE-09: dataSources schema（如需持久化展示）

**Description:** 作为开发者，若要持久化并展示数据来源，需扩 schema 并保持 parity。

**Acceptance Criteria:**

- [ ] `ExperienceLocation` 加可选 `dataSources: [String]`（TS + Swift + SwiftData 同步）
- [ ] `pnpm parity:check` 全绿
- [ ] 旧行迁移安全（optional，轻量迁移）

### M4 — Web 搜索富集源

#### US-PE-10: top-N 网络补充源

**Description:** 作为用户，对排序靠前的好地方，我想看到一句网络上的真实补充（是否网红、是否适合独处）。

**Acceptance Criteria:**

- [ ] 新增 `WebSearchEnrichmentSource`，仅对排序后 top-N（默认 5）触发
- [ ] 走现有 AI 通道或轻量搜索 API；无 key/配额耗尽静默跳过，不阻塞
- [ ] 只补可交叉验证的客观信息，沿用反幻觉 prompt 边界（不编菜品/店主故事）
- [ ] FeatureFlag 控制开关，默认按配额策略
- [ ] 单测：无 key 时降级、top-N 截断正确

### M5 — Agent 调度（对话/语音驱动）

#### US-PE-11: QueryAgent 质量与氛围维度

**Description:** 作为用户，我想用"高分""环境好""安静""适合一个人""便宜"这类词来描述需求。

**Acceptance Criteria:**

- [ ] `ExperienceFilter` 新增 `ratingMin / ambianceMin / quietness / soloFriendly / priceMax`
- [ ] 映射：环境好→`ambianceFit`；安静→高`seatingFriendly`+低`staffPressure`；适合一个人→高`soloPatronRatio`+高`soloPortioning`
- [ ] QueryAgent prompt 补抽取示例，把形容词锚定到阈值
- [ ] 单测：典型语句→正确 filter（"安静能工作的咖啡馆"→coffee+quietness）

#### US-PE-12: explore 工具接质量维度 + 渐进

**Description:** 作为开发者，语音/对话的 explore 工具要能带质量门槛并触发渐进采集。

**Acceptance Criteria:**

- [ ] `explore_nearby`/`search_places` schema 增 `categories[] / solo_score_min / rating_min / ambiance_min / progressive`
- [ ] ToolRouter 把工具参数翻译为 `ExperienceFilter` 下发给 `exploreProgressively`
- [ ] `progressive:true` 走阶梯；显式 radius 覆盖起始阶
- [ ] 单测：工具参数→filter 映射正确

#### US-PE-13: filter_visible 与 expand_radius 工具

**Description:** 作为用户，我想说"把低于 8 分的去掉""再远一点"。

**Acceptance Criteria:**

- [ ] 新增 `filter_visible`：对已标记集合按质量维度瞬时过滤（不重采）
- [ ] 新增 `expand_radius`：主动触发下一阶半径扩展（复用 M1 引擎单步）
- [ ] `MapViewModel` 暴露 `applyQualityFilter(_:)` 与 `expandOneStage()` 落点
- [ ] 单测：filter_visible 不触发网络；expand_radius 推进一阶

#### US-PE-14: Agent 自主多步编排 [UI]

**Description:** 作为用户，我说"找高分咖啡馆"，agent 应自主决定先过滤已有还是去采集、不够就扩或放宽，并解释。

**Acceptance Criteria:**

- [ ] 已有同类可见集 → 先 `filter_visible`，不足再 `explore_nearby(progressive)`
- [ ] 满足条件太少 → agent 自主 `expand_radius` 或放宽阈值，GuideAgent 回复解释权衡
- [ ] 调度过程进度胶囊显示当前动作（"只有 2 家，扩到 10km…"）
- [ ] Verify in simulator（语音 + 文字两条路径）

#### US-PE-15: 多轮对话上下文精炼 [UI]

**Description:** 作为用户，我想说"刚才那些里最近的""再便宜点"，基于上一轮结果精炼而不重新采集。

**Acceptance Criteria:**

- [ ] 复用 `AgentMessage.history`，对上一轮结果集做排序/过滤而非重采
- [ ] "最近的"按距离重排；"再便宜点"收紧 priceMax；"换成吃饭"覆盖意图重启
- [ ] 指代消解："第二个""那家"映射到可见集对应项
- [ ] Verify in simulator

#### US-PE-16: 主动推荐与理由 [UI]

**Description:** 作为用户，我希望 agent 主动给一条最佳推荐并说明为什么适合此刻的我。

**Acceptance Criteria:**

- [ ] GetRecommendation 意图下，agent 结合时间/位置/偏好选一条最佳，GuideAgent 给"为什么适合你"的一句话理由
- [ ] 理由引用真实信号（rating/营业中/适合独处），不空泛
- [ ] 被推荐项在地图上高亮
- [ ] Verify in simulator

#### US-PE-17: 行程 / 收藏编排 [UI]

**Description:** 作为用户，我想说"把这几个排个下午的路线"，让 agent 排出可步行的顺序。

**Acceptance Criteria:**

- [ ] agent 把选中/收藏的多个地点按距离 + 营业时间排成有序序列
- [ ] 地图上以连线/编号展示顺序
- [ ] 序列冲突（如某点已打烊）时给出提示与替代
- [ ] Verify in simulator

#### US-PE-18: 实时营业 / 此刻可去 [UI]

**Description:** 作为用户，我想说"现在还开着的"，只看此刻可去的地方。

**Acceptance Criteria:**

- [ ] 结合 `openingHours`（M3）+ 当前本地时间过滤"此刻营业"
- [ ] 营业状态在卡片/详情显示（营业中 / 即将打烊 / 已关）
- [ ] 营业时间缺失的地点标注"营业时间未知"而非假设开着
- [ ] Verify in simulator

## 4. Functional Requirements

- FR-1: `exploreProgressively` 按 5/10/25/100km 阶梯采集，累计可用数 ≥ 阈值即短路。
- FR-2: 每阶只采新增环形区域；跨阶按 cell+osmId 去重。
- FR-3: 采集意图 = `selectedCategory` ?? `preferredCategories` ?? 全部类目。
- FR-4: 每个"类目×阶"synthesis 完成即通过 `onBatch` 增量回调，`MapViewModel` 增量更新 `visibleExperiences`。
- FR-5: 新增标记淡入浮现；扩展时画渐隐半径圈。
- FR-6: 多源信息合并为 `CompiledPlace`，按可信度取值、保留来源标签。
- FR-7: ≥2 源印证 → 提升 confidence + 详情显示来源。
- FR-8: Web 搜索源仅对 top-N 触发，配额敏感、可静默降级。
- FR-9: `ExperienceFilter` 支持 rating/ambiance/quietness/soloFriendly/priceMax。
- FR-10: explore 工具接质量维度 + `progressive`；新增 `filter_visible`、`expand_radius` 工具。
- FR-11: agent 自主编排多步（先过滤→再采集→不够则扩/放宽），并解释决策。
- FR-12: 多轮对话基于 history 精炼上一轮结果，不重采；支持指代消解。
- FR-13: 主动推荐给一条最佳 + 真实理由；高亮于地图。
- FR-14: 行程编排按距离+营业时间排序，地图连线展示。
- FR-15: "此刻可去"按 openingHours + 本地时间过滤，缺失时标"未知"不假设。
- FR-16: 任意外部源失败/无 key/配额耗尽 → 静默降级，主流程不阻塞；全程可飞行模式回退缓存。
- FR-17: 用户中途改意图/拖图 → 取消当前任务、按新意图重启，无脏数据。
- FR-18: 半径/阈值/top-N/各开关可配（常量或 FeatureFlag）以便灰度。

## 5. Non-Goals (Out of Scope)

- 不做付费/订阅门槛变更（沿用现有 paywall 逻辑，不在本 PRD 调整）。
- 不引入需要后端常驻服务的实时数据（营业状态来自 provider 字段，不做实时爬取/抓店）。
- 不做多用户协作行程（行程编排是单人本地，不含共享/同步到他人）。
- 不编造任何无法跨源验证的细节（菜品、店主故事、座位）—— 严守反幻觉边界。
- 不做离线地图瓦片下载；离线仅复用已缓存的 explore 结果。
- 不在本 PRD 重构语音识别/ASR（沿用现有 `VoiceService`）。

## 6. Design Considerations

- 复用：`MarkerIconView`、annotation fade、`ExploreProgressBar`、browse-city 空态入口、`Intent→Query→Guide` 流水线、`VoiceAgentToolRouter`。
- 进度态文案分阶段：scanning / compiling / expanding / synthesizing，胶囊实时反映半径 + 已找到数。
- "首批最快"：5km + 用户主类目 优先跑、优先标。
- agent 决策透明：每步在胶囊显示动作，GuideAgent 回复解释做了什么/权衡了什么。
- 语音与文字走完全相同的 agent 管道（现有架构已如此）。

## 7. Technical Considerations

- **依赖链**：M5 的质量过滤依赖 M3 的真实数据；M3 依赖 M1（采集引擎）。推进顺序 M1→M2→M3→M4→M5。
- 数据源：Overpass / Foursquare / MapKit 已可按类目+半径采；环形采集（`prevR..<R`）需补。
- 并发：每阶多源并发；synthesis 按"类目×阶"小批（≤8）便于增量发布 + 单次便宜。
- 缓存：复用 30 天 synthesis 缓存 + 跨阶去重避免重复 AI 花费。
- 取消：`Task` cancellation 贯穿引擎，意图切换即时中断。
- Schema：`ExperienceLocation` 已有 rating/openingHours/priceLevel/website/phone；如加 `dataSources` 需 TS+Swift+SwiftData parity。
- Kill switch：`FF_DEEP_DIVE_ENRICHMENT`（已存在）+ 渐进/agent 子能力各自 flag，便于灰度与回退。

## 8. Success Metrics

- 稀疏区域 explore 成功率（拿到 ≥1 结果）从"3km 即报错"提升到接近 100%（100km 覆盖）。
- 首批标记出现时间 < 全流程完成时间的 50%。
- 含真实 rating/营业时间的 experience 占比显著上升（M3 后）。
- 自然语言 explore 的意图满足率（用户无需再手动调过滤）。
- 因外部源失败导致的"硬报错"归零（全部降级为软提示/缓存）。

## 9. Open Questions

- `enoughThreshold` 默认 8 是否合适？是否随类目数动态调整（选了 3 类时门槛更高）？
- Web 搜索源用现有 AI 通道还是独立搜索 API？配额与成本如何分摊？
- 行程编排是否需要考虑交通方式（步行 vs 公交）还是 v1 只做步行序列？
- "此刻可去"在营业时间缺失普遍的地区，是否需要一个"可能营业"的中间态？
- 多轮上下文保留多少轮 / 多长时间过期，避免陈旧结果误导？
- 质量维度阈值（如"高分"= 8.0）是否暴露给用户微调，还是 agent 内部固定？
