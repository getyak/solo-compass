# PRD: P0 Fix Batch — Solo Compass iOS

| 字段 | 值 |
|---|---|
| 状态 | 草稿 → 待评审 |
| 创建日期 | 2026-05-28 |
| 基线 | `main @ 0252ce3` |
| 依据 | `docs/EVAL_REPORT.md` |
| 范围 | apps/ios/SoloCompass |
| 预计交付 | 10 个 PR（一项一 US），1-2 周窗口 |

---

## 1. Introduction / Overview

5 个并行 agent 对 Solo Compass iOS 做了一轮深度评测，输出 52 条 finding。其中 **10 条 P0** 是会真实造成用户损失或 crash 的问题：force-unwrap 崩溃路径、`SyncService` 静默丢用户数据、AI fallback 用户看不见、a11y 命中区不达标、`AnyView` 杀 SwiftUI diff 等。

本 PRD 把 10 个 P0 一对一拆成 10 个可独立 ship 的 user story，**不做任何超出 P0 范围的事**。每个 US 必须满足四种验收：iPhone 17 Pro Simulator 真机手测 + 自动化 XCTest + VoiceOver 手动验收（a11y 类）+ Sentry 上报证据（静默失败类）。

---

## 2. Goals

- **零 crash 风险**：消除全部 `route.companion!` force-unwrap 路径
- **零静默数据丢失**：`SyncService` 任何 enqueue 失败必须可观测
- **AI 透明度**：用户能区分真 AI 输出 / skeleton 占位
- **a11y 合规**：所有 P0 hit-target 与 live-region 缺失全部修复，VoiceOver 用户可独立完成核心闭环
- **性能基线**：CompassMapView 增量 diff 恢复；markerState / availableCities / nowCount 不再每帧重算
- **每个 fix 都有 XCTest 守护**，回归率 0

---

## 3. User Stories

### US-001: 消除 `route.companion!` force-unwrap

**Description:** As an iOS engineer, I want all 6 `route.companion!` force-unwrap sites replaced with safe binding so the app never crashes when companion data is unexpectedly nil.

**Affected sites:**
- `Services/LocalRouteCompanionRemote.swift:38, 119, 126, 137`
- `Views/Companion/MyRequestsListView.swift:182`
- `Views/Companion/ApprovalQueueView.swift:311`

**Acceptance Criteria:**
- [ ] 0 occurrences of `route.companion!` or `updated.companion!` in non-test Swift files (grep verified)
- [ ] Each site replaced with `guard var companion = updated.companion else { return }` pattern, mutating the bound copy then writing back via `updated.companion = companion`
- [ ] New XCTest `RouteCompanionForceUnwrapTests` covers each mutation with `companion == nil` input → operation no-ops cleanly, no crash
- [ ] Existing `RouteCompanionStateMachineTests` still pass
- [ ] iPhone 17 Pro Simulator: 手动跑通"申请加入路线 → 主理人审批 → 撤回申请"完整闭环，截图存档
- [ ] Sentry: 任何兜底 no-op 触发要 `SentryService.capture(...)` 上报一条 warning，便于发现真实场景
- [ ] Typecheck / lint 通过

---

### US-002: SyncService.enqueue 错误传播

**Description:** As an end user, I want my completions, favorites, and route join requests to never silently disappear so my actions are durable across devices.

**Affected:** `Services/SyncService.swift:95-98`

**Acceptance Criteria:**
- [ ] `enqueue(_:)` 中 `try? JSONEncoder().encode(...)` 改为 `do { try ... } catch { SentryService.capture(error, context: "SyncService.enqueue", payload: payloadType) }`
- [ ] 失败时不再静默 `return`，而是抛回上层（或保留 graceful 降级但**必须**上报）
- [ ] 新增 `SyncServiceEnqueueTests`：注入故意 encode 失败的 payload → 验证 Sentry mock 收到上报
- [ ] iPhone 17 Pro Simulator: 模拟离线 → 完成一个 experience → 重启 app → 看到 sync queue 正常恢复，截图存档
- [ ] Sentry 后台能看到至少 1 条 `SyncService.enqueue` 上报样本作为验证证据
- [ ] Typecheck / lint 通过

---

### US-003: AI fallback 用户可见标识

