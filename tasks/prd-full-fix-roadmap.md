# PRD: Full Fix Roadmap — Solo Compass iOS

| 字段         | 值                                                                       |
| ------------ | ------------------------------------------------------------------------ |
| 版本         | v1.0                                                                     |
| 状态         | 草稿 → 待评审                                                            |
| 创建日期     | 2026-05-29                                                               |
| 基线         | `main @ 0252ce3` · `feat/comparecanvas-verified-badge-3-tier @ b225080`  |
| 依据         | `docs/EVAL_REPORT.md` (v2) + 6 个 agent 测评                             |
| 范围         | apps/ios/SoloCompass（**只** iOS；Web / Bot / Edge Function 不在本 PRD） |
| 预计交付窗口 | 4 周（10 个 PR P0 → 5 个 PR P1 → 3 个 PR P2 → 3 个 PR 路线图）           |
| 超集替代     | [tasks/prd-p0-fix-batch.md](./prd-p0-fix-batch.md) 是本文件的 P0 子集    |

---

## 0. 谁该读这份文档

| 角色                      | 读哪一段                                        |
| ------------------------- | ----------------------------------------------- |
| Tech Lead / PM            | § 1 / § 2 / § 8 / § 9                           |
| Reviewer                  | § 5 Non-Goals · § 3 US 列表中你负责的 US        |
| Implementer（人或 agent） | 你认领的 US 全文 + § 7 Technical Considerations |
| QA / 真机验收人           | 每个 US 的 Acceptance Criteria 第 3-5 项        |

---

## 1. Introduction / Overview

2026-05-28/29 两天对 Solo Compass iOS 做了一次**深度多 agent 评测**：

| Agent                 | 类型             | 状态          | 产出条目                                     |
| --------------------- | ---------------- | ------------- | -------------------------------------------- |
| code-explorer         | 源码结构         | ✅            | 文件清单 / Route+Companion 现状              |
| code-reviewer         | 源码质量         | ✅            | 11 条（1 Critical + 5 High + 3 Medium）      |
| a11y-architect        | WCAG 2.2         | ✅            | hit-target / live-region / Dynamic Type 缺口 |
| performance-optimizer | 性能热点         | ✅            | AnyView / markerState / cache 缺口           |
| silent-failure-hunter | 错误吞掉         | ✅            | SyncService / LocationService / AI fallback  |
| e2e-runner v1         | 真机模拟         | ❌ stall 600s | 0 截图                                       |
| e2e-runner v2         | 真机模拟（轻量） | ✅            | 5 张截图 + 6 条真机视觉问题                  |

**6 个 agent + 1 张评测表**汇总出 **58 条 finding**：

- **13 P0**（10 EVAL_REPORT 原始 + 3 v2 真机新发现，会真实造成用户损失或 crash）
- **29 P1**（27 EVAL_REPORT 原始 + 2 v2 真机新发现，影响完整性/可用性）
- **16 P2**（15 EVAL_REPORT 原始 + 1 v2 真机新发现，体验打磨）

本 PRD 把 58 条全部一对一拆成 **58 个 user story**（命名：US-P0-001..013 / US-P1-001..029 / US-P2-001..016 / US-V-001..006，V 表示真机发现，与 P0/P1/P2 交叉编号），按主题分组放进 22 个候选 PR。每个 US 都符合**严格四重验收**：

1. **iPhone 17 Pro Simulator 真机手测**（截图前后对比，存 PR description）
2. **XCTest 自动化覆盖**（每个 fix 加 1+ 用例，回归率 0）
3. **VoiceOver 手动验收**（a11y 类 US 必须）
4. **Sentry 上报证据**（静默失败 / 错误传播类必须）

---

## 2. Goals

### 2.1 可观测目标（4 周内达成）

- 仓内 `route.companion!` force-unwrap 数：**6 → 0**
- 仓内 `Services/SyncService.swift` `try?` encode 数：**1 → 0**
- 仓内硬编码 "results" / 英文用户文案数：**≥6 → 0**
- iOS test target 函数数：**~489 → ≥547**（每条 US 至少 +1 test = +58 但有合并）
- CompassMapView 30s pan/zoom main-thread CPU time：**≤ baseline × 0.8**
- Sentry 月度 companion 相关 crash：**unknown → < 1**
- Sentry 月度 skeleton_fallback 上报：**0 → > 0**（验证机制有效）
- VoiceOver 用户完成"申请加入路线"闭环：**未测 → 100%**
- CompareCanvas 设计稿对齐度：**80% → 100%**（剩余 stop-strip / RecruitingModule 三档强度 / CT token 推广）

### 2.2 不可观测但同等重要

- **冷启动一致性**：header city 标签 / 地图 region / 抽屉 nearby 数据三者永远同步（V2 / V4）
- **i18n 完整性**：任意 locale 下不再出现半翻译界面（V3 + 10 处硬编码 strings）
- **架构债务可见**：6 个超 800 行的文件全部分拆，单文件 ≤ 800 行硬约束被尊重

---

## 3. User Stories

### 命名约定

`US-{优先级}-{序号}` · 优先级 ∈ `{P0, P1, P2, V, A}` ·

- `P0..P2`: EVAL_REPORT 已分级
- `V`: v2 e2e-runner 真机发现
- `A`: 架构重构 / 设计稿对齐路线图

每个 US 用统一模板：

```
### US-Px-NNN: 标题
**Description:** As a {role}, I want {capability} so that {benefit}.
**Affected:** file:line · file:line
**Acceptance Criteria:**
- [ ] 具体可验证条目
- [ ] iPhone 17 Pro Simulator 手测路径（截图存档）
- [ ] XCTest 用例名（视类型）
- [ ] VoiceOver / Sentry 验收（视类型）
- [ ] Typecheck / lint 通过
```

---

### 3.1 P0 — 13 个（先做）

#### US-P0-001: 消除 `route.companion!` force-unwrap

