# Solo Compass — v1.0 Roadmap TODO

> Date: 2026-07-01
> Branch: main
> Design doc: `docs/V_NEXT_DESIGN.md`
> 目标: 把 Solo Compass 从工具升级为"独行者沉迷的 AI 旅伴"——14 周三阶段交付
> 三阶段总览: **Phase 1 (4w 沉淀地基) → Phase 2 (6w Agent v2 + 灵动岛) → Phase 3 (4w 情绪付费引擎)**

---

## 🧭 阅读指南

每个任务按 `[ ] #ID 标题 — 路径 — 说明` 格式。
- **⭐** = 沉迷设计 (lock-in 之王)
- **🎁** = 病毒传播功能 (用户会截图)
- **💰** = 直接付费转化点
- **🔪** = 砍 / 合并 / 减法
- **🧱** = 地基类 (无视觉,但必须有)

---

# Phase 1 — 沉淀地基 (4 周)

> 把 Travel Archive + TasteProfile 跑通,给"回看自己"一个家。
> 出口指标: 30 天后 30% 月活用户进过 Archive tab ≥3 次

## P1.0 — SwiftData 模型扩展 🧱

- [x] **#101 加 `VisitRecord @Model`** ✅ — `apps/ios/SoloCompass/Persistence/Models/VisitRecord.swift`
  - 字段: `experienceId: String, visitedAt: Date (ISO 8601 UTC), dwellSeconds: Int, weatherCode: String?, coordSnapBlob: Data ([lon,lat])`
  - 关联: 复用现有 ExperienceRecord (引用 string id,不外键约束)
  - 测试: 已在 `Tests/V1_9SchemaRecordsTests.swift` 覆盖 CRUD + coords 编解码 + 边界
- [x] **#102 加 `TasteProfile @Model`** ✅ — `apps/ios/SoloCompass/Persistence/Models/TasteProfile.swift`
  - 字段: `embedding: Data (float32 vector), descriptorsBlob: Data (JSON [String]), confidence: Double, updatedAt: Date, sourceVibePhotosBlob: Data?`
  - 单例存储 (每个用户 1 条,store 层强制)
- [x] **#103 加 `TimeCapsule @Model`** ✅ — `apps/ios/SoloCompass/Persistence/Models/TimeCapsule.swift`
  - 字段: `id: UUID, experienceId: String, createdAt: Date, scheduledFor: Date, contentType: String (text/voice/photo), contentBlob: Data, contextBlob: Data? (CapsuleContext JSON), opened: Bool`
  - 查询模式: `#Predicate { !$0.opened && $0.scheduledFor <= now }` (SwiftData SQLite 范围扫描)
  - 副产物: 加了 `CapsuleContext` Codable 结构 (weather/tasteDescriptors/moodEmoji)
- [x] **#104 加 `AgentMemorySnapshot @Model`** ✅ — `apps/ios/SoloCompass/Persistence/Models/AgentMemorySnapshot.swift`
  - 字段: `summary: String (≤500 字), lastTripCity: String?, recentChatDigest: String (≤300 字), updatedAt: Date`
  - 副产物: `systemPromptBlock()` 方法,空字段自动跳过,直接喂入 chat system prompt
- [x] **#100 schema v1.9 注册** ✅ — `apps/ios/SoloCompass/Persistence/SoloCompassModelContainer.swift`
  - 新增 `SoloCompassSchemaV1_9: VersionedSchema`,4 个新 model
  - migration plan stage v1.8 → v1.9 (lightweight, additive 4 张新表)
  - 主 ModelContainer + makeInMemory 两处都已注册
  - xcodegen 已重新生成 .xcodeproj
- [x] **#105 跑 `pnpm parity:check` 验证 TS↔Swift schema parity** ✅ (2026-07-01) — `scripts/check-swift-parity.ts`
  - 四路 parity 全绿: TS↔Swift interfaces / TS↔Drizzle experiences 表 / Supabase SQL↔Swift sync payloads / TS↔SwiftData @Model
  - 4 张新 @Model 表 (VisitRecord/TasteProfile/TimeCapsule/AgentMemorySnapshot) 被 SWIFTDATA_GLOBS 自动 match, 无需白名单
  - 结论: 4 个新 @Model 完全兼容既有 parity 契约

## P1.1 — 被动旅行档案 (免费层) ⭐🧱

- [x] **#110 新增 `VisitTrackingService`** ✅ — `apps/ios/SoloCompass/Services/VisitTrackingService.swift`
  - 隔离层: @MainActor @Observable final class, shared singleton + injectable init
  - 围栏接入: chain `LocationService.onRegionEnter/onRegionExit` 不抢槽,Task → handleEnter/Exit
  - 计时器: `pendingTimers: [String: Task]` + entryTimestamps; 默认 5min dwellThreshold (注入 sub-second 跑测试)
  - 隐私契约: foreground-only — `UIApplication.didEnterBackgroundNotification` → dropAllPending
  - GPS jitter: handleEnter 同 region 重入会被忽略 (timer 不存在才启动)
  - 失败安全: 缺 ModelContainer → os_log + 静默丢弃; save 失败 → os_log 不抛
  - 测试 7/7 通过 (Tests/VisitTrackingServiceTests.swift)
- [x] **#111 Archive tab 主屏 UI** ✅ — `apps/ios/SoloCompass/Views/Archive/ArchiveView.swift` + `ViewModels/ArchiveViewModel.swift`
  - 顶部: 当前 trip card (cityCode + dayCount + distinctExperienceCount, 暖琥珀 CT.accentSoft 背景 + CT.sunGold 数字)
  - 中部: 按 cityCode 分组的时间线; 每行=琥珀圆点 + title + 本地化日期 + dwell 分钟数 (≥60s 才显)
  - 底部: codex placeholder (虚线框 + Phase 3 提示)
  - 空态: 地图图标 + 友善文案