**Description:** As an end user, I want a clear visual indicator when an experience card is showing skeleton data instead of real AI insight so I don't mistake placeholder text for personalized recommendation.

**Affected:** `Services/AIService.swift:765-768, 781-791` + `Views/Experience/ExperienceCardView.swift`

**Acceptance Criteria:**
- [ ] `AIService` 暴露 `lastSynthesisQuality: SynthesisQuality` 状态（`.real | .skeleton | .cached`）
- [ ] Experience card 在 skeleton 状态下显示一个角标 pill：`NSLocalizedString("ai.skeleton.badge", ...)` = "数据有限" / "Limited data"
- [ ] Skeleton 角标使用 `CT.fgMuted` 色而非 accent，避免抢主内容焦点
- [ ] 真实 AI 输出 / cached 输出 **不**显示该角标
- [ ] 新增 `AISkeletonSurfaceTests`：注入 skeleton experience → 验证角标渲染 + a11y label 正确
- [ ] iPhone 17 Pro Simulator: 把 `ANTHROPIC_API_KEY` 留空跑一遍，确认 explore 出的卡片都有"数据有限"角标，截图前后对比
- [ ] VoiceOver: 角标的 accessibilityLabel = "数据有限，此卡片为占位内容"
- [ ] Sentry: skeleton fallback 触发上报 `AIService.skeleton_fallback` warning，便于度量发生率
- [ ] Typecheck / lint 通过

---

### US-004: 移除 CompassMapView 的 AnyView 包裹

**Description:** As an iOS engineer, I want the root `mapContent` to return `some View` directly instead of being wrapped in `AnyView` so SwiftUI can do incremental diffing on the app's heaviest view.

**Affected:** `Views/Map/CompassMapView.swift:76`

**Acceptance Criteria:**
- [ ] `public var body: some View { mapContent }` 直接返回 `@ViewBuilder` 的具体类型
- [ ] 移除 `AnyView(mapContent)` 调用
- [ ] 若 init 签名因为 public ABI 不能改，加 `@ViewBuilder` 修饰让 body 推导出来
- [ ] 新增 `CompassMapViewBodyTypeTests`：通过 `String(describing: type(of:))` 断言 body 不是 `AnyView<...>`
- [ ] iPhone 17 Pro Simulator: 跑 Instruments Time Profiler，对比 before/after 一段 30s pan/zoom 操作的 main thread cpu time，要求降低 ≥20%
- [ ] 全部既有 snapshot/unit test 通过（包括 `MarkerIconTests` / `CityPillHitTargetTests` / `FilterBarViewTests`）
- [ ] Typecheck / lint 通过

---

### US-005: markerState 每帧单次调用

**Description:** As an iOS engineer, I want `markerState(for:)` called once per ForEach iteration so we don't recompute 6 conditions (`isCompleted` / `isFavorited` / `isBestNow` / `minutesUntilBestTime`) twice per visible marker per frame.

**Affected:** `Views/Map/CompassMapView.swift:612-616`

**Acceptance Criteria:**
- [ ] `ForEach(visibleExperiences)` body 顶部 `let state = viewModel.markerState(for: exp)`，下面两处复用
- [ ] 新增 `MarkerStatePerformanceTest`：构造 100 个 experience，循环 1000 次取 state，p95 latency 较 baseline 降低 ≥40%
- [ ] iPhone 17 Pro Simulator: 跑一遍 explore + filter 切换，地图 marker 渲染肉眼无差
- [ ] 既有 `MarkerIconViewTests` 全部通过
- [ ] Typecheck / lint 通过

---

### US-006: availableCities 缓存

**Description:** As an iOS engineer, I want `MapViewModel.availableCities` to cache its result so we don't traverse `allExperiences` + SwiftData fetch on every body invocation.

**Affected:** `ViewModels/MapViewModel.swift:187-215`

**Acceptance Criteria:**
- [ ] 加 `@ObservationIgnored private var _cachedCities: [CityInfo]?`
- [ ] `allExperiences` / `selectedCity` 变化时 invalidate（在 didSet 或 refresh 路径中）
- [ ] `availableCities` 计算属性命中缓存返回，否则重算并存
- [ ] 新增 `MapViewModelCityCacheTests`：覆盖 fresh / cache hit / invalidation 三种路径
- [ ] iPhone 17 Pro Simulator: 切换 4 个城市 → 验证 city pill / city picker / nearest seeded city 行为一致
- [ ] 既有城市相关测试通过（`CityPillHitTargetTests` 等）
- [ ] Typecheck / lint 通过