**Description:** As an iOS engineer, I want all 6 `route.companion!` force-unwrap sites replaced with safe binding so the app never crashes when companion data is unexpectedly nil.
**Affected:** `Services/LocalRouteCompanionRemote.swift:38, 119, 126, 137` + `Views/Companion/MyRequestsListView.swift:182` + `Views/Companion/ApprovalQueueView.swift:311`
**Acceptance Criteria:**

- [ ] grep `\bcompanion!` 在非 Tests Swift 文件返回 0 行
- [ ] 每处改为 `guard var companion = updated.companion else { ... }` 模式
- [ ] 新增 `RouteCompanionForceUnwrapTests`：companion == nil 入参 → no-op 不 crash
- [ ] Simulator: 跑通"申请加入 → 主理审批 → 撤回"闭环，截图存档
- [ ] Sentry: 兜底 no-op 触发上报 warning
- [ ] Typecheck / lint 通过

#### US-P0-002: SyncService.enqueue 错误传播

**Description:** As an end user, I want my completions, favorites, and route join requests to never silently disappear so my actions are durable across devices.
**Affected:** `Services/SyncService.swift:95-98`
**Acceptance Criteria:**

- [ ] `try?` encode → `do { try } catch { SentryService.capture(...) }`
- [ ] 新增 `SyncServiceEnqueueTests`：注入故意 encode 失败 → 验证 Sentry mock 收到
- [ ] Simulator: 离线 → 完成 experience → 重启 → sync queue 恢复，截图
- [ ] Sentry 后台见至少 1 条 `SyncService.enqueue` 上报样本
- [ ] Typecheck / lint 通过

#### US-P0-003: AI fallback 用户可见标识

**Description:** As an end user, I want a clear visual indicator when an experience card is showing skeleton data instead of real AI insight so I don't mistake placeholder text for personalized recommendation.
**Affected:** `Services/AIService.swift:765-768, 781-791` + `Views/Experience/ExperienceCardView.swift`
**Acceptance Criteria:**

- [ ] `AIService.lastSynthesisQuality: AISynthesisQuality { case real, skeleton, cached }`
- [ ] ExperienceCard 在 skeleton 下渲染 `SkeletonBadgeView` 角标（CT.fgMuted 色，capsule，文案待 § 9 OQ-2 决定）
- [ ] 真实 / cached 不渲染角标
- [ ] 新增 `AISkeletonSurfaceTests`：注入 skeleton → 验证渲染 + a11y label
- [ ] Simulator: 留空 ANTHROPIC_API_KEY 跑 explore，截图前后对比
- [ ] VoiceOver: 角标 accessibilityLabel 正确朗读
- [ ] Sentry: skeleton fallback 触发上报 `AIService.skeleton_fallback`
- [ ] Typecheck / lint 通过

#### US-P0-004: 移除 CompassMapView.body 的 `AnyView`

**Description:** As an iOS engineer, I want the root `mapContent` to return `some View` directly so SwiftUI can do incremental diffing on the app's heaviest view.
**Affected:** `Views/Map/CompassMapView.swift:76`
**Acceptance Criteria:**

- [ ] `body` 不再包 `AnyView(...)`，必要时加 `@ViewBuilder`
- [ ] 新增 `CompassMapViewBodyTypeTests`：`String(describing: type(of:))` 断言不含 `AnyView`
- [ ] Simulator: Instruments Time Profiler 30s pan/zoom，main-thread CPU ≤ baseline × 0.8（PR description 贴对比截图）
- [ ] 既有 snapshot/unit test 全部通过
- [ ] Typecheck / lint 通过

#### US-P0-005: BottomInfoSheet drag handle hit target ≥ 44pt

**Description:** As a VoiceOver / Switch Control user, I want the bottom sheet drag handle to have a 44×44pt minimum hit area so I can switch detent levels.
**Affected:** `Views/Map/BottomInfoSheet.swift:127-131`
**Acceptance Criteria:**

- [ ] handle 区域 `.frame(minWidth: 60, minHeight: 44).contentShape(Rectangle())`，视觉 pill 仍 36×4
- [ ] 加 `.accessibilityLabel("Sheet handle")` + `.accessibilityAdjustableAction` cycle peek/mid/full
- [ ] 新增 `BottomInfoSheetHandleHitTargetTests`：snapshot 验证 hit area ≥ 44
- [ ] Simulator + Accessibility Inspector：手测 hit area，截图
- [ ] VoiceOver: 焦点能落 handle，三态 cycle 可用
- [ ] Typecheck / lint 通过

#### US-P0-006: 硬编码 "results" 与 voice toast live region

**Description:** As a VoiceOver user, I want hardcoded English strings replaced with localized ones and voice processing toasts to announce themselves so I stay in sync with app state.
**Affected:** `Views/Filter/FilterBarView.swift:180, 230, 264, 301` + `Views/Map/CompassMapView.swift:868-885`
**Acceptance Criteria:**

- [ ] 4 处 "results" → `NSLocalizedString("filter.results.count", ...)`
- [ ] `Localizable.strings` en + zh-Hans 双语对齐，`StringsParityTests` 过
- [ ] voice.processing toast 加 `.accessibilityElement().accessibilityAddTraits(.updatesFrequently)` + `UIAccessibility.post(.announcement, ...)`
- [ ] 新增 `FilterBarLocalizationTests`：grep "results" 编译后字符串不出现
- [ ] Simulator: 切 locale en ↔ zh-Hans，filter 文案对齐
- [ ] VoiceOver: voice 查询触发后能朗读"思考中: <query>"
- [ ] Typecheck / lint 通过

#### US-P0-007: Companion layer toggle nil 占位决策

**Description:** As a product owner, I want the long-unimplemented companion layer toggle either backed by real data or hidden so users don't click a dead button.
**Affected:** `Views/Map/CompassMapView.swift:541` (`nearbyCells` 永远返回 nil)
**Acceptance Criteria:**

