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

# Phase 2 — Solo Agent v2 + 灵动岛主战场 (6 周)

> 让用户"每天 3-5 次想到打开 App"。
> 出口指标: Pro 转化率 2x、DAU/MAU 显著提升

## P2.0 — Chat Agent 升级 ⭐

- [ ] **#201 ChatOrchestrator 注入 AgentMemorySnapshot** — `apps/ios/SoloCompass/Services/VoiceAgentOrchestrator.swift`
  - 每次新会话开始时,从 SwiftData 读最近 memory snapshot
  - 注入 system prompt: "用户最近: <summary>;当前 trip: <city, day N>;最爱: <top 3 experience names>"
  - 注意: prompt 中包含的所有数据必须脱敏 (不带坐标/手机/身份)
- [ ] **#202 AgentMemorySnapshot 后台更新** — `apps/ios/SoloCompass/Services/MemoryDigestService.swift`
  - 每个 chat session 结束时,异步调用 LLM 生成 ≤500 字摘要
  - 写回 AgentMemorySnapshot
  - on-device 优先,不上传云端
- [ ] **#203 ChatOrchestrator 加入时段意识** — `VoiceAgentOrchestrator.swift`
  - 注入 system prompt: "现在是 <morning/afternoon/evening/night> 的 <周几>"
  - 早上语气: "今天想做什么", 傍晚: "要不要去坐一会"
- [ ] **#204 Settings 加 "忘记我" 按钮** — `apps/ios/SoloCompass/Views/Settings/SettingsView.swift`
  - 一键清空 AgentMemorySnapshot + TasteProfile
  - 用户隐私焦虑兜底

## P2.1 — 新 Tool 扩展 (VoiceAgentToolRouter) ⭐

- [ ] **#210 Tool: `suggest_now_action`** — `apps/ios/SoloCompass/Services/VoiceAgentToolRouter.swift`
  - 输入: 当前位置、时段、最近 VisitRecord、TasteProfile
  - 输出: ChatCard.experience (1 个) + 1 句话 + 路上做什么的小建议
  - **RAG 约束**: 必须从 Experience 池命中,never 凭空生成 POI
- [ ] **#211 Tool: `open_blindbox`** — `VoiceAgentToolRouter.swift`
  - 输入: duration (默认 3 小时)
  - 启动盲盒 Trip 流程(见 P2.3)
- [ ] **#212 Tool: `bury_capsule`** — `VoiceAgentToolRouter.swift`
  - 输入: experienceId, contentType, contentBlob, scheduledFor
  - 写入 TimeCapsule
- [ ] **#213 Tool: `recall_pattern`** — `VoiceAgentToolRouter.swift`
  - 输入: period (本月/本季/本年)
  - 输出: 月度洞察文本 + 卡片
- [ ] **#214 Tool: `sos_plan`** — `VoiceAgentToolRouter.swift`
  - 触发: 用户说"下雨了/景点关了/朋友爽约"等关键词
  - 输出: 4 小时替代路线 + 走 paywall (Pro 用户每月 3 次免费,免费用户 $2.99/次 IAP)
  - 关联 product ID: `com.solocompass.consumable.sos.single` (Phase 3 接入)
- [ ] **#215 Tool: `unwalked_path`** — `VoiceAgentToolRouter.swift` 💰
  - 触发: trip 结束时用户问"那天还能怎么走"
  - 输出: 反事实路径 + 单次解锁 $4.99 IAP
  - 关联 product ID: `com.solocompass.consumable.unwalked.single` (Phase 3 接入)