---

### US-007: nowCount 缓存

**Description:** As an iOS engineer, I want `MapViewModel.nowCount` cached and recomputed only on `visibleExperiences` change so BottomInfoSheet & FilterBarView don't trigger O(n) scans on every render.

**Affected:** `ViewModels/MapViewModel.swift:298` + `updateBottomInfo()` 内部第 720, 736 行

**Acceptance Criteria:**
- [ ] `private var _nowCount: Int = 0` + 在 `loadNearbyExperiences` / `refreshForLocation` / `updateBottomInfo` 末尾统一更新
- [ ] `nowCount` 计算属性返回缓存
- [ ] `visibleExperiences.filter { $0.isBestNow() }` 出现次数从 3 降到 ≤1
- [ ] 新增 `NowCountCacheTests`：注入 mock experiences → 验证 count 更新时机正确
- [ ] iPhone 17 Pro Simulator: 切换 filter "Now" 模式 → 抽屉数字与地图标记一致，无延迟
- [ ] 既有 `FilterBarViewTests` 通过
- [ ] Typecheck / lint 通过

---

### US-008: BottomInfoSheet drag handle hit target ≥44pt

**Description:** As a VoiceOver / Switch Control user, I want the bottom sheet drag handle to have a 44×44pt minimum hit area so I can switch detent levels.

**Affected:** `Views/Map/BottomInfoSheet.swift:127-131`

**Acceptance Criteria:**
- [ ] `dragHandleArea` `.frame(minWidth: 60, minHeight: 44).contentShape(Rectangle())`
- [ ] 视觉 pill 仍是 36×4（不变）
- [ ] 新增 `.accessibilityLabel("Sheet handle")` + `.accessibilityAdjustableAction` cycling peek/mid/full
- [ ] 新增 `BottomInfoSheetHandleHitTargetTests`：snapshot 验证 hit area ≥44
- [ ] iPhone 17 Pro Simulator: 用 Accessibility Inspector 检查 hit area，截图存档
- [ ] VoiceOver: 焦点能落在 handle 上，三态 cycle 可用
- [ ] Typecheck / lint 通过

---

### US-009: FilterBar pills 与 ExperienceCard 心形按钮 hit target ≥44pt

**Description:** As a VoiceOver / Switch Control user, I want filter pills and the favorite heart to all meet HIG 44pt minimum so I can interact with them reliably.

**Affected:**
- `Views/Filter/FilterBarView.swift:240` (iconPill 36×36)
- `Views/Experience/ExperienceCardView.swift:175` (favorite heart 32×32)
- `Views/Map/CompassMapView.swift:1124` (DismissibleBanner X 按钮)

**Acceptance Criteria:**
- [ ] 所有 3 个 hit area `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())`，视觉尺寸保持不变
- [ ] 新增 `HitTargetSizeTests`：枚举上述 view，断言 hit area ≥44
- [ ] iPhone 17 Pro Simulator: 跑一遍 filter 切换 + 收藏 + 关闭 banner 流程
- [ ] VoiceOver: 三处都能被 focus，actionable trait 正确
- [ ] Typecheck / lint 通过

---

### US-010: 静态文案与状态 announce 修复

**Description:** As a VoiceOver user, I want hardcoded English "results" strings replaced with localized strings and voice processing toasts to announce themselves so I stay in sync with app state.

**Affected:**
- `Views/Filter/FilterBarView.swift:180, 230, 264, 301` (硬编码 "results")
- `Views/Map/CompassMapView.swift:868-885` (voice.processing toast 缺 live region)

**Acceptance Criteria:**
- [ ] 4 处 "results" 替换为 `NSLocalizedString("filter.results.count", comment: "")` 配合 `String(format:)`
- [ ] `Localizable.strings`（en + zh-Hans）新增对应 key，过 `StringsParityTests`
- [ ] `voice.processing` toast 包裹 `.accessibilityElement().accessibilityAddTraits(.updatesFrequently)` + 在 onAppear 调 `UIAccessibility.post(.announcement, ...)`
- [ ] 新增 `FilterBarLocalizationTests`：验证 "results" 不再出现在编译后字符串
- [ ] iPhone 17 Pro Simulator: 切换语言 zh-Hans → en，filter 计数文案两边都对
- [ ] VoiceOver: 触发 voice 查询，能听到 "思考中: <query>" 朗读，不需要焦点切换
- [ ] Typecheck / lint 通过