- [ ] 产品方做决策（§ 9 OQ-1）：A) 隐藏 toggle / B) 加 "Coming soon" hint / C) 真接 backend
- [ ] 若 A：`.hidden()` 包住 button + tests skip 相关 UI test
- [ ] 若 B：banner / toast 提示 "数据准备中"
- [ ] 若 C：另起 backend PRD（不在本 PRD）
- [ ] Simulator: 截图验证选定方案
- [ ] Typecheck / lint 通过

#### US-V-001: Onboarding 文案截断修复

**Description:** As a first-time user, I want the privacy onboarding sheet to show the full subtitle so I understand what services the app calls.
**Affected:** `Views/Onboarding/PrivacyAcknowledgementSheet.swift`（grep "talks to two services" 定位）
**Acceptance Criteria:**

- [ ] Sheet height 自适应，subtitle 完整显示 "...on your behalf"
- [ ] 或 subtitle 改为 multi-line + `.fixedSize(horizontal: false, vertical: true)`
- [ ] 新增 `PrivacyAcknowledgementSheetSnapshotTest`：snapshot 含完整 subtitle
- [ ] Simulator: 冷启动截图（v2 agent 的 01-launch.png 作为 before）
- [ ] Dynamic Type AX5 下也不截断
- [ ] Typecheck / lint 通过

#### US-V-002: City 标签与地图 region 同步

**Description:** As a user, I want the city header label and the map's rendered region to always agree so I'm never confused about where I am.
**Affected:** `ViewModels/MapViewModel.swift` `selectedCity` ↔ `defaultCenterForSelectedCity` 接线
**Acceptance Criteria:**

- [ ] 冷启动后 `selectedCity` 与 `mapCameraPosition` 一致（首次 didSet 必触发 region 切换）
- [ ] 新增 `MapViewModelCityRegionSyncTests`：切城市 → 验证 cameraPosition 同步更新
- [ ] Simulator: 冷启动 + 切 3 个城市，header 与地图一致，截图
- [ ] VoiceOver: city pill `accessibilityValue` 反映当前 selectedCity
- [ ] Typecheck / lint 通过

#### US-V-003: 半翻译界面修复（底部抽屉与 filter bar）

**Description:** As a zh-Hans user, I want the entire bottom sheet UI in Chinese so I don't see English copy bleeding through.
**Affected:** `Views/Map/BottomInfoSheet.swift` "Good spots for right now" + 其他可能漏走 NSLocalizedString 的位置
**Acceptance Criteria:**

- [ ] grep 整个 Views/ 找 `Text("[A-Z]` 模式，确认无未本地化的 user-visible 字符串
- [ ] 新增 `LocalizationCoverageTest`：扫描 Views 目录，硬编码英文文案返回 0
- [ ] Simulator: 切到 zh-Hans 跑 explore，无半翻译，截图前后对比
- [ ] StringsParityTests 通过
- [ ] Typecheck / lint 通过

#### US-P0-008: SwiftData @Query KeyPath 警告清零

**Description:** As an iOS engineer, I want SwiftData @Query Sendable warnings (Swift 6 mode errors) resolved so we can opt into strict concurrency cleanly.
**Affected:** `Views/Settings/SettingsView.swift:897` + 其他 `@Query(...)` 用 `KeyPath` 排序的位置
**Acceptance Criteria:**

- [ ] `KeyPath` 改为 `SortDescriptor(...)` 显式或包 `@Sendable` closure
- [ ] 新增 `SettingsViewQuerySortTest`：断言查询返回顺序正确
- [ ] Simulator: 设置页打开 + 重新加载，无 print 警告
- [ ] xcodebuild 编译输出该 warning 数量 = 0
- [ ] Typecheck / lint 通过

#### US-P0-009: ChatSheet voiceService Sendable 警告

**Description:** As an iOS engineer, I want main-actor isolated voiceService usage to not race so strict concurrency holds.
**Affected:** `Views/Chat/ChatSheet.swift:621`
**Acceptance Criteria:**

- [ ] `VoiceService` 加 `@MainActor` 或 `requestPermission()` 加 `@MainActor`
- [ ] 新增 `VoiceServiceActorIsolationTest`：断言 `requestPermission` 在 main actor 调用
- [ ] Simulator: 触发 voice 录音，无 crash
- [ ] xcodebuild warning 数 = 0
- [ ] Typecheck / lint 通过

#### US-P0-010: FavoritesListView BounceSymbolEffect iOS 18 守卫

**Description:** As an iOS engineer, I want the iOS 18 API gated by `#available` so we don't ship a Swift 6 error in CI.
**Affected:** `Views/Shared/FavoritesListView.swift:327`
**Acceptance Criteria:**

- [ ] 加 `if #available(iOS 18, *)` 守卫
- [ ] 新增 `FavoritesBounceAvailabilityTest`：snapshot 在 iOS 17 与 18 都过
- [ ] Simulator (iOS 17 + iOS 26): 收藏图标 bounce 正常
- [ ] xcodebuild warning 数 = 0
- [ ] Typecheck / lint 通过

---

### 3.2 P1 — 29 个（次做，分组）

#### 组 P1-A · 真机相关（V4 + V5 + 4 条 EVAL_REPORT）

##### US-V-004: 冷启动空状态数据不一致诊断

**Description:** As a user, I want the home screen to show experiences for my selected city on cold start so the app doesn't feel broken.
**Affected:** `Services/ExperienceService.swift` seed import + `MapViewModel.loadNearbyExperiences`
**Acceptance Criteria:**

- [ ] 排查冷启动 → seed 装载完成 → 切城市 → loadNearbyExperiences 流程，定位"5km/25km 都 empty"根因
- [ ] 修复（可能是 distance filter bug / SQLite seed 没装 / userLocation 默认 SF 不会跟随 selectedCity）
- [ ] 新增 `ColdStartExperienceLoadTests`：冷启动 + 选 Chiang Mai → ≥ 1 个 experience
- [ ] Simulator: 冷启动跑 5 个种子城市，截图每城市 nearby count
- [ ] Sentry: 任何路径下"selectedCity 与 nearby 数量长期 0"上报
- [ ] Typecheck / lint 通过