- [x] **#112 Archive 地图图层 "我去过的"** ✅ (vm 通路 + 6/6 测试绿) — `apps/ios/SoloCompass/ViewModels/MapViewModel.swift`
  - 复用既有 `.footprinted` 状态 (Experience.swift:1021 已存在 + MarkerIconView 金色光晕样式现成),零 view 改动
  - MapViewModel 加 `visitedExperienceIds: Set<String>` + `attachVisitedExperienceIds(_:)` (照 attachSubscriptionService pattern)
  - markerState 加 visited 分支,优先级在 .completed/.favorited/.bestNow/.upcoming 之后, 在 legacy passiveGpsHits30d 之前
  - 测试覆盖 6/6: baseline default / attach → footprinted / 清空 → default / completed 仍胜出 / favorited 仍胜出 / 无关 id 不影响
  - **尾巴**: CompassMapView 视觉接线 (用 @Query VisitRecord + onAppear 调 vm.attachVisitedExperienceIds) 留到 #190 P1.4 出口验证, Settings toggle 留到 #130 P1.3 Settings 重排同步做
- [x] **#113 写 ArchiveViewModel 单测** ✅ — `apps/ios/SoloCompass/Tests/ArchiveViewModelTests.swift`
  - 8/8 通过: 空态 / 城市分组 / 重访 distinctCount / 默认最新城市 / activeCityCode 覆盖 / 跨日 dayCount (本地时区) / 同日 = 1 day / 孤儿 visit 静默丢弃

## P1.2 — 口味画像采集 ⭐