---

## 4. Functional Requirements

- **FR-1**: 全仓 Swift 文件 grep `\bcompanion!` 返回 0 行（Tests 目录除外）
- **FR-2**: 全仓 Swift 文件 grep `try? .*encode\|try? .*decode` 在 `Services/SyncService.swift` 中返回 0 行
- **FR-3**: AIService 提供 `lastSynthesisQuality: AISynthesisQuality { case real, skeleton, cached }` public 字段
- **FR-4**: ExperienceCardView 根据 `lastSynthesisQuality == .skeleton` 渲染 `SkeletonBadgeView`，否则不渲染
- **FR-5**: CompassMapView.body 返回类型不再包含 `AnyView`（可通过 LLDB `po type(of: view.body)` 验证）
- **FR-6**: MapViewModel 提供 `markerState(for:)` 单次调用 helper；ForEach 内部仅一处调用
- **FR-7**: MapViewModel 内部 `_cachedCities` / `_nowCount` 字段标 `@ObservationIgnored`，避免循环依赖触发 Observation
- **FR-8**: 全仓 Swift 文件中 hit target `.frame(width:` 含 32 / 36 数值且作用在按钮上的——必须有 `.contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44)` 兜底
- **FR-9**: 所有用户可见的字符串都通过 `NSLocalizedString` 调用；CI 的 `pnpm parity:check` 与 `StringsParityTests` 通过
- **FR-10**: 上述每一项都有对应 XCTest（命名见 US AC），iOS test target 总用例数 ≥ baseline + 10

---

## 5. Non-Goals (Out of Scope)

- ❌ **拆文件 / 架构重构**：6 个超 800 行的文件（MapViewModel 1685 / AIService 1467 / CompassMapView 1457 / ExperienceDetailView 1423 / SettingsView 1344 / ChatSheet 807）本轮**不动**，留给独立 PR。
- ❌ **RouteCard 设计稿全量对齐**：stop-strip / recruit-mini / 三档强度均**不在本 PRD**，由后续 "RouteCard CompareCanvas alignment" PRD 跟进。
- ❌ **Web / Bot / Edge Function 同步修复**：apps/web 与 apps/bot 端的类似问题不在本轮范围；Supabase Edge Function 服务端配置同样不动。
- ❌ **AI 推荐质量本身**：本轮只做 transparency（让用户知道是 skeleton），**不**调 model / prompt / temperature / context 长度。
- ❌ **P1 / P2 修复**：EVAL_REPORT 里 27 个 P1 与 15 个 P2 全部**不**包含在本 PRD。下一份 PRD 处理 P1。
- ❌ **新功能 / 新视图**：本 PRD 是纯修复，不增任何用户可见的新能力。
- ❌ **Companion layer 真实数据接入**：`Views/Map/CompassMapView.swift:541` 的 `nearbyCells` 静默返回 nil 是产品方向问题（后端 geohash6 未交付），本 PRD **暂不动**，但建议另起一个 task 决定是否先隐藏 toggle。

---

## 6. Design Considerations

- **新增组件**：仅 `SkeletonBadgeView`（US-003）。复用 `CompareTokens.CT.fgMuted` 色，capsule 风格与现有 `ConfidenceBadge` 一致。
- **不引入新依赖**：所有改动都在现有 SwiftUI + XCTest + Sentry 体系内。
- **a11y 视觉不变**：所有 hit-target 修复仅扩大命中区，视觉尺寸保持当前像素稿。
- **Skeleton 角标位置**：放在 ExperienceCard 右上角，紧贴 ConfidenceBadge 下方或并列，需在 implementation 期产出设计 mock 1 张确认。

---

## 7. Technical Considerations