##### US-V-005: 顶部 filter chip 溢出 affordance

**Description:** As a user, I want a visual hint that filter chips scroll horizontally so I can discover all categories.
**Affected:** `Views/Filter/FilterBarView.swift` 顶部 ScrollView
**Acceptance Criteria:**

- [ ] 右边缘加 fade gradient mask 或加 chevron icon
- [ ] 新增 `FilterBarScrollAffordanceTest`：snapshot 验证右边 mask 渲染
- [ ] Simulator: 视觉对比有/无 mask
- [ ] VoiceOver: scroll 到末尾时 chip 焦点能到最后一个
- [ ] Typecheck / lint 通过

##### US-P1-001: markerState 每帧单次调用

**Description:** As an iOS engineer, I want `markerState(for:)` called once per ForEach iteration.
**Affected:** `Views/Map/CompassMapView.swift:612-616`
**Acceptance Criteria:**

- [ ] ForEach body 顶部 `let state = viewModel.markerState(for: exp)`
- [ ] 新增 `MarkerStatePerformanceTest`：100 experience × 1000 次循环 p95 ↓ ≥ 40%
- [ ] Simulator: explore + filter 切换，肉眼无差
- [ ] 既有 `MarkerIconViewTests` 通过
- [ ] Typecheck / lint 通过

##### US-P1-002: availableCities 缓存

**Description:** As an iOS engineer, I want `MapViewModel.availableCities` cached.
**Affected:** `ViewModels/MapViewModel.swift:187-215`
**Acceptance Criteria:**

- [ ] `@ObservationIgnored private var _cachedCities: [CityInfo]?`
- [ ] `allExperiences` / `selectedCity` 变化时 invalidate
- [ ] 新增 `MapViewModelCityCacheTests`：fresh / hit / invalidation 三路径
- [ ] Simulator: 切 4 城市行为一致
- [ ] Typecheck / lint 通过

##### US-P1-003: nowCount 缓存

**Description:** As an iOS engineer, I want `nowCount` recomputed only when `visibleExperiences` changes.
**Affected:** `ViewModels/MapViewModel.swift:298` + `updateBottomInfo()` 720/736
**Acceptance Criteria:**

- [ ] `_nowCount: Int` + 统一在 loadNearbyExperiences / refreshForLocation / updateBottomInfo 末尾更新
- [ ] `visibleExperiences.filter { $0.isBestNow() }` 出现次数 3 → ≤ 1
- [ ] 新增 `NowCountCacheTests`
- [ ] Simulator: filter "Now" 数字与地图标记一致
- [ ] Typecheck / lint 通过

##### US-P1-004: FilterBar pills + ExperienceCard heart + Banner X 三处 hit-target

**Description:** As a VoiceOver / Switch Control user, I want all interactive controls to meet 44pt minimum.
**Affected:** `Views/Filter/FilterBarView.swift:240` (36×36) · `Views/Experience/ExperienceCardView.swift:175` (32×32) · `Views/Map/CompassMapView.swift:1124` (banner X)
**Acceptance Criteria:**

- [ ] 三处 `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`
- [ ] 视觉尺寸不变
- [ ] 新增 `HitTargetSizeTests`
- [ ] Simulator: filter + 收藏 + 关 banner 全跑通
- [ ] VoiceOver: 三处都能 focus
- [ ] Typecheck / lint 通过

#### 组 P1-B · 启动性能与状态

##### US-P1-005: SoloCompassApp.onAppear 异步化

**Description:** As a user, I want cold start TTI to not block on serial main-thread init so the map appears within 500ms.
**Affected:** `App/SoloCompassApp.swift:43-73`
**Acceptance Criteria:**

- [ ] `pruneStaleCheckIns` / `attachRepository` / `RouteStore.importSeedIfNeeded` / `UserDirectory.loadIfNeeded` 改 `Task { ... }` 并行
- [ ] `subscriptionService.loadProducts` → `refreshEntitlement` 链断开为独立 Task
- [ ] 新增 `AppLaunchPerformanceTest`：模拟 TTI ≤ baseline × 0.5
- [ ] Simulator: Instruments 录 TTI 对比，PR description 贴截图
- [ ] Typecheck / lint 通过

##### US-P1-006: CompassMapView ViewModel 非 Optional 化

**Description:** As an iOS engineer, I want `viewModel` initialized eagerly so writes between launch and onAppear don't silently drop.
**Affected:** `Views/Map/CompassMapView.swift:1458`
**Acceptance Criteria:**

- [ ] `viewModel` 改为 `@State private var viewModel = MapViewModel(...)` 或 environment injection
- [ ] 删除 `.onAppear` 中的创建逻辑
- [ ] 新增 `MapViewModelEagerInitTest`：app launch 后立刻能 read viewModel.allExperiences
- [ ] Simulator: 冷启动无 ProgressView 闪烁
- [ ] Typecheck / lint 通过

##### US-P1-007: City pill 与 filter bar 视觉层级冲突

**Description:** As a user, I want city selector and filter bar to not visually fight for attention in the top-left.
**Affected:** `Views/Map/CompassMapView.swift` 顶部 overlay 布局
**Acceptance Criteria:**

- [ ] city pill 移至 navigation bar 区或与 filter bar 垂直分离
- [ ] 新增 `TopOverlayLayoutTest`：snapshot 验证不重叠
- [ ] Simulator: 视觉对比
- [ ] VoiceOver: 焦点顺序合理（city → filter → ...）
- [ ] Typecheck / lint 通过

#### 组 P1-C · Experience 详情

##### US-P1-008: BestNowBadge 共享 TimelineView

**Description:** As an iOS engineer, I want a single periodic timer feeding all BestNowBadge instances instead of 20+ concurrent timelines.
**Affected:** `Views/Experience/ExperienceCardView.swift:267-289`
**Acceptance Criteria:**