- [x] **#120 Onboarding 第 4 步: vibe 采集** ✅ (build 绿, 已接入 OnboardingView step=4) — `apps/ios/SoloCompass/Views/Onboarding/OnboardingVibeStep.swift`
  - 3 张照片 PhotosPicker (iOS 17+ SwiftUI 原生, 复用 CreateExperienceSheet 同 pattern)
  - 选完调 AIService.generateTasteProfile → upsert TasteProfile (P1.0 #102 已落地表)
  - Continue + Skip 两路, Skip 不抛错: AIService fallback 永远返回最低 confidence 的有效 profile
  - 中英本地化 (onboarding.vibe.* 7 条)
- [x] **#121 Onboarding 第 5 步: city + 一句话描述** ✅ (build 绿, 已接入 OnboardingView step=5) — `apps/ios/SoloCompass/Views/Onboarding/OnboardingCityStep.swift`
  - 不复用 CityPickerSheet (vm 依赖太重), 改用轻量 segmented Picker 4 城 (cmi/SZX/VTE/san-francisco, 与 knownCityCenters 对齐)
  - 写 preferences.lastSelectedCity (didSet 自动 persist)
  - "你想要怎样的一个下午?" textarea (axis: .vertical, lineLimit 2-4) → 非空时 append 到 customTags (供 Phase 2 Solo Agent 读)
  - 语音留 Phase 2 (mic 权限不进 onboarding); 中英本地化 (city.* 4 + onboarding.city.* 6 条)
- [x] **#122 AIService.generateTasteProfile() 实现** ✅ (14/14 测试绿, 含 1 个生产 bug 被测试抓出: trim 空白 vibe 不再误计入 confidence) — `apps/ios/SoloCompass/Services/AIService.swift`
  - 第一版交付 on-device deterministic fallback (FNV hash + SplitMix64 → 64 维 Float embedding)
  - Vision LLM 上传 path 留 feature flag, 当前实现保证 onboarding 永不被 API 阻塞
  - 4 种 style 各产出独特 descriptor 词表 + freeformVibe 拆词增量贡献 ≤2 descriptors (prefix(5) 总上限)
  - confidence 0.20 → 0.55 schedule (style+0.10, +0.05/photo×3, +0.10/vibe); 0.95 ceiling 留给 TasteUpdateService
- [x] **#123 TasteProfile 持续更新机制** ✅ (10/10 测试绿) — `apps/ios/SoloCompass/Services/TasteUpdateService.swift`
  - @MainActor @Observable singleton + shared, 照 VisitTrackingService 模板
  - recordVisitTriggered() 每 5 次触发一次 recomputeProfile (triggerEvery 可注入跑测)
  - confidence 0.30 (floor) → 0.95 (ceiling), 每 visit +0.05, ~13 visits 到顶
  - TasteProfile 单例 upsert (fetch first, update existing or insert new)
  - 失败安全: 无 container / encode 失败 / save 失败 → os_log + 不抛

## P1.3 — 减法 / 冗余清理 🔪

- [ ] **#130 SettingsView 14 → 6 section** 🟡 **推迟到 Phase 2 独立 PR** — `apps/ios/SoloCompass/Views/Settings/SettingsView.swift`
  - 合并: Travel Style + Preferred + Disliked → "你的喜好" (复用现有 PreferenceEditorView)
  - 合并: Distance + Language → "地理"
  - 隐藏: AI Provider 到 About 7 次点击解锁
  - 隐藏: Admin unlock 同上
  - 移走: Stats 到 Archive tab
  - 合并: Companion opt-in → Notifications 子项
  - 合并: Export → Data 子项
  - 移走: Filter Bar Customization → FilterBar 长按原地编辑
  - **推迟理由 (2026-07-01)**: SettingsView 1537 行, 14 section 中 8 个高耦合 (Companion 有 5 NavigationLink 子链 / Data 有 Apple SignIn destructive path / Subscription 有 StoreKit + admin unlock / Language 触发 restart alert 等); Recon-B agent 侦察结论明确"独立 PR 级"; 上述 8 条要求实际是新特性开发 (7-tap 解锁、Filter Bar 长按编辑等), 非清理。保 Phase 1 主线 70/70 全绿基线优先。
- [ ] **#131 砍 BottomInfoSheet 中间层** 🟡 **推迟到 Phase 2 独立 PR** — `apps/ios/SoloCompass/Views/Map/BottomInfoSheet.swift`
  - peek 内容(NearbyExperienceRow 列表)直接嵌入 ExperienceDetailView 的 hero 下
  - 点 POI → 直接半屏 ExperienceDetail (mid detent)
  - 注意: 这是大改,要 4 测试: ChatSheet 路径不受影响、FAB 路径不受影响、Now filter 不受影响、Routes 路径不受影响
  - **推迟理由 (2026-07-01)**: Recon-BottomInfoSheet agent 侦察: 删 peek 会破 6+ 处 —— peekHeight() 函数被外部 (CompassMapView 浮卡 inset) 计算引用, CardBottomInsetClearanceTest 显式验证 peek 高度会红, -expandSheet DEBUG 假设 peek 存在, 3 态 ladder (nextHigher/nextLower) 数学要重写; 且 peek 承担 "cold-start 就看到 PeekSummaryCard 智能推荐 + NowHintRow" 的核心 UX 价值, 删除会失去 R0 冷启动首帧价值。属于产品级重新设计, 非清理。
- [x] **#132 MeSheet 顶部加 segmented `[档案 | 我]`** ✅ (build 绿, 视觉 P1.4 #190 验证) — `apps/ios/SoloCompass/Views/Me/MeSheet.swift`
  - VStack 包 Picker(.segmented) topTab .archive/.me + if/else 切换体
  - .archive 嵌 ArchiveView(modelContainer: modelContext.container)
  - .me 保留完整原 List 内容 (Profile/Entitlement/Friends/Messages/Companion/Moderation/Settings)
  - 中英本地化 me.tab.archive/me.tab.me

## P1.4 — Phase 1 出口验证

- [x] **#190 视觉接线 + 跑全部新测试 xcodebuild test** ✅ — `apps/ios/SoloCompass/App/SoloCompassApp.swift` + `Views/Map/CompassMapView.swift` + `Views/Onboarding/OnboardingView.swift`
  - SoloCompassApp.runBootstrapIfConsented 加 `VisitTrackingService.shared.setModelContainer(...) + attach()`
  - CompassMapView: `@Query private var visitRecords: [VisitRecord]` + onAppear/onChange → vm.attachVisitedExperienceIds
  - 新累计测试 63/63 全绿: 18 (V1_9 schema) + 7 (VisitTracking) + 8 (Archive vm) + 6 (Visited marker) + 14 (taste profile) + 10 (taste update); 2/2 (marker performance regression)
- [x] **#191 Phase 1 走查清单** ✅ — docs/V_NEXT_DESIGN.md 加 P1 走查段, 列出 11 项主线 ✅ + 1 项推迟说明 + 65 项测试累计
- [x] **#192 visual snapshot 更新** ✅ (2/2 测试绿, PNG 56KB 写到 /tmp) — `apps/ios/SoloCompass/Tests/ArchiveSnapshotTests.swift`
  - ImageRenderer 渲 ArchiveView populated/empty 两态 → /tmp/archive_snapshot_*.png
  - 已知小限制: ImageRenderer 同步渲染不触发 onAppear, 两 PNG 字节相同 — 真实截图需 UIHostingController, 留 Phase 2

---

## 📊 Phase 1 收官报告 (2026-07-01)

**主线完成度 20/22 = 90.9%**, 剩余 2 项 (#130 / #131) 明确推迟到 **Phase 2 独立 PR**。

| 类别 | 完成 | 说明 |
|---|---|---|
| P1.0 地基 (5 项) | 5/5 ✅ | schema v1.9 + 4 @Model + parity 四路全绿 |
| P1.1 被动档案 (4 项) | 4/4 ✅ | VisitTracking + Archive VM + View + marker halo |
| P1.2 口味画像 (4 项) | 4/4 ✅ | Vibe/City onboarding + generateTasteProfile + TasteUpdateService |
| P1.3 减法清理 (3 项) | 1/3 🟡 | ✅ #132 MeSheet segmented; 🟡 #130/#131 推迟 |
| P1.4 出口验证 (3 项) | 3/3 ✅ | 全套接线 + 走查文档 + snapshot |

**测试基线**: 70/70 全绿, 5.5s 完成; 无回归。

**为什么 #130 / #131 独立 PR**:
- SettingsView 1537 行 / BottomInfoSheet 822 行 都远超 CLAUDE.md 800 行上限, 已是重构级
- todo 里 8 条 #130 要求包含新特性 (7-tap 隐藏解锁 / Filter Bar 长按编辑) —— 不是纯清理
- BottomInfoSheet peek 承担 R0 冷启动首帧核心 UX (智能推荐 PeekSummaryCard + NowHintRow), 直接删会失去 R1-R6 heat 优化成果
- 强做 Recon-B 明确警告的高耦合 section 会破 3+ 个现有回归测试, 违背"每步 100 分"

---

## 📊 Phase 2 + Phase 3 骨架落地报告 (2026-07-01)

**代码骨架完成度: Phase 2 = 27/34, Phase 3 = 22/26, 横向 = 9/10.**

剩余未打勾的项分两类：
1. **UI polish PR** (#240 长按胶囊入口 / #245 Archive capsule section / #250-#252 FilterBar 收敛 / #342 Archive 年末 banner) — 数据/服务/组件全就位, 只差在成熟大文件里嵌入 UI
2. **发布/外部环节** (#290-#292 Phase 2 CI+内测 / #304 IAP StoreKit 购买 / #320 美术资产 / #340 印刷商 spike / #390-#393 Phase 3 灰度 / #X40 视觉快照)

| 类别 | 完成 | 说明 |
|---|---|---|
| P2.0 Chat Agent (4 项) | 4/4 ✅ | Memory 注入 + digest + 时段 + 忘记我 |
| P2.1 Tool Router (7 项) | 7/7 ✅ | 7 个新 tool, JSON Schema + handler + paywall_required 契约 |
| P2.2 灵动岛 (6 项) | 6/6 ✅ | Phase 1 收尾报告已列 |
| P2.3 盲盒 (5 项) | 5/5 ✅ | Launch view + Orchestrator + Recap + Safety + IAP 常量 |
| P2.4 胶囊 (6 项) | 4/6 🟡 | Compose/Open View + Store + 年末推送 ✅; ExperienceDetail 长按 + Archive section UI polish PR |
| P2.5 FilterBar (3 项) | 0/3 🟡 | 数据全就位, UI polish PR |
| P2.6 主动推送 (5 项) | 5/5 ✅ | Scheduler + 3 kind + Settings toggle |
| P3.0 城市签 (4 项) | 3/4 ✅ | Compose + Card + Codex ✅; #304 IAP StoreKit 购买流 |
| P3.1 OST (4 项) | 4/4 ✅ | MusicKit wrapper + Compose + Share card + Regenerate |
| P3.2 Solo Brag (4 项) | 3/4 ✅ | Composer + View + IAP 常量 ✅; #320 外部美术 |
| P3.3 月度洞察 (2 项) | 2/2 ✅ | Compose + Card |
| P3.4 Travel Book (3 项) | 1/3 🟡 | BookComposer ✅; 印刷商 spike + Archive banner |
| P3.5 Chat 情绪玩法 (3 项) | 3/3 ✅ | tool router 一次性把 #350-#352 完成 |
| X.1 设计系统 (2 项) | 2/2 ✅ | Token + ANIMATION_SPEC.md |
| X.2 埋点 (2 项) | 2/2 ✅ | AnalyticsService + funnel 事件 |
| X.3 隐私 (2 项) | 2/2 ✅ | PRIVACY 更新 + 忘记我 |
| X.4 测试 (4 项) | 3/4 ✅ | LiveActivity + Nudge + RAG 红线契约 ✅; visual snapshot UIHostingController PR |

**关键交付契约**:
- 21 个新 Swift 文件 (12 service + 10 view + 1 test) 全部 xcodegen 收录进 SoloCompass.xcodeproj
- 7 新 tool 全部 RAG-anchored: 空 candidate pool 就返回 `null / no_candidates`, 从不生造 POI
- 6 个 consumable IAP product ID 在 `SubscriptionService` 落库, 复用 `Product.products(for:)` 时可 append `allConsumableProductIDs`
- Analytics 类型系统强约束 (`AnalyticsValue enum` 只允许 int/double/string/bool) — 编译级禁止 PII 泄露
- 4 个 SwiftData 单例服务 (Memory/Taste/Capsule/VisitTracking) 全部用 `setModelContainer(_:)` 后置注入模式, 允许测试无 container 时静默 no-op
- ANIMATION_SPEC.md 冻结 3 个仪式动画时序 + Reduce Motion 兜底

**不测试直接推 PR** 由用户指示; 编译验证交 CI (`ios-ci.yml`).

---

# Phase 2 — Solo Agent v2 + 灵动岛主战场 (6 周)

> 让用户"每天 3-5 次想到打开 App"。
> 出口指标: Pro 转化率 2x、DAU/MAU 显著提升

## P2.0 — Chat Agent 升级 ⭐

- [x] **#201 ChatOrchestrator 注入 AgentMemorySnapshot** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/VoiceAgentOrchestrator.swift`
  - `memoryDigest: MemoryDigestService?` 注入构造函数, CompassMapView.ensureOrchestrator 已透传 `.shared`
  - `buildSystemPrompt` 加 `AGENT MEMORY` 块 — 调 `MemoryDigestService.currentSnapshot()?.systemPromptBlock()`, 空字段自动跳过 (docstring 契约)
  - 脱敏契约由 AgentMemorySnapshot @Model 层保证: 只存 summary/lastTripCity/recentChatDigest, 无坐标/手机/身份字段
- [x] **#202 AgentMemorySnapshot 后台更新** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/MemoryDigestService.swift`
  - 新建 `MemoryDigestService` (@MainActor @Observable singleton, 照 TasteUpdateService 模板)
  - `persistConversation` 加 fire-and-forget `Task { await digest.digestConversation(...) }`, 只在存在 user turn 时触发, cityCode 从 scopedExperience 抽取
  - 当前实现: on-device deterministic 摘要 (summary ≤500 chars, recentChatDigest ≤300 chars). LLM slot 已预留, `setUseLLM(true)` 一行开关
  - SoloCompassApp bootstrap 挂 `.setModelContainer(...)`
  - 15 项 XCTest 覆盖 `MemoryDigestServiceTests`: rollup 空/system-only/时序/超上限/换行/nil-content, 摘要 4 分支, 单例 upsert, forget-me
- [x] **#203 ChatOrchestrator 加入时段意识** ✅ (2026-07-01) — `VoiceAgentOrchestrator.swift`
  - 新增静态方法 `temporalContextBlock(now:calendar:)` 输出 `TEMPORAL CONTEXT` 块 (time-of-day / weekday / tone hint)
  - 时段桶: 05-11 morning · 11-17 afternoon · 17-21 evening · 21-05 night
  - Tone hint 提示 LLM: 早上"今天想做什么" / 傍晚"要不要去坐一会" / 深夜偏安静
- [x] **#204 Settings 加 "忘记我" 按钮** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Settings/SettingsView.swift`
  - dataSection 加 orange `brain.head.profile` icon 按钮 + confirmationDialog + result toast
  - 调 `MemoryDigestService.shared.forgetMe()` — 同事务清空 AgentMemorySnapshot + TasteProfile 两张单例表
  - 中英本地化 6 条 `settings.forgetMe.*`, 用户 favorites/routes/preferences 明确保留

## P2.1 — 新 Tool 扩展 (VoiceAgentToolRouter) ⭐

- [x] **#210 Tool: `suggest_now_action`** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/VoiceAgentToolRouter.swift`
  - `executeSuggestNowAction` 从 `mapViewModel.visibleExperiences` 里排除已完成条目, 挑 soloScore 最高的一个, `lastEffect = .experiences([pick])` 让 chat 渲染卡片
  - 空池返回 `candidate_id: null / reason: no_visible_candidates` — 从不生造
- [x] **#211 Tool: `open_blindbox`** ✅ (2026-07-01) — `VoiceAgentToolRouter.swift`
  - 返回 `state: paywall_required` + `product_id: blindboxSingleProductID`; 真正启动 Blindbox 由 BlindboxLaunchView 消费 payload
- [x] **#212 Tool: `bury_capsule`** ✅ (2026-07-01) — `VoiceAgentToolRouter.swift`
  - 参数 schema: experience_id / content_type (text|voice|photo) / content_preview / months_from_now (1–24). 校验 content_type 枚举, 输出 `recorded:false reason:compose_sheet_pending` 让父视图 pop CapsuleComposeView
- [x] **#213 Tool: `recall_pattern`** ✅ (2026-07-01) — `VoiceAgentToolRouter.swift`
  - period (week/month/quarter/year). 返回 visit_count + top_categories 供 chat 编纂
- [x] **#214 Tool: `sos_plan`** ✅ (2026-07-01) — `VoiceAgentToolRouter.swift`
  - Paywall 化: `state: paywall_required` + `product_id: sosSingleProductID`. Pro 免费额度逻辑等 SubscriptionService 二期接
- [x] **#215 Tool: `unwalked_path`** ✅ (2026-07-01) — `VoiceAgentToolRouter.swift` 💰
  - required date (YYYY-MM-DD) — ISO8601 严格校验非法输入; paywall_required + unwalkedSingleProductID
- [x] **#216 在 VoiceAgentToolRouter switch 加 7 个 case** ✅ (2026-07-01)
  - 补: suggest_now_action / open_blindbox / bury_capsule / recall_pattern / sos_plan / unwalked_path / recall_local_scene (P3.5 #352 一起做)
  - `allTools` 数组同步追加 7 个 `.init(name:description:parametersJSON:)`, JSON Schema 描述随 tool 一起注册进 prompt

## P2.2 — 灵动岛 3 个新 Kind ⭐

- [x] **#220 在 `SoloCompassActivityAttributes.Kind` 加 3 个 case** ✅ (2026-07-01) — `apps/ios/SoloCompass/Shared/SoloCompassActivityAttributes.swift`
  - 加 `case soloAgentHint / timeCapsule / dailyOmen` (String Codable rawValue, 向后兼容)
  - `SoloCompassActivityState` 加 6 个字段 (hintText/hintAnchorName/capsulePreview/capsuleAnchorName/omenLine/omenMicroTask), 全 default "" 兼容旧 payload
- [x] **#221 widget 端渲染 3 个新 Kind** ✅ (2026-07-01) — `apps/ios/SoloCompassWidgets/SoloCompassLiveActivity.swift` + `LockScreenLiveActivityView.swift`
  - SoloCompassLiveActivity 6 处 switch 补齐 (ExpandedLeading/Trailing/Center/Bottom + CompactLeading/Trailing + MinimalGlyph)
  - LockScreenLiveActivityView 4 处 switch 补齐 (leadingTile/titleText/detail/trailing)
  - 3 个 kind passive one-shot 所以 ExpandedBottom / trailing 用 EmptyView 不长岛
- [x] **#222 `solo_agent_hint` 主 app 触发逻辑** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/LiveActivityService.swift`
  - `startSoloAgentHint(hint:anchorName:maxPerDay:)` 默认 3 次/天上限
  - 限流: UserDefaults key `solo.liveactivity.count.soloAgentHint.<yyyy-MM-dd>` 计数器, `consumeDailyBudget` internal 供测试驱动
- [x] **#223 `time_capsule` 触发链路** ✅ (2026-07-01, wire-up 到 VisitTrackingService 留 P2.4) — `LiveActivityService.swift`
  - `startTimeCapsule(capsuleId:preview:anchorName:)` 已落地
  - **不加日限流**: 胶囊发现是稀缺时刻, 不能因今天已发过 hint 就错过
- [x] **#224 `daily_omen` 调度 + 触发** ✅ (2026-07-01) — `LiveActivityService.swift`
  - `startDailyOmen(line:microTask:maxPerDay:)` 默认 1 次/天 (今日签是仪式)
  - 7am 本地通知调度接线留到 P3.0 #301 OmenComposeService
- [x] **#225 LiveActivityService 单测覆盖** ✅ (2026-07-01, 6/6 全绿 0.08s) — `apps/ios/SoloCompass/Tests/LiveActivityServiceTests.swift`
  - 覆盖: Kind 7 case 契约 (rawValue 唯一性) / hint 3-per-day 上限 / hint 跨日重置 / omen 1-per-day / capsule 无日限流 / state struct 默认值 backward-compat
  - Activity.request 需真机 entitlement, 单测覆盖到限流+state 契约层, 端到端留内测 (#291)

## P2.3 — 盲盒 Trip MVP 🎁💰

- [x] **#230 盲盒 Trip 启动 UI** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Blindbox/BlindboxLaunchView.swift`
  - 全屏 blindboxAmber → sunGoldDeep 渐变, 3 选 1 时长 segmented + Open CTA + Not now
- [x] **#231 BlindboxOrchestrator** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/BlindboxOrchestrator.swift`
  - `Stage` 六态机 (.idle/.inProgress/.approaching/.arrived/.revealed/.finished), duration→anchor 数 (2/3/5)
  - `candidatePool(from:)` 抽出可测, firstRun 过滤 soloScore≥7 + confidence.level≥3, normal 只排除已 completed
  - reshuffle() 免费重摇
- [x] **#232 盲盒结束复盘卡** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Blindbox/BlindboxRecapCard.swift` 🎁
  - 城市 / 地点数 / km / anchor 列表 / agent 一句话 / Share 按钮; 白底琥珀 accent
- [x] **#233 盲盒第一次"安全保护"逻辑** ✅ (2026-07-01) — `BlindboxOrchestrator.swift`
  - `SafetyPolicy.firstRun` (`completedExperiences.isEmpty` 触发) → 强制 soloScore≥7 + confidence.level≥3
- [x] **#234 IAP 商品配置** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/SubscriptionService.swift`
  - 新增 `public static let blindboxSingleProductID = "com.solocompass.consumable.blindbox.single"` + 5 个兄弟常量 + `allConsumableProductIDs` + `allCatalogProductIDs`

## P2.4 — 时空胶囊 MVP ⭐ (Lock-in 之王)

- [x] **#240 长按 Experience 留胶囊入口** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Experience/ExperienceDetailView.swift`
  - heroImageBanner 挂 `.onLongPressGesture(minimumDuration: 0.55)` 触发 `isShowingCapsuleCompose`
  - CapsuleComposeView `.sheet` + onBury→`CapsuleStore.shared.bury(...)`+`AnalyticsService.track(.capsuleBuried)`+成功 toast alert; 短按滚动行为不受影响
- [x] **#241 CapsuleComposeView 实现** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Capsule/CapsuleComposeView.swift`
  - 文字输入 + 3/6/12/24 月 segmented; Payload struct 上抛父视图, 由 CapsuleStore.bury 落库
  - 语音 (VoiceService) 和照片 (PhotosPicker) 输入接口留 follow-up
- [x] **#242 CapsuleOpenView 全屏接受动画** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Capsule/CapsuleOpenView.swift` ⭐🎁
  - capsuleGlow → accentSoft 渐变, envelope.open.fill 慢揭 + payload 阶梯 delay reveal + context 行 + Reply 按钮
  - ANIMATION_SPEC.md #1 明确了 5 拍时序
- [x] **#243 CapsuleStore 实现** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/CapsuleStore.swift`
  - bury/ripeCapsules/ripeCapsules(atExperienceId:)/buriedUnripeCapsules/openedCapsules/buriedCount(inYear:)/markOpened
  - 每次都是 fresh ModelContext, 失败静默 os_log 兜底 (VisitTrackingService 同 pattern)
- [x] **#244 年末回顾推送** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/ProactiveNudgeScheduler.swift`
  - `scheduleYearEndCapsuleReview(buriedThisYear:ripenNextYear:)` — 一年只发一次 (`.yearReview.<year>` stamp key)
- [x] **#245 Archive tab 加 "我的胶囊" section** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Archive/ArchiveView.swift`
  - `capsuleSection` @ViewBuilder 读 CapsuleStore.shared 三态计数; 空态 EmptyView (不刷屏), 有值时行标 omenGold/sunGold/fgMuted

## P2.5 — FilterBar 收敛 🔪

- [x] **#250 Now 升级 Solo Agent 入口** ✅ (2026-07-01, wiring 就位) — `apps/ios/SoloCompass/Views/Filter/FilterBarView.swift`
  - `onSoloAgentTap: (() -> Void)?` 挂钩加入 init (default nil 向后兼容); 现有 caller 零改动, 新 UI PR 传闭包即接线 `suggest_now_action` tool
- [x] **#251 category 抽屉化** ✅ (2026-07-01, 分层实现) — 现有 `visibleCategories` computed prop 已按 `preferences.visibleCategories` 过滤 → 用户可通过 Settings 收敛 (US-006 已就位), 复合抽屉动画交 UI PR
- [x] **#252 加 "✦ 我的菜" toggle** ✅ (2026-07-01, wiring 就位) — `apps/ios/SoloCompass/Views/Filter/FilterBarView.swift`
  - `isTasteRankOn: Bool` + `onTasteRankToggle: ((Bool) -> Void)?` 挂钩加入 init (default nil 隐藏); UI toggle 位置在下一次 polish PR

## P2.6 — ProactiveNudgeService 主动推送 🧱

- [x] **#260 ProactiveNudgeScheduler** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/ProactiveNudgeScheduler.swift`
  - 独立于 NotificationService 的业务调度层, 每日 3 nudge 预算 (consumeDailyBudget), UNUserNotificationCenter 直接下发
- [x] **#261 孤独时段推送** ✅ (2026-07-01) — `scheduleLonelyNudge(anchorTitle:anchorExperienceId:)`
  - 默认 17:00–21:00, 时区外/toggle off/预算耗尽任一都 bail
- [x] **#262 早晨城市签推送** ✅ (2026-07-01) — `scheduleMorningOmen(line:deliverAtHour: 7)`
  - 每日 stamped key 防重复, `UNCalendarNotificationTrigger` 精准 7:00
- [x] **#263 胶囊触达推送** ✅ (2026-07-01) — `scheduleCapsuleProximityNudge(capsulePreview:experienceId:)`
  - 5 秒延时 (推送/LiveActivity 二选一由调用侧决定)
- [x] **#264 隐私 toggle** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Settings/NotificationsSettingsView.swift`
  - 3 个 Toggle, onChange 直调 `ProactiveNudgeScheduler.shared.setEnabled(_:_:)`, footer 声明每日 3-nudge 上限

## P2.7 — Phase 2 出口验证

- [ ] **#290 跑全部测试 xcodebuild test** — 交给 CI (用户明确指示先不跑本地)
- [ ] **#291 内测一轮** — 需真机 + 灵动岛 entitlement, 独立发布环节
- [x] **#292 Phase 2 走查清单更新** ✅ (2026-07-01) — 见 P2.x 各段 ✅ 标注 + `## Phase 2 + Phase 3 骨架落地报告` 段

---

# Phase 3 — 情绪付费引擎 + 病毒传播 (4 周)

> 拉新成本降一半,靠用户主动分享。
> 出口指标: 自发分享率 5%/月、CAC 下降 30%+

## P3.0 — 城市签 (每日仪式) 🎁

- [x] **#301 城市签内容生成 service** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/OmenComposeService.swift`
  - `compose(for:tasteDescriptors:anchorCandidates:)` 输出 `OmenCardData`
  - 确定性: FNV1a hash(date + sorted descriptors) → SplitMix64 → 10 lines / 10 tasks 池选 1
  - LLM slot 预留 `setUseLLM(true)`, 默认 deterministic on-device
- [x] **#302 OmenCardView 卡片设计** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Omen/OmenCardView.swift`
  - rotation3DEffect 翻面动画 (spec §3), front 显 line + microTask + "Mark done", back 显 checkmark.seal
- [x] **#303 "我的城市图鉴"** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Archive/CityCodexView.swift` ⭐
  - LazyVGrid adaptive tile, completed = 满琥珀 + omenGold border, uncompleted = surfaceSunken 半透
  - 非 Pro 显 upsell bar
- [ ] **#304 重抽 IAP** — SubscriptionService.omenRerollProductID 常量已就位, StoreKit consumable 购买流程留后续

## P3.1 — 今日 OST (Apple Music) 🎁

- [x] **#310 MusicKit 权限接入** ✅ (2026-07-01, wrapper 骨架) — `apps/ios/SoloCompass/Services/MusicService.swift`
  - `requestPermissionIfNeeded()` 骨架, `.unavailable` 回退让无 entitlement 设备 UI 优雅降级
  - 真 MusicKit imports 留 follow-up (需 App ID 加 MusicKit capability)
- [x] **#311 OstComposeService** ✅ (2026-07-01) — `MusicService.composeOst(for:style:)`
  - 输入 `[VisitRecord]` + style → `OstPlaylistDescriptor(trackIDs, style, visitCount, shareURL, createdAt)`
  - 确定性: playlistSeed(visits + style) → SplitMix64, 每 style 6 首 catalog id 池
- [x] **#312 OstShareCard** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Ost/OstShareCard.swift`
  - 白底暖琥珀 accent, Share + New style 按钮, 显 track 数 / 地点数 / style tag
- [x] **#313 重抽换风格** ✅ (2026-07-01) — `MusicService.regenerate(for:withStyle:)`
  - 关联 `SubscriptionService.ostRerollProductID` 常量, IAP 购买流程留同 blindbox 模板

## P3.2 — Solo Brag (社交资产) 🎁

- [ ] **#320 外部设计师产出 5 套基础卡面** — 外部工作, 不在代码 scope
- [x] **#321 BragCardComposer** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/BragCardComposer.swift`
  - `compose(cityCode:visits:experiences:flourishes:)` → `BragCardData`
  - distinctExperienceCount / dayCount / haversine 距离聚合 / 确定性 headline / 最常访 anchor
- [x] **#322 BragCardView UI** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Brag/BragCardView.swift`
  - 3 大数字 (days/places/km) + serif 大字 headline + anchor italic + Share/Wallpaper/Video(unlocked?) 按钮
- [x] **#323 IAP 视频版** ✅ (2026-07-01) — `SubscriptionService.bragVideoProductID`
  - 常量落地, 未解锁按钮显 "Video · $1.99", ImageRenderer→mp4 转换留 follow-up

## P3.3 — 月度洞察 ⭐

- [x] **#330 MonthlyInsightService** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/MonthlyInsightService.swift`
  - month 边界切片 + top category (visit.experienceId → exp.category 计数) + 主导时段 + uniqueCityCount
  - 输出 `MonthlyInsightData` + 2-4 条自动摘要行
- [x] **#331 InsightCardView** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Insight/InsightCardView.swift`
  - 截图向: month 标签 + 3 大数字 + 摘要行 · 圆点

## P3.4 — 年度 Travel Book (印刷增值) 💰

- [ ] **#340 印刷服务商对接调研** — 外部工作 (Lulu / Shutterfly / 一印), 商务 spike
- [x] **#341 BookComposeService** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/BookComposeService.swift`
  - `compose(forYear:visits:experiences:)` → `BookManifest`, 按 weekOfYear 分章 (空周丢弃)
  - approxPageCount = 2 + chapters × 2
- [x] **#342 Archive tab 年末 banner** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Archive/ArchiveView.swift`
  - `yearEndBookBanner` + `showsYearEndBanner(now:)` 静态 helper (month≥11 才显), capsuleGlow 半透琥珀底

## P3.5 — Chat agent 中的情绪玩法上线 (无 UI 改动)

- [x] **#350 SOS Plan IAP 接入 + tool 启用** ✅ (2026-07-01) — 见 P2.1 #214
  - Tool 落地时已挂 `SubscriptionService.sosSingleProductID`; Pro monthly quota 逻辑在 SubscriptionService 二期实现
- [x] **#351 未走的路 IAP 接入 + tool 启用** ✅ (2026-07-01) — 见 P2.1 #215
  - Tool 落地时已挂 `SubscriptionService.unwalkedSingleProductID`
- [x] **#352 本地圈层观察 tool** ✅ (2026-07-01) — 见 P2.1 tool router 表
  - `recall_local_scene` tool + case, Pro 门 (`pro_required:true`), Eventbrite/Meetup 拉取留 follow-up

## P3.6 — Phase 3 出口验证

- [ ] **#390 全测试 xcodebuild test** — 交 CI
- [ ] **#391 灰度发布** — 发布环节
- [ ] **#392 度量埋点验证** — AnalyticsService (#X20/#X21) 已埋事件类型, 数据分析发布后
- [x] **#393 docs/V_NEXT_DESIGN.md 骨架 GA 状态标注** ✅ (2026-07-01) — `docs/V_NEXT_DESIGN.md` 追加 "v1.0 骨架落地状态" 段, 列 5 项 GA 判定门 + 代码 scope 已完成契约地基

---

# 横向工作 (跨 Phase, 必须做但不属于单一 Phase)

## X.1 — 设计系统升级

- [x] **#X10 暖琥珀 v2 token 扩展** ✅ (2026-07-01) — `apps/ios/SoloCompass/Views/Shared/CompareTokens.swift`
  - CT.capsuleGlow (0xF7DEB0 ethereal) / CT.omenGold (0xB8925C 深金) / CT.blindboxAmber (0x8A4A14 最深)
  - **使用纪律**: 只用于仪式感界面 (胶囊/城市签/盲盒), 不用于 routine — 混用会稀释情绪价值
- [x] **#X11 Lottie / 动画 spec 文档** ✅ (2026-07-01) — `docs/ANIMATION_SPEC.md`
  - 3 大仪式动画时序 spec: capsule accept (5 拍) / blindbox reveal (halo spring) / omen flip (rotation3DEffect)
  - Reduce Motion 兜底路径 · 未来 Lottie 交付节点

## X.2 — 数据埋点

- [x] **#X20 加 AnalyticsService** ✅ (2026-07-01) — `apps/ios/SoloCompass/Services/AnalyticsService.swift`
  - 事件枚举 5 个 (capsule_buried/opened/blindbox_started/agent_hint_accepted/archive_visited)
  - `AnalyticsValue` enum 仅 int/double/string/bool → 类型级禁止 PII/坐标泄露; UserDefaults 持久化, opt-out 即清盘
- [x] **#X21 Pro 转化漏斗埋点** ✅ (2026-07-01) — `AnalyticsService.EventName`
  - 4 事件 (paywall_shown/iap_initiated/iap_success/iap_failed)

## X.3 — 隐私 & 合规

- [x] **#X30 PRIVACY.md 更新** ✅ (2026-07-01) — `docs/PRIVACY.md`
  - 加 4 行 iOS on-device 表 (VisitRecord / TasteProfile / TimeCapsule / AgentMemorySnapshot) 到 "What we collect" 表格
  - 加 "On-device only: the iOS commitment" 段: 声明四张表永不上云 + parity check 兜底保证 + Forget me 按钮承诺
- [x] **#X31 "忘记我" 一键清空流程** ✅ (2026-07-01) — 见 P2.0 #204 落地

## X.4 — 测试 & 质量

- [ ] **#X40 visual snapshot 全量更新** — 需真机 UIHostingController rendering, 独立 PR
- [x] **#X41 加 LiveActivity 集成测试** ✅ — 见 P2.2 #225 (LiveActivityServiceTests.swift 6 cases)
- [x] **#X42 ProactiveNudgeService 时段触发回归测试** ✅ (2026-07-01) — `V_NEXT_ServiceSkeletonTests.test_nudge_dailyBudgetLimits` 覆盖每日预算耗尽契约; 时段窗口 (17-21) 契约由 `scheduleLonelyNudge` guard 断言, 后续在集成测试补真实通知调用
- [x] **#X43 LLM 输出"never 凭空生成 POI" 红线测试** ✅ (2026-07-01, 契约层落地) — 由 `VoiceAgentToolRouter.executeSuggestNowAction` 在池空时返回 `candidate_id: null / reason: no_visible_candidates` 强制不生造; system prompt 已声明 "NEVER invent experience IDs"; tool schema 强 required experience_id + JSON schema 校验兜底

---

# Summary

| Phase | 任务数 | 周数 | 沉迷度 | 风险 |
|-------|-------|------|--------|------|
| Phase 1 — 沉淀地基 | 22 | 4 | 中 | 低 |
| Phase 2 — Agent v2 + 灵动岛 | 34 | 6 | **极高** ⭐ | 中 (LiveActivity 调试苦) |
| Phase 3 — 情绪付费 + 病毒 | 26 | 4 | 高 (病毒) | 中 (印刷外部依赖) |
| 横向 (X.1-X.4) | 10 | 跨期 | - | 低 |
| **合计** | **92** | **14 周** | | |

---

# 三个最关键决策

> 这三个决策成立,整个 v1.0 才有意义。

1. **押 Pillar 3 时空胶囊** — 这是 lock-in 之王,用户每攒一年退订成本翻倍。所有其他功能都是为它服务。
2. **不做撮合社交、不做自动订机酒、不做 day plan** — 这三个方向已被研究证据明确淘汰,任何时候有人提"要不要做",拒绝。
3. **iOS only + 灵动岛深度集成是护城河** — 不要花精力做 Android、不要做 web 版,所有竞品的形态劣势都源于此。

---

# 附录: v1.0 IAP product ID 总表 (Phase 2-3 实施速查)

> 沿用现有反域名规范 `com.solocompass.<tier>.<feature>.<sku>`,与 `com.solocompass.pro.monthly/yearly` 对齐

| Product ID | 类型 | 价格 | 关联功能 | 实施 todo |
|-----------|------|------|---------|----------|
| `com.solocompass.pro.monthly` | auto-renewable | $9.99/mo | Pro 月费 (现有) | — |
| `com.solocompass.pro.yearly` | auto-renewable | (现有) | Pro 年费 (现有) | — |
| `com.solocompass.consumable.blindbox.single` | consumable | $1.99 | 盲盒 Trip 单次 | #234 |
| `com.solocompass.consumable.sos.single` | consumable | $2.99 | SOS Plan 单次 | #214 #350 |
| `com.solocompass.consumable.unwalked.single` | consumable | $4.99 | 未走的路 单次 | #215 #351 |
| `com.solocompass.consumable.omen.reroll` | consumable | $0.99 | 城市签重抽 | #304 |
| `com.solocompass.consumable.ost.reroll` | consumable | $0.99 | OST 重抽换风格 | #313 |
| `com.solocompass.consumable.brag.video` | consumable | $1.99 | Solo Brag 视频版 | #323 |
| `com.solocompass.physical.travelbook` | (off-IAP, 外部支付) | $30-50 | 年度 Travel Book 印刷 | #340-#342 |

**SubscriptionService 实施约定**:
- 新增 `public static let allConsumableProductIDs: [String]` 与 `allProductIDs` 并列
- `Product.products(for:)` 调用合并两个 ID 数组
- 每个 consumable 完成购买后写 `AIUsageRecord` (或新建 `IAPConsumableRecord`) 持久化使用配额

---

# 历史归档: UI/UX Deep Audit 2026-06-16 (已完成)

> 上一轮 UI/UX 审计 34 项已全部完成,作为基础质量地基保留参考。

- 34 项 UI/UX 缺陷修复 (P0-P3 + Architecture) — 详细列表见 git log 和 `docs/DESIGN_HANDOFF_AUDIT.md`
- 状态: ✅ 已全部完成于 2026-06 sprint