- **Sentry 上报**：US-002 / US-003 必须确认 `SentryService.capture` 在 `DEBUG` 与 release 都正常上报；本地用 SentryService mock 验证。
- **测试基线**：当前 iOS test target 有 ~489 个测试函数；本 PRD 加 10 个，总数应 ≥499。
- **Build matrix**：所有 US 都必须在 iOS 26.4 Simulator (iPhone 17 Pro) 通过 `xcodebuild test`。
- **XCodeGen**：每新增 Swift 文件后跑 `cd apps/ios && xcodegen` 重生 .xcodeproj，避免遗漏。
- **回归保护**：US-004 / US-005 / US-006 / US-007 修改的是热路径，**必须**在 PR description 中贴 Instruments p95 对比截图。
- **依赖关系**：
  - US-001 与 US-002 独立，可并行
  - US-003 依赖 US-002（共享 Sentry 上报 pattern）
  - US-004 必须先于 US-005/US-006/US-007（否则性能对比 baseline 不准）
  - US-008 / US-009 / US-010 独立，可并行

---

## 8. Success Metrics

| 指标 | 当前 | 目标 |
|---|---|---|
| 仓内 `route.companion!` force-unwrap 数 | 6 | 0 |
| 仓内 `Services/SyncService.swift` 的 `try?` encode 数 | 1 | 0 |
| 仓内硬编码 "results" 字符串数 | 4 | 0 |
| iOS test target 函数数 | 489 | ≥499 |
| CompassMapView 30s pan/zoom main-thread CPU time | baseline X | ≤ 0.8X |
| Sentry 月度 crash 数（companion 相关） | unknown | < 1 |
| Sentry 月度 skeleton_fallback 上报 | 0 | > 0（验证机制有效，而非"越少越好"） |
| VoiceOver 用户完成"申请加入路线"闭环成功率（人工测试） | 未测 | 100% |

---

## 9. Open Questions

1. **Companion layer toggle 是否本轮隐藏？** `Views/Map/CompassMapView.swift:541` 占位 nil 已存在多月。本 PRD 标 Non-Goal，但用户体验上是显眼 dead button——是否在 US-008/US-009 顺手把 toggle `.hidden()` 掉？*(待产品决定)*
2. **AI skeleton 角标的产品文案**：用"数据有限" / "Limited data" 还是"占位预览" / "Preview" 还是"AI 未生成"？*(待产品决定)*
3. **Sentry skeleton_fallback 上报频次**：每次触发都报 vs 按小时合并 vs 按 daily 合并？太多会刷爆 quota。*(待 ops 决定)*
4. **Performance metrics 测量基线**：US-004/US-005 的 ≥20% / ≥40% 阈值需要先在干净 baseline 跑一次 Instruments，把绝对数字钉死。建议先开一个 spike PR 跑 baseline。
5. **本 PRD 与 EVAL_REPORT 的 PR ②④⑤ 的关系**：EVAL_REPORT § 4 给的 PR 拆分是把 P0 安全 + a11y 急修合并；本 PRD 选了一项一 US 的更细粒度。两者非冲突，本 PRD 是落地版。
6. **何时开始 P1 PRD**：本批 10 个 PR 全 merge 后立即开 P1 PRD，还是中间观察一周 Sentry 数据？

---

## 10. Cross-Reference

| US 编号 | EVAL_REPORT 锚点 | PR ① 已完成？ |
|---|---|---|
| US-001 | Journey 6 P0 | ❌ |
| US-002 | Journey 6 P0 | ❌ |
| US-003 | Journey 3 P0 | ❌ |
| US-004 | Journey 2 P0 | ❌ |
| US-005 | Journey 2 P1（但归入 P0 性能批） | ❌ |
| US-006 | Journey 2 P1（同上） | ❌ |
| US-007 | Journey 2 P1（同上） | ❌ |
| US-008 | Journey 5 P0 | ❌ |
| US-009 | Journey 4 P1（多处 hit target 合并归 P0 a11y 批） | ❌ |
| US-010 | Journey 4 P0 + Journey 7 P0 | ❌ |
| ✅ 已完成 | Journey 0 设计稿对齐 — CompareTokens + VerifiedBadge 三档 | ✅ PR ① |

---

_本 PRD 与 `docs/EVAL_REPORT.md` 互为依据。所有 acceptance criteria 中的"截图存档"指存在 PR description 中作为 reviewer 验收材料。_