- [ ] 提取 `BestNowClock: ObservableObject` 单例，每 60s tick
- [ ] BestNowBadge 监听 clock 而非自带 TimelineView
- [ ] 新增 `BestNowBadgeClockTest`：100 badge 共用 1 个 clock，main-thread overhead ↓
- [ ] Simulator: explore 20+ best-now，无可见卡顿
- [ ] Typecheck / lint 通过

##### US-P1-009: Solo Score 雷达图 a11y label

**Description:** As a VoiceOver user, I want the radar chart's 6 dimensions read out loud.
**Affected:** `Views/Shared/SoloScoreRadarChart.swift`
**Acceptance Criteria:**

- [ ] `accessibilityElement(children: .combine)` + `accessibilityLabel` 含 6 维度数值
- [ ] `accessibilityValue` 反映 overall 分数
- [ ] 新增 `SoloScoreRadarA11yTest`：assert accessibilityLabel non-empty
- [ ] VoiceOver: 焦点能落 chart，朗读"安全 7.5, 餐饮 8.0, ..."
- [ ] Typecheck / lint 通过

##### US-P1-010: "Ask Solo" Pro-gate 与 Paywall 路径连接

**Description:** As a free-tier user, I want clicking a gated feature to take me to the paywall, not a dead toast.
**Affected:** `Views/Experience/ExperienceDetailView.swift` "Ask Solo" CTA
**Acceptance Criteria:**

- [ ] gated 状态点击 → present `PaywallSheet`
- [ ] 新增 `AskSoloPaywallNavigationTest`：tap → sheet 出现
- [ ] Simulator: 未付费跑 explore + Ask Solo，截图 paywall
- [ ] Typecheck / lint 通过

#### 组 P1-D · 错误传播与可见性

##### US-P1-011: LocationService.lastError 暴露到 UI

**Description:** As a user, I want GPS errors surfaced so I understand why the map defaulted to Chiang Mai.
**Affected:** `Services/LocationService.swift` `lastError` + `MapViewModel`
**Acceptance Criteria:**

- [ ] MapViewModel 监听 `lastError`，渲染 dismissible banner "GPS unavailable, showing default region"
- [ ] 新增 `LocationErrorSurfaceTests`
- [ ] Simulator: 设备 Location → None，banner 出现
- [ ] VoiceOver: banner 朗读
- [ ] Sentry: lastError != nil 上报 warning
- [ ] Typecheck / lint 通过

##### US-P1-012: Voice 录音中途错误 UI 反馈

**Description:** As a user, I want voice recording interruptions shown in UI instead of silently stopping.
**Affected:** `Views/Chat/ChatSheet.swift:636-638`
**Acceptance Criteria:**

- [ ] catch 不再空，弹 toast "Recording interrupted: <reason>"
- [ ] 新增 `VoiceInterruptionToastTest`
- [ ] Simulator: 录音中拒权限 → toast 出现
- [ ] VoiceOver: toast 朗读
- [ ] Typecheck / lint 通过

##### US-P1-013: Filter chip 选中态对比度修复

**Description:** As a low-vision user, I want filter chip text to meet WCAG 4.5:1 contrast.
**Affected:** `Views/Filter/FilterBarView.swift` selected state `#D4A843` on 白
**Acceptance Criteria:**

- [ ] 文字色调暗，或背景填充改深色（CT.accent on white text 对比 ≥ 7:1）
- [ ] 新增 `FilterChipContrastTest`：算 WCAG 对比度断言 ≥ 4.5
- [ ] Simulator: 视觉对比
- [ ] Typecheck / lint 通过

##### US-P1-014: 抽屉高度 Dynamic Type 缩放

**Description:** As an AX5 (largest accessibility) Dynamic Type user, I want sheet detent heights to scale so content doesn't overflow.
**Affected:** `Views/Map/BottomInfoSheet.swift` peek 170 / mid 500 / full 800
**Acceptance Criteria:**

- [ ] 三档高度乘 `UIFontMetrics.default.scaledValue(for:)`
- [ ] 新增 `BottomSheetDetentDynamicTypeTest`：AX5 下三档可读
- [ ] Simulator: 切到 AX5 截图三档
- [ ] Typecheck / lint 通过

##### US-P1-015: Sort 按钮 accessibilityValue

**Description:** As a VoiceOver user, I want the sort button to announce current sort mode.
**Affected:** `Views/Map/BottomInfoSheet.swift:208`
**Acceptance Criteria:**

- [ ] `.accessibilityValue("Sorted by \(currentMode)")` 动态
- [ ] 新增 `SortButtonA11yValueTest`
- [ ] VoiceOver: 焦点 sort，朗读"Sort, Sorted by smart"
- [ ] Typecheck / lint 通过

##### US-P1-016: JoinRouteRequestSheet inline error feedback

**Description:** As a user submitting a join request, I want inline validation errors so I know which field is missing.
**Affected:** `Views/Companion/JoinRouteRequestSheet.swift`
**Acceptance Criteria:**

- [ ] pace 与 message 任一缺失 → 字段下方红色 hint
- [ ] 新增 `JoinRequestValidationTest`
- [ ] Simulator: 提交空表单 → hint 出现
- [ ] VoiceOver: hint 朗读
- [ ] Typecheck / lint 通过

##### US-P1-017: Approval queue 信任信号显示

**Description:** As a host reviewing join requests, I want to see opt-in status, walked count, and group count next to each requester.
**Affected:** `Views/Companion/ApprovalQueueView.swift`
**Acceptance Criteria:**

- [ ] 每条申请下方展示 3 个 micro-stats
- [ ] 新增 `ApprovalTrustSignalTest`
- [ ] Simulator: 模拟 3 个 requester 不同信号，截图
- [ ] Typecheck / lint 通过

#### 组 P1-E · 性能与文案剩余

##### US-P1-018 .. US-P1-029（11 个）：分别覆盖