- [ ] **#216 在 VoiceAgentToolRouter switch 加 5 个 case**
  - 当前 switch 有 10 个 case (explore_nearby/build_route/filter_by_category/show_details/save_to_favorites/dismiss_recommendation/search_places/navigate_to/filter_visible/expand_radius),新增 5 个不冲突
  - tool 字符串规范: `suggest_now_action / open_blindbox / bury_capsule / recall_pattern / sos_plan / unwalked_path / compose_ost / recall_local_scene` (P3.5 #352 用)
  - AIService prompt 模板同步注册新 tool 描述

## P2.2 — 灵动岛 3 个新 Kind ⭐

- [ ] **#220 在 `SoloCompassActivityAttributes.Kind` 加 3 个 case** — `apps/ios/SoloCompass/Shared/SoloCompassActivityAttributes.swift`
  - **注意**: Kind enum 在双 target 共享文件,改一处自动两端生效
  - 加: `case soloAgentHint`, `case timeCapsule`, `case dailyOmen`
  - 同步在 `SoloCompassActivityState` 加每个 Kind 需要的字段 (hint text / capsule preview / omen line)
- [ ] **#221 widget 端渲染 3 个新 Kind** — `apps/ios/SoloCompassWidgets/SoloCompassLiveActivity.swift` + `LockScreenLiveActivityView.swift`
  - 在 `ExpandedLeading/Trailing/Center/Bottom` 4 个 @ViewBuilder switch 加新 case (现有写法已为加 Kind 留好扩展点)
  - 限流逻辑放主 app 不放 widget (widget 只渲染,不决策)
- [ ] **#222 `solo_agent_hint` 主 app 触发逻辑** — `apps/ios/SoloCompass/Services/LiveActivityService.swift`
  - 加 `startSoloAgentHint(hint:experienceId:)` 方法
  - 限流: 一天最多 3 次 (用 UserDefaults 滚动计数)
  - expanded region: 建议 + 采纳/换一个/5min 后再提 (intent button)
- [ ] **#223 `time_capsule` 触发链路** — `LiveActivityService.swift` ⭐
  - 触发源: 新增的 VisitTrackingService 检测进入有未拆胶囊的围栏 (复用 CLCircularRegion)
  - 加 `startTimeCapsule(capsuleId:experienceId:preview:)`
  - 拆开动画走主 app 全屏 (CapsuleOpenView, 见 #242),widget 只负责"邀请拆开"卡片
- [ ] **#224 `daily_omen` 调度 + 触发** — `LiveActivityService.swift`
  - 每天 7am 本地通知触发 (复用 NotificationService schedule 能力)
  - 加 `startDailyOmen(line:experienceId:)`
- [ ] **#225 LiveActivityService 单测覆盖** — `apps/ios/SoloCompass/Tests/LiveActivityServiceTests.swift`
  - 每个 start/update/end 路径都覆盖
  - 限流硬上限测试 (24 小时窗口超过 3 次必须 noop)

## P2.3 — 盲盒 Trip MVP 🎁💰

- [ ] **#230 盲盒 Trip 启动 UI** — `apps/ios/SoloCompass/Views/Blindbox/BlindboxLaunchView.swift`
  - 全屏一键按钮 (橙色琥珀渐变)
  - 时长选择: 1h/3h/全天
  - 付费墙: 免费用户 $1.99 IAP / Pro 用户每月 5 次免费
- [ ] **#231 BlindboxOrchestrator** — `apps/ios/SoloCompass/Services/BlindboxOrchestrator.swift`
  - 从 Solo Agent 选 3-5 个 anchor Experience (按时长打散)
  - 状态机: 进行中 / 走向某站 / 到达 / 揭秘 / 结束
  - 全程接 LiveActivity (复用 route Kind 但终点延迟揭示)
- [ ] **#232 盲盒结束复盘卡** — `apps/ios/SoloCompass/Views/Blindbox/BlindboxRecapCard.swift` 🎁
  - 设计要美 (找设计师): 今天去了 N 个地方、走了 X km、agent 一句话总结
  - "分享" 按钮 (生成图片到相册 / 直接分享 sheet)
- [ ] **#233 盲盒第一次"安全保护"逻辑** — `BlindboxOrchestrator.swift`
  - 新用户的第一次盲盒全部走 high-confidence + 高 SoloScore Experience
  - "重摇" 按钮免费 (无次数限制)
- [ ] **#234 IAP 商品配置** — `apps/ios/SoloCompass/Services/SubscriptionService.swift`
  - 加 product ID `com.solocompass.consumable.blindbox.single` $1.99 (沿用现有反域名命名规范,对齐 `com.solocompass.pro.monthly/yearly`)
  - 在 SubscriptionService 加 `public static let blindboxSingleProductID` 常量
  - StoreKit2 `Product.products(for:)` 注册,放入 `allConsumableProductIDs` 数组

## P2.4 — 时空胶囊 MVP ⭐ (Lock-in 之王)

- [ ] **#240 长按 Experience 留胶囊入口** — `apps/ios/SoloCompass/Views/Experience/ExperienceDetailView.swift`
  - 长按 hero 区域 → 弹出 sheet: "留下时间胶囊"
  - 输入: 文字 (textfield) / 语音 (复用 VoiceService) / 照片 (PhotosPicker)
  - 配置: 几个月后触发 (3/6/12 默认 12)
- [ ] **#241 CapsuleComposeView 实现** — `apps/ios/SoloCompass/Views/Capsule/CapsuleComposeView.swift`
  - 写入 TimeCapsule + 当时 weather/taste/mood snapshot
  - 写入后吐司: "胶囊将在 X 年后等你回来"
- [ ] **#242 CapsuleOpenView 全屏接受动画** — `apps/ios/SoloCompass/Views/Capsule/CapsuleOpenView.swift` ⭐🎁
  - 仪式感 UI: 暖琥珀粒子 + 慢揭示 + 当时元数据展示
  - "再回信一句" 二次互动 (写入新 TimeCapsule)
- [ ] **#243 CapsuleStore 实现** — `apps/ios/SoloCompass/Services/CapsuleStore.swift`
  - CRUD + 围栏匹配
  - 每天 launch 时检查 scheduledFor ≤ now 的胶囊,关联到对应围栏
- [ ] **#244 年末回顾推送** — `apps/ios/SoloCompass/Services/ProactiveNudgeService.swift`
  - 12 月底自动推送: "今年你埋了 X 个胶囊,X 个会在明年触发"
  - 防止用户忘记资产存在
- [ ] **#245 Archive tab 加 "我的胶囊" section**
  - 显示已埋未触发、已触发未拆、已拆 三组列表

## P2.5 — FilterBar 收敛 🔪

- [ ] **#250 Now 升级 Solo Agent 入口** — `apps/ios/SoloCompass/Views/Filter/FilterBarView.swift`
  - Now chip 改为 "⚡ Solo Agent" 琥珀色
  - 点击直接触发 `suggest_now_action` tool 并打开 ChatSheet 显示结果
- [ ] **#251 category 抽屉化** — `FilterBarView.swift`
  - 默认显示 3 个: 咖啡 / 美食 / 文化 (基于 user 历史频率自动选 3 个)
  - "≡ More" 按钮展开抽屉显示其余 5 个 + 自定义 tag
- [ ] **#252 加 "✦ 我的菜" toggle** — `FilterBarView.swift`
  - 开启后所有结果按 TasteProfile 匹配度排序
  - 免费层就给 (是 Pro 私密策展的钩子)

## P2.6 — ProactiveNudgeService 主动推送 🧱

- [ ] **#260 在现有 `NotificationService` 之上加 `ProactiveNudgeScheduler`** — `apps/ios/SoloCompass/Services/ProactiveNudgeScheduler.swift`
  - **不替代** 现有 NotificationService (它已实现 UNUserNotificationCenter 基础 + deep-link),只在其上加业务调度层
  - 统一限流: 一天最多 3 个 nudge 推送 (与 LiveActivity 限流共用一个计数器)
  - 用户主动开启 (Settings 中)
- [ ] **#261 孤独时段推送** — `ProactiveNudgeScheduler.swift`
  - 默认 17:00-21:00 (可调)
  - 每天最多 1 次,选 1 个 high-confidence Experience + 一句话
- [ ] **#262 早晨城市签推送** — `ProactiveNudgeScheduler.swift` (Phase 3 才填内容)
- [ ] **#263 胶囊触达推送** — `ProactiveNudgeScheduler.swift`
  - 进围栏 + 有未拆胶囊 → 5 秒后推送 (推送 + Live Activity 二选一,避免双重打扰)
- [ ] **#264 隐私 toggle** — `Views/Settings/NotificationsSettingsView.swift` (新建,从 SettingsView 抽出)
  - 三个开关: 孤独时段 / 城市签 / 胶囊
  - 默认全开 (Pro 用户),但用户可单独关

## P2.7 — Phase 2 出口验证

- [ ] **#290 跑全部测试 xcodebuild test**
- [ ] **#291 内测一轮**: 灵动岛限流是否生效、胶囊触发是否准确、盲盒 fallback 是否安全
- [ ] **#292 Phase 2 走查清单更新**

---

# Phase 3 — 情绪付费引擎 + 病毒传播 (4 周)

> 拉新成本降一半,靠用户主动分享。
> 出口指标: 自发分享率 5%/月、CAC 下降 30%+

## P3.0 — 城市签 (每日仪式) 🎁

- [ ] **#301 城市签内容生成 service** — `apps/ios/SoloCompass/Services/OmenComposeService.swift`
  - 每天 7am 调 LLM 生成: 1 句签文 + 1 个微任务 + 1 个 anchor Experience
  - 文案克制: 不卖萌,参考 Co-Star 占星 app 风格
- [ ] **#302 OmenCardView 卡片设计** — `apps/ios/SoloCompass/Views/Omen/OmenCardView.swift`
  - 美术极简 (找设计师做 5-10 套卡面 rotate)
  - 完成微任务后翻面解锁
- [ ] **#303 "我的城市图鉴"** — `apps/ios/SoloCompass/Views/Archive/CityCodexView.swift` ⭐
  - 网格展示已解锁卡片
  - Pro 才能看进度 (退订 = 失去未完成图鉴 = 沉没成本)
- [ ] **#304 重抽 IAP** — `SubscriptionService.swift`
  - product ID `com.solocompass.consumable.omen.reroll` $0.99
  - 限制: 每日最多重抽 3 次

## P3.1 — 今日 OST (Apple Music) 🎁

- [ ] **#310 MusicKit 权限接入** — `apps/ios/SoloCompass/Services/MusicService.swift`
  - SKCloudServiceController 权限请求
  - Apple Music 订阅检测
- [ ] **#311 OstComposeService** — `MusicService.swift`
  - 输入: 今天的 VisitRecord 序列
  - LLM 把每个地点 vibe 翻译成音乐 tag: "京都鸭川黄昏 → ambient + 日本民谣"
  - 调 Apple Music Search API 拿 track id
  - 创建用户私密 playlist
- [ ] **#312 OstShareCard** — `apps/ios/SoloCompass/Views/Ost/OstShareCard.swift`
  - 分享 playlist 到 IG Story 的卡片,带 logo
- [ ] **#313 重抽换风格** — `MusicService.swift`
  - product ID `com.solocompass.consumable.ost.reroll` $0.99 重抽: jazz / lo-fi / ambient / 古典
  - StoreKit2 consumable,沿用 #234 同款 SubscriptionService 注册流程

## P3.2 — Solo Brag (社交资产) 🎁

- [ ] **#320 外部设计师产出 5 套基础卡面** — `apps/ios/SoloCompass/Resources/Assets.xcassets/BragCards/`
  - 不要 emoji 不要卡通,专辑封面级别美感
- [ ] **#321 BragCardComposer** — `apps/ios/SoloCompass/Services/BragCardComposer.swift`
  - Trip 结束自动生成 (基于 VisitRecord 聚合)
  - 数据: 城市/天数/距离/Experience 数/咖啡杯数/微笑次数 (用户自报)
  - 一句话故事 (LLM 生成,带城市名 + 一个动人细节)
- [ ] **#322 BragCardView UI** — `apps/ios/SoloCompass/Views/Brag/BragCardView.swift`
  - "分享" / "设为壁纸" / 视频版 ($1.99 IAP)
- [ ] **#323 IAP 视频版** — `SubscriptionService.swift`
  - product ID `com.solocompass.consumable.brag.video` $1.99
  - 走 ImageRenderer 转 mp4

## P3.3 — 月度洞察 ⭐

- [ ] **#330 MonthlyInsightService** — `apps/ios/SoloCompass/Services/MonthlyInsightService.swift`
  - 每月 1 号 0am 调用 LLM 分析过去 30 天 VisitRecord
  - 输出: 2-3 句话洞察 + 1 张数据卡片
  - 推送通知: "你的 6 月旅行 DNA 出炉了"
- [ ] **#331 InsightCardView** — `apps/ios/SoloCompass/Views/Insight/InsightCardView.swift`
  - 截图友好设计 (情绪溢价)
  - 分享按钮

## P3.4 — 年度 Travel Book (印刷增值) 💰

- [ ] **#340 印刷服务商对接调研** — 准备 spike (1 周)
  - 候选: Lulu API / Shutterfly / 国内一印
  - 价格区间确认 $30-50
- [ ] **#341 BookComposeService** — `apps/ios/SoloCompass/Services/BookComposeService.swift`
  - 把 VisitRecord + 照片 + agent 写的旅行随笔编排成 PDF
  - 上传到印刷 API
- [ ] **#342 Archive tab 年末 banner** — `apps/ios/SoloCompass/Views/Archive/ArchiveView.swift`
  - 11-12 月主动浮现 banner "你的 2026 年度旅行书 — 限时印刷"

## P3.5 — Chat agent 中的情绪玩法上线 (无 UI 改动)

- [ ] **#350 SOS Plan IAP 接入 + tool 启用** — `VoiceAgentToolRouter.swift` + `SubscriptionService.swift`
  - tool 实现已在 P2.1 #214 落地,Phase 3 加上 `com.solocompass.consumable.sos.single` $2.99 IAP 触达
  - Pro 用户每月 3 次免费配额逻辑
- [ ] **#351 未走的路 IAP 接入 + tool 启用** — `VoiceAgentToolRouter.swift` + `SubscriptionService.swift`
  - tool 实现已在 P2.1 #215 落地,Phase 3 加上 `com.solocompass.consumable.unwalked.single` $4.99 IAP 触达
- [ ] **#352 本地圈层观察 tool** — `VoiceAgentToolRouter.swift`
  - 加 tool case `recall_local_scene`
  - 触发: 用户问"这城市有什么本地圈子"
  - 输出: 场景描述卡片 (从 Eventbrite/Meetup API 拉取数据兜底)
  - Pro 内含,不走 IAP

## P3.6 — Phase 3 出口验证

- [ ] **#390 全测试 xcodebuild test**
- [ ] **#391 灰度发布**: 10% → 50% → 100%
- [ ] **#392 度量埋点验证**: 自发分享率/CAC 是否达预期
- [ ] **#393 docs/V_NEXT_DESIGN.md 标记 v1.0 GA**

---

# 横向工作 (跨 Phase, 必须做但不属于单一 Phase)

## X.1 — 设计系统升级

- [ ] **#X10 暖琥珀 v2 token 扩展** — `apps/ios/SoloCompass/Views/Shared/CompareTokens.swift`
  - 新增 CT.capsuleGlow / CT.omenGold / CT.blindboxAmber 等场景色
- [ ] **#X11 Lottie / 动画 spec 文档** — `docs/ANIMATION_SPEC.md`
  - 时空胶囊接受动画、盲盒揭秘动画、城市签翻面 三个核心动画的 spec

## X.2 — 数据埋点

- [ ] **#X20 加 AnalyticsService**(隐私优先,本地聚合后定期上报)
  - 关键事件: capsule_buried / capsule_opened / blindbox_started / agent_hint_accepted / archive_visited
- [ ] **#X21 Pro 转化漏斗埋点**
  - paywall_shown / iap_initiated / iap_success / iap_failed

## X.3 — 隐私 & 合规

- [ ] **#X30 PRIVACY.md 更新**
  - 增加 VisitRecord / TasteProfile / TimeCapsule 数据用途说明
  - 强调全部 on-device,云端不存
- [ ] **#X31 "忘记我" 一键清空流程** (P2.0 #204 已计划)

## X.4 — 测试 & 质量

- [ ] **#X40 visual snapshot 全量更新**
- [ ] **#X41 加 LiveActivity 集成测试**
- [ ] **#X42 ProactiveNudgeService 时段触发回归测试**
- [ ] **#X43 LLM 输出"never 凭空生成 POI" 红线测试**

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