- Filter "Now" 与 Map "bestNow" 视觉同步
- 路线 section / Nearby section 视觉分隔
- SettingsView KeyPath 警告（与 P0-008 不同位置）
- ChatView `otherId` 未用警告
- ShareCardComponents 文案硬编码（2 处）
- ShareCardView 文案硬编码（1 处）
- print 19 处 → Logger（分批迁移）
- VoiceService `@MainActor` 推进
- ForEach String id `\.self` 重复 ID 修复（3 处）
- Onboarding Skip 入口
- 启动 ProgressView 闪烁修复（与 US-P1-006 配套）

每条按统一模板写，详细 AC 在 implementation 期生成。

---

### 3.3 P2 — 16 个（最后做）

按主题分组，每条按统一模板：

| 编号      | 主题          | 摘要                                              |
| --------- | ------------- | ------------------------------------------------- |
| US-P2-001 | Onboarding    | Skip 入口                                         |
| US-P2-002 | Filter        | "Now" 模式与地图视觉同步                          |
| US-P2-003 | BottomSheet   | 路线 / Nearby 视觉分隔线                          |
| US-P2-004 | Settings      | admin 解锁 / 语言切换重启测试                     |
| US-P2-005 | ShareCard     | "Solo Compass" / "Solo Score" 文案 l10n           |
| US-P2-006 | Settings      | `Color` extension 私有化检查                      |
| US-P2-007 | Companion     | Companion layer 文案占位（与 US-P0-007 决策联动） |
| US-P2-008 | Map           | 顶部色块缺街道（V6）                              |
| US-P2-009 | Performance   | print → Logger 全仓迁移                           |
| US-P2-010 | a11y          | Onboarding pages VoiceOver order                  |
| US-P2-011 | a11y          | Empty-state announce                              |
| US-P2-012 | Theming       | ObsidianTheme dark mode 校准                      |
| US-P2-013 | i18n          | zh-Hans 标点对齐（半角/全角）                     |
| US-P2-014 | Code quality  | comment-only TODOs 清扫                           |
| US-P2-015 | Code quality  | unused imports 清扫                               |
| US-P2-016 | Documentation | inline doc 缺失补全（顶层 public API）            |

P2 每条 AC 仍要求 XCTest + 手测，但 VoiceOver/Sentry 视类型可选。

---

### 3.4 设计稿与架构路线图 — 8 个

#### 组 A-1 · CompareCanvas 剩余 20%

##### US-A-001: RouteCard 加 stop-strip

**Description:** As a user browsing routes, I want a visual breadcrumb of stops on each route card so I can preview the journey.
**Affected:** `Views/Companion/Components/RouteCard.swift`
**Acceptance Criteria:**

- [ ] stops 渲染为彩色圆点 + 连接线（设计稿 route.jsx `stop-strip`）
- [ ] 新增 `RouteCardStopStripTest`：snapshot 验证 2/3/5 站
- [ ] Simulator: 截图与设计稿对比
- [ ] CT token 全部对齐（CT.accent / CT.fgMuted）
- [ ] Typecheck / lint 通过

##### US-A-002: RouteCard 加 recruit-mini

**Description:** As a user with companion mode on, I want each route card to show the recruiting state inline (host / N/N filled / departure time) without opening detail.
**Acceptance Criteria:**

- [ ] companionOn && status ∈ {open, forming, closed, completed} → 渲染 recruit-mini 条
- [ ] 文案根据 status 切换（"Maya 招募 · 1/3 · 今晚 18:00"）
- [ ] 新增 `RouteCardRecruitMiniTest`：覆盖 4 态 snapshot
- [ ] Simulator: 截图四态
- [ ] Typecheck / lint 通过

##### US-A-003: RouteCard 加 walked-by 行

**Description:** As a user browsing routes, I want to see how many travelers walked this route (with avatar stack) so I can gauge social proof.
**Acceptance Criteria:**

- [ ] companion off 或 companion nil 时显示 walked-by 行
- [ ] AvatarStack maxVisible: 4
- [ ] 新增 `RouteCardWalkedByTest`
- [ ] Typecheck / lint 通过

##### US-A-004: RecruitingModule 三档视觉强度

**Description:** As a designer, I want restrained / neutral / strong variants of the recruiting module to A/B test.
**Affected:** `Views/Companion/Components/RecruitingModule.swift`（如不存在则新建）
**Acceptance Criteria:**

- [ ] 三档：restrained (默认, peer card) / neutral (暖色 gradient) / strong (Airbnb ribbon + bold border)
- [ ] `strength` 参数控制
- [ ] 新增 `RecruitingModuleStrengthTest`：snapshot ×3
- [ ] Simulator: 截图三档
- [ ] Typecheck / lint 通过

##### US-A-005: CT token 推广到其他 View

**Description:** As a code reviewer, I want all `Color.accentColor` and `Color(hex:)?` calls in Companion / Route surfaces migrated to CT.\* so design tokens are authoritative.
**Acceptance Criteria:**

- [ ] grep `Color.accentColor` 在 Views/Companion / Views/Map 出现次数 → 0
- [ ] grep `Color(hex:` failable 调用全替换
- [ ] 新增 `DesignTokenAdoptionTest`：扫描断言
- [ ] Simulator: 视觉前后对比
- [ ] Typecheck / lint 通过

#### 组 A-2 · 架构债务

##### US-A-006: MapViewModel.swift 1685 行拆分

**Description:** As a maintainer, I want MapViewModel split into focused sub-VMs by responsibility.
**Acceptance Criteria:**

- [ ] 拆出 `MapCameraViewModel` / `MarkerStateViewModel` / `BottomInfoViewModel` 等
- [ ] 单文件 ≤ 600 行
- [ ] 所有 既有 test 通过
- [ ] 新增 `MapViewModelDecompositionTests`：验证子 VM 独立可测
- [ ] Typecheck / lint 通过

##### US-A-007: AIService.swift 1467 行拆分

**Description:** As a maintainer, I want AIService split into request / cache / synthesis sub-services.
**Acceptance Criteria:** 类似 US-A-006，单独 PR

##### US-A-008: CompassMapView.swift 1457 行拆分

**Description:** As a maintainer, I want CompassMapView split into sub-View components by overlay layer.
**Acceptance Criteria:** 类似 US-A-006

> US-A-009 .. A-011: ExperienceDetailView 1423 / SettingsView 1344 / ChatSheet 807 同样拆分，每个独立 PR。

---

## 4. Functional Requirements

- **FR-1** 全仓 Swift 文件 grep `\bcompanion!` 在非 Tests 返回 0
- **FR-2** `Services/SyncService.swift` 内 `try?` encode/decode 数 = 0
- **FR-3** `AIService` 提供 `lastSynthesisQuality: AISynthesisQuality` public 字段
- **FR-4** ExperienceCardView 根据 `lastSynthesisQuality == .skeleton` 渲染 `SkeletonBadgeView`
- **FR-5** `CompassMapView.body` 返回类型不含 `AnyView`
- **FR-6** `MapViewModel.markerState(for:)` 单次调用 helper，ForEach 内仅 1 处调用
- **FR-7** `MapViewModel._cachedCities` / `_nowCount` 标 `@ObservationIgnored`
- **FR-8** 所有按钮 hit target ≥ 44×44pt（CI lint 规则后续可加）
- **FR-9** 所有用户可见字符串走 `NSLocalizedString`，`StringsParityTests` 通过
- **FR-10** iOS test target 函数数 ≥ baseline + 58
- **FR-11** `VerifiedBadge` 三档全部渲染（已交付 PR #292）
- **FR-12** `RouteCard` 含 stop-strip + recruit-mini + walked-by（US-A-001..003）
- **FR-13** `RecruitingModule` 含 strength 参数三档（US-A-004）
- **FR-14** Cold start 后 selectedCity / mapCameraPosition / nearbyExperiences 三者同步
- **FR-15** 任意 locale 下扫描 Views 目录无硬编码英文 user-visible 文案
- **FR-16** 单文件行数 ≤ 800（架构 PR 完成后强制）

---

## 5. Non-Goals (Out of Scope)

- ❌ **Web / Bot / Edge Function 端**：apps/web、apps/bot、Supabase Edge Function 的类似问题不在本 PRD。各自需独立 PRD。
- ❌ **AI 推荐质量本身**：本 PRD 只做 transparency（skeleton 角标 + Sentry 上报），**不**调 model / prompt / temperature / context 长度。模型质量在 `docs/AI_AUDIT_2026Q2.md` 范围。
- ❌ **新功能 / 新视图**：纯修复 + 设计稿对齐。所有新增视图限于 `SkeletonBadgeView`、`RecruitingModule` 三档变体。
- ❌ **Companion layer 真实数据接入**：US-P0-007 决策时若选 C（接 backend），另起 PRD。
- ❌ **CI / DevOps / 发布流水线**：iOS CI workflow / TestFlight 上传等不动。
- ❌ **后端 schema 变更**：`packages/core/src/experience.ts` 与 iOS Model 的 schema 不变。
- ❌ **i18n 新增语种**：仅维护现有 en + zh-Hans，不新增 ja / es / etc.
- ❌ **付费墙 / 订阅逻辑改动**：US-P1-010 仅修复导航路径，不改产品边界。

---

## 6. Design Considerations

- **新增组件**仅 4 个：`SkeletonBadgeView`（US-P0-003）、`RouteCardStopStrip`（US-A-001）、`RouteCardRecruitMini`（US-A-002）、`RecruitingModule` 三档变体（US-A-004）。
- **现有 CompareTokens.swift** 是设计 token 单一权威，所有新组件颜色/字体走 `CT.*`，禁止再用 `Color.accentColor` 或 failable hex。
- **设计稿 ground truth**：`/tmp/compare_design/solocompassapp/project/` 下的 `CompareCanvas.html` / `route.jsx` / `companion.jsx` / `styles.css` + chat transcripts。本仓不入。
- **截图对比**：所有 UI 类 US 在 PR description 强制 before/after 截图，存档在 PR comments 而非仓内。
- **a11y 视觉不变**：所有 hit-target 修复只扩命中区，视觉尺寸保持像素稿。
- **暗色模式不在本 PRD**：CompareTokens 当前固定 light token，dark mode 适配是独立 task（US-P2-012）。

---

## 7. Technical Considerations

### 7.1 Sentry 上报

- 所有 P0 / P1 静默失败类 US 都要确认 `SentryService.capture` 在 DEBUG 与 release 都能上报。
- 本地用 SentryService mock 验证；release 后第一周观察 Sentry quota，必要时按 OQ-3 收敛上报频次。

### 7.2 测试基线

- 当前 iOS test target ~ 489 个测试函数；本 PRD 加 58 个，总数 ≥ 547。
- 每新增 Swift 文件后跑 `cd apps/ios && xcodegen`。
- 所有 US 在 iOS 26.4 Simulator (iPhone 17 Pro) 通过 `xcodebuild test`。

### 7.3 性能基线

- US-P0-004 / US-P1-001 / US-P1-002 / US-P1-003 / US-P1-005 / US-P1-008 都涉及性能，**必须**在 PR description 贴 Instruments p95 对比截图。
- 建议第 1 周开 spike PR 跑 baseline，钉死绝对数字后再开始 P0 性能批。

### 7.4 PR 依赖图

```
PR-1 (US-P0-001 force-unwrap)       ──┐
PR-2 (US-P0-002 SyncService)         ──┤
PR-3 (US-P0-003 AI skeleton badge)    ◄── 依赖 PR-2 共享 Sentry pattern
PR-4 (US-P0-004 AnyView)             ──┐
PR-5 (US-P1-001..003 perf 三件套)     ◄── 必须 baseline 在 PR-4 后采
PR-6 (US-P0-005..006 a11y P0 批)
PR-7 (US-V-001..003 真机 P0 批)
PR-8 (US-P0-008..010 Swift 6 警告批)
PR-9 (US-P0-007 Companion toggle 决策)
PR-10..15 (P1 分组 A..E)
PR-16..18 (P2 分批)
PR-19..21 (设计稿 A-001..005)
PR-22..24 (架构拆文件 A-006..011，每文件独立)
```

### 7.5 依赖与约束

- `SoloCompass.xcodeproj/project.pbxproj` 是 xcodegen 自动生成 —— **不要手编**。每加文件跑 `cd apps/ios && xcodegen`。
- `Localizable.strings` 现在是 UTF-8，已被多次 patch（见 `f5555c3` / `a64f97d` / `ef344b9`），加 key 时不要改回 UTF-16。
- Force `route.companion!` 在 6 个位置外，**绝对不要**新增 force-unwrap，否则违反本 PRD 精神。
- 本 PRD 不增任何 SwiftPM 依赖（约束在 supabase-swift + sentry-cocoa）。

---

## 8. Success Metrics

| 指标                                 | 当前                        | 1 周后 | 2 周后  | 4 周后  |
| ------------------------------------ | --------------------------- | ------ | ------- | ------- |
| P0 关闭数                            | 0 / 13                      | 6 / 13 | 13 / 13 | —       |
| P1 关闭数                            | 0 / 29                      | 0 / 29 | 12 / 29 | 29 / 29 |
| P2 关闭数                            | 0 / 16                      | 0 / 16 | 0 / 16  | 12 / 16 |
| 设计稿对齐 US                        | 1 / 6（VerifiedBadge 已做） | 1      | 4       | 6       |
| 架构拆文件 US                        | 0 / 6                       | 0      | 0       | 3       |
| iOS test target 函数                 | ~489                        | ~510   | ~533    | ≥ 547   |
| Sentry 月度 crash (companion)        | unknown                     | < 5    | < 2     | < 1     |
| Sentry 月度 skeleton_fallback 上报   | 0                           | > 0    | > 0     | > 0     |
| Sentry 月度 SyncService.enqueue 上报 | 0                           | > 0    | > 0     | > 0     |
| 仓内 `\bcompanion!` 数               | 6                           | 0      | 0       | 0       |
| 仓内硬编码英文 user-visible 数       | ≥ 6                         | ≥ 6    | 0       | 0       |
| 单文件 > 800 行数                    | 6                           | 6      | 5       | ≤ 3     |
| VoiceOver "申请加入路线"成功率       | 未测                        | 50%    | 80%     | 100%    |

---

## 9. Open Questions

- **OQ-1**: Companion layer toggle 选 A (hide) / B (coming soon hint) / C (接 backend)？_待产品决策，影响 US-P0-007_
- **OQ-2**: AI skeleton 角标产品文案：「数据有限」/「Limited data」/「占位预览」/「AI 未生成」？_待产品决策，影响 US-P0-003_
- **OQ-3**: Sentry skeleton_fallback 上报频次：每次 / 每小时合并 / 每日合并？_待 ops 决策_
- **OQ-4**: Performance 阈值绝对数字（US-P0-004 / US-P1-001..003）需要 spike PR 钉死。是否本周内跑 baseline？_待决_
- **OQ-5**: 设计稿剩余 20% 缺口（A-001..005）的优先级——是穿插进 P1 批，还是 P1/P2 全做完后单独冲刺？_待 PM 决策_
- **OQ-6**: 6 个超 800 行的拆文件 PR（A-006..011）排在 P2 之后还是 P1 之后？拆文件风险最高，建议最后。_待 lead 决策_
- **OQ-7**: VoiceOver 全闭环成功率验收是否需要外部测试用户？_待 PM_
- **OQ-8**: 与 `docs/AI_AUDIT_2026Q2.md` 中的 P0 (AI 质量) 是否有重叠？_需 lead 对账_

---

## 10. Agent 评测原始证据汇总

| Agent                      | 输出位置                                                     | 形态                                                                               |
| -------------------------- | ------------------------------------------------------------ | ---------------------------------------------------------------------------------- |
| code-explorer              | 嵌在主对话决策中                                             | iOS 现有 Route / Companion 全部实现                                                |
| code-reviewer (`ad84f0a…`) | 完成于 prior session                                         | 11 finding (1 Critical + 5 High + 3 Medium)                                        |
| a11y-architect             | 并行结果嵌入 EVAL_REPORT                                     | WCAG 2.2 全维度                                                                    |
| performance-optimizer      | 同上                                                         | AnyView / cache / TimelineView                                                     |
| silent-failure-hunter      | 同上                                                         | SyncService / LocationService / catch 吞                                           |
| e2e-runner v1 (`aba9c19…`) | **stall failed**                                             | 0 截图                                                                             |
| e2e-runner v2 (`a16a636…`) | `/tmp/sc-eval-shots/01..05.png` + `docs/EVAL_REPORT.md §4.5` | 5 张截图 + 6 条真机 finding                                                        |
| 设计稿 fetch               | `/tmp/compare_design/solocompassapp/`                        | tar 24MB · CompareCanvas.html + route.jsx + companion.jsx + styles.css + 2 段 chat |

详细 finding 文本见 `docs/EVAL_REPORT.md`。本 PRD 是 EVAL_REPORT 的**可执行版**。

---

## 11. Cross-Reference

| 文档                                                  | 关系                                                 |
| ----------------------------------------------------- | ---------------------------------------------------- |
| [docs/EVAL_REPORT.md](../docs/EVAL_REPORT.md)         | finding 原始来源（含真机 § 4.5）                     |
| [tasks/prd-p0-fix-batch.md](./prd-p0-fix-batch.md)    | 本文件的 P0 子集 · 已被本文件超集                    |
| [docs/AI_AUDIT_2026Q2.md](../docs/AI_AUDIT_2026Q2.md) | AI 模型质量审计 · 与 US-P0-003 边界                  |
| [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)       | 拆文件 US-A-006..011 的参考                          |
| PR #292                                               | 本 PRD 的第一个交付（VerifiedBadge 三档 + CT token） |

---

_本 PRD 是 EVAL_REPORT 的可执行版。所有 acceptance criteria 中的"截图存档"指存在 PR description 中作为 reviewer 验收材料。所有 file:line 锚点基于 `main @ 0252ce3`。_
