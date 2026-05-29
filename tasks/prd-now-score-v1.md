# PRD: NowScore v1 — 把「此刻最佳」从静态布尔变成动态评分

| 字段 | 值 |
|---|---|
| 版本 | v1.0 草稿 |
| 创建日期 | 2026-05-29 |
| 基线 | `main @ 996e421` |
| 范围 | apps/ios/SoloCompass + packages/core |
| 与 58-US 关系 | 并行 ·  不依赖 prd-full-fix-roadmap 任何 US；可同时推进 |
| 预计交付 | 2 周（10 个 US，单端 iOS + 1 个 schema 改动） |

---

## 1. Introduction / Overview

iOS app 当前的 "BestNow" 判定（`Experience.isBestNow()` at `Models/Experience.swift:472`）是基于一个**静态 `bestTimes: [TimeWindow]` 数组**——只看当前时间是否落在某个预设时段内，输出 Bool。

这意味着 marker 上的"此刻"徽章、`MapViewModel.nowCount` 抽屉数字、Filter "Now" 模式都只能给出**二值答案**：现在好 / 现在不好。

但**独行用户决策的真实变量**是**多维度连续值**：
- 营业时间内吗（已有）
- 现在到日落还有多久（缺）
- 今天天气如何（缺）
- 此刻人流是高峰还是空档（缺）
- 用户当前节奏匹配吗（缺，需要 UserPreferences.pace）

把这些组合成一个 `[0, 1]` 的 `nowScore`，UI 就能从"是 / 否"升级到**"现在是这个地方 87% 完美时刻 · 日落还有 23 分钟"**——这是 Google Maps / Apple Maps 永远不会做的差异化。

---

## 2. Goals

### 2.1 可观测目标

- `Experience.nowScore(at: Date) -> Double` 返回 `[0, 1]` 连续值
- `Experience.isBestNow()` 保留为 `nowScore(at:) >= 0.7` 的语义糖（向后兼容）
- 5 个种子城市每个城市至少 1 个 experience 在合适时段达到 `nowScore >= 0.9`
- 引入 `nowScoreReason: String?` 文案接口（"日落 23 分钟后 · 晴天 · 人少"）
- `MapViewModel.markerState(for:)` 排序加入 nowScore 权重
- 性能：单 experience 的 nowScore 计算 p95 < 5ms（含天气/sunset 缓存命中路径）
- 离线 fallback：无网络时 nowScore 仍能返回（只用 bestTimes 维度），不空 / 不抛
- 全部 100+ 既有 BestNow 测试不破

### 2.2 不可观测但同等重要

- **概念演化**：从 `isBestNow()` 的二元思维迁移到 `nowScore` 的连续思维，全 codebase 心智一致
- **可解释性**：每次 nowScore 必须能产出人类可读的 reason 文案（不做黑盒）
- **可扩展性**：未来加 user-pace / crowd / season 维度时只需注册一个新的 `NowSignal`，不改主接口

---

## 3. User Stories

### US-NS-001: 引入 NowScore 类型与 Experience.nowScore(at:) 方法
**Description:** As an iOS engineer, I want a `NowScore` value type and an `Experience.nowScore(at:)` method so downstream views and viewmodels can read a continuous value instead of a Bool.
**Affected:**
- 新建 `apps/ios/SoloCompass/Models/NowScore.swift`
- `apps/ios/SoloCompass/Models/Experience.swift:472-499`（在 `isBestNow()` 旁边加 `nowScore(at:)`）

**Acceptance Criteria:**
- [ ] 新 struct `public struct NowScore: Sendable { public let value: Double /* [0,1] */; public let reason: String?; public let breakdown: [String: Double] }`
- [ ] `Experience.nowScore(at date: Date) -> NowScore` 内部第一版只看 bestTimes 维度，返回 `value = isInWindow ? 1.0 : 0.0`
- [ ] 保留 `isBestNow(at:)` 不变；新增内部 `isBestNow(at:)` impl 改为 `nowScore(at:).value >= 0.7`
- [ ] 新增 `NowScoreTests`：bestTimes 覆盖 → 1.0；不覆盖 → 0.0；空 bestTimes → 0.5（中性，非 0）
- [ ] 全部既有 `BestNow*Tests` 仍 pass
- [ ] Typecheck / lint pass
- [ ] Tests pass

---

### US-NS-002: NowSignal 协议 + bestTimes / hourOfDay 两个内置信号
**Description:** As an iOS engineer, I want a `NowSignal` protocol so future contributors can add new signals (weather / crowd / sunset) without touching `Experience.nowScore` itself.
**Affected:**
- 新建 `apps/ios/SoloCompass/Services/NowScore/NowSignal.swift`
- 新建 `apps/ios/SoloCompass/Services/NowScore/BestTimesSignal.swift`
- 新建 `apps/ios/SoloCompass/Services/NowScore/HourOfDaySignal.swift`

**Acceptance Criteria:**
- [ ] `public protocol NowSignal { static var key: String { get }; func score(for experience: Experience, at date: Date) async -> NowSignalContribution }`
- [ ] `public struct NowSignalContribution { let value: Double /* [0,1] */; let weight: Double; let reason: String? }`
- [ ] `BestTimesSignal` 实现：复刻 US-NS-001 的 bestTimes 逻辑，weight = 0.4
- [ ] `HourOfDaySignal` 实现：基于 `experience.bestStartHour` ± 90min 高斯衰减，weight = 0.2
- [ ] `Experience.nowScore(at:)` 内部循环所有注册的 signal，加权平均得 value，拼接 reason
- [ ] 新增 `NowSignalCompositionTests`：两个 signal 都满分 → 总分 1.0；只一个 → ≈ weight 比例
- [ ] Typecheck / lint pass
- [ ] Tests pass

---

### US-NS-003: 新建 WeatherService（OpenWeather 接入 + 12 小时 SwiftData 缓存）
**Description:** As an iOS engineer, I need a WeatherService that fetches and caches current + 24h weather for any coordinate so NowScore can read it without making a fresh network call per marker.
**Affected:**
- 新建 `apps/ios/SoloCompass/Services/WeatherService.swift`
- 新建 `apps/ios/SoloCompass/Persistence/Models/WeatherCacheRecord.swift`

**Acceptance Criteria:**
- [ ] `@MainActor @Observable public final class WeatherService` with `func current(at: CLLocationCoordinate2D) async throws -> WeatherSnapshot`
- [ ] `WeatherSnapshot { let tempC: Double; let condition: WeatherCondition; let precipChancePct: Int; let windKph: Double; let observedAt: Date }`
- [ ] OpenWeather API key from `Secrets.openWeatherAPIKey`（如缺失，方法 throw `WeatherError.noAPIKey`，调用方 graceful）
- [ ] SwiftData 缓存 `WeatherCacheRecord`，TTL 12 小时，key = `(lat.rounded(2), lon.rounded(2))`（精度避免每米一份）
- [ ] 离线（NetworkMonitor.isOnline == false）→ 强制读缓存，无缓存返回 nil
- [ ] 新增 `WeatherServiceTests`：mock URLSession → 缓存写入 → 第二次调用不访问网络
- [ ] 新增 `WeatherCacheTTLTests`：13 小时后缓存失效
- [ ] Typecheck / lint pass
- [ ] Tests pass

---

### US-NS-004: WeatherSignal（NowScore 信号实现）
**Description:** As a user, I want the NowScore to drop when it's raining hard or unbearably hot so the app doesn't suggest a "perfect now" outdoor experience in a thunderstorm.
**Affected:**
- 新建 `apps/ios/SoloCompass/Services/NowScore/WeatherSignal.swift`

**Acceptance Criteria:**
- [ ] `WeatherSignal` 实现 `NowSignal` 协议；weight = 0.15
- [ ] 评分逻辑（outdoor 类 experience，category ∈ [.nature, .nightlife with rooftop tag]）：
  - 晴 / 多云 → 1.0
  - 小雨（precipChancePct ≥ 30%）→ 0.5
  - 大雨 / 雷暴（precipChancePct ≥ 70% OR windKph ≥ 30）→ 0.0
- [ ] 室内类（coffee / work / wellness / culture）→ 始终 1.0
- [ ] reason 文案：`"晴 · 27°C · 适合"` / `"雷雨预警 · 不建议外出"` (en + zh-Hans 都要)
- [ ] WeatherService 不可用 → contribution.value = 0.5（中性），不影响其他 signal
- [ ] 新增 `WeatherSignalTests`：覆盖雨/晴/雷暴/服务不可用四态
- [ ] 新增 localization keys: `nowscore.weather.sunny` / `.rain` / `.storm` / `.unknown` (en + zh-Hans 双语)
- [ ] StringsParityTests pass
- [ ] Typecheck / lint pass
- [ ] Tests pass

---

### US-NS-005: SunsetSignal（日出/日落实时倒计时）
**Description:** As a solo traveler, I want viewpoints / parks / rooftop bars to score highest in the 90 minutes before sunset so I'm nudged to "出发 · 日落还有 23 分钟" at the right moment.
**Affected:**
- 新建 `apps/ios/SoloCompass/Services/NowScore/SunsetSignal.swift`
- 复用 Foundation `Solar` 计算（或新增 `apps/ios/SoloCompass/Services/SolarEvents.swift`，本地纯函数计算，无需网络）

**Acceptance Criteria:**
- [ ] `SolarEvents.sunset(at: CLLocationCoordinate2D, date: Date) -> Date?` 纯函数，使用 NREL Solar Position Algorithm 简化版
- [ ] `SunsetSignal` 实现：仅对 tag 含 `sunset_friendly` 或 category ∈ [.nature, .nightlife] 的 experience 起作用
- [ ] 评分曲线：日落前 90 → 30 min: 1.0，30 → 0 min: 高斯衰减到 0.7，日落后 30 min（蓝调时刻）: 0.6，其它时段 0.4
- [ ] reason 文案动态生成：`"日落 23 分钟后"` / `"日落 8 分钟后 · 蓝调时刻"` / `"日落已过 47 分钟"`
- [ ] 新增 localization keys: `nowscore.sunset.before_min` / `.blue_hour` / `.after_min`（用 stringsdict 处理单复数）
- [ ] 新增 `SolarEventsTests`：北京冬至 sunset ≈ 16:50；万象夏至 sunset ≈ 18:50（± 5 min）
- [ ] 新增 `SunsetSignalTests`：日落前 60 / 30 / 5 / 0 / +20 / +60 min 六个采样点
- [ ] StringsParityTests pass
- [ ] Typecheck / lint pass
- [ ] Tests pass

---

### US-NS-006: NowScore reason 拼接 + UI 透出（ExperienceCardView 副标题）
**Description:** As a user looking at an experience card, I want the "best now" badge replaced with a one-line reason like "日落 23 分钟后 · 晴 · 适合" so I understand *why* this is recommended right now.
**Affected:**
- `apps/ios/SoloCompass/Views/Experience/ExperienceCardView.swift:267-289` (`BestNowBadge`)

**Acceptance Criteria:**
- [ ] `BestNowBadge` 当 `nowScore.value >= 0.7` 时，副标题渲染 `nowScore.reason ?? "此刻"`
- [ ] reason 最多展示 3 个最高 weight 的 signal 拼接，`·` 分隔；超出截断 + `…`
- [ ] reason 为 nil（所有 signal 都中性 / 离线）→ 退回原有 "此刻" 文案
- [ ] 新增 `BestNowBadgeReasonTests`：三种 reason 长度的 snapshot
- [ ] Typecheck / lint pass
- [ ] Tests pass
- [ ] iPhone 17 Pro Simulator: 跑一个 sunset 时段的 marker，确认 badge 显示 "日落 X 分钟后" 文案，截图存档

---

### US-NS-007: MapViewModel 排序与 nowCount 接入 nowScore
**Description:** As an iOS engineer, I want `MapViewModel.markerState`/`nowCount` to drive off `nowScore.value >= 0.7` instead of the legacy `isBestNow()` so the entire app reflects the new continuous model.
**Affected:**
- `apps/ios/SoloCompass/ViewModels/MapViewModel.swift:298` (`nowCount`)
- `apps/ios/SoloCompass/ViewModels/MapViewModel.swift` (markerState sort)

**Acceptance Criteria:**
- [ ] `nowCount` 计算改为 `visibleExperiences.filter { $0.nowScore(at: .now).value >= 0.7 }.count`（注意：需与 US-P1-003 的 nowCount 缓存策略协调，本 PRD 跟 58-US 都改 nowCount 时哪个先 merge 都要 rebase）
- [ ] markerState 排序：bestNow 优先 → nowScore 降序 → distance 升序
- [ ] 新增 `MapViewModelNowScoreSortTest`：注入 3 个 mock experience（score 0.9 / 0.7 / 0.5），断言排序
- [ ] 既有 `MarkerIconViewTests` 通过
- [ ] Typecheck / lint pass
- [ ] Tests pass

---

### US-NS-008: Filter "Now" 模式渐变高亮（连接 nowScore 强度）
**Description:** As a user, when "Now" filter is on, I want markers visually graded by nowScore intensity (full color / semi / faded) instead of just shown/hidden so I can pick the *best* "now" option.
**Affected:**
- `apps/ios/SoloCompass/Views/Map/CompassMapView.swift` MarkerIconView 调用点
- `apps/ios/SoloCompass/Views/Map/MarkerIconView.swift`（如存在）

**Acceptance Criteria:**
- [ ] Now 模式下，marker 透明度 = `nowScore.value`（0.5 以下封顶 0.5 避免完全消失）
- [ ] nowScore >= 0.9 的 marker 加一圈 `CT.accent` pulse 动画（与 P1-035 协调）
- [ ] 新增 `FilterNowGradientHighlightTest` snapshot
- [ ] 既有 FilterBarViewTests / CompassMapView snapshot 通过
- [ ] Typecheck / lint pass
- [ ] Tests pass
- [ ] iPhone 17 Pro Simulator: 切 Now → 截图，确认渐变高亮可见

---

### US-NS-009: nowScore p95 性能保障（< 5ms）
**Description:** As an iOS engineer, I want NowScore evaluation to stay under 5ms p95 so it doesn't tank scrolling perf on a list of 100 markers.
**Affected:**
- `apps/ios/SoloCompass/Models/Experience.swift` nowScore 实现
- 可能新增 `apps/ios/SoloCompass/Services/NowScore/NowScoreCache.swift`

**Acceptance Criteria:**
- [ ] WeatherService cache 命中路径：纯内存查询，无 SwiftData fetch（用 in-memory dict + LRU 100 entries 兜底）
- [ ] SolarEvents 计算结果按 `(lat.rounded(1), lon.rounded(1), date.yyyymmdd)` 缓存到内存
- [ ] 新增 `NowScorePerformanceTest`：构造 100 experiences → 调用 1000 次 nowScore → p95 < 5ms
- [ ] 测试要 fail 时清楚指出哪个 signal 拖后腿（per-signal timing breakdown 打印在 test failure message）
- [ ] Typecheck / lint pass
- [ ] Tests pass

---

### US-NS-010: 离线 + 错误降级 + Sentry 上报
**Description:** As a user, I want NowScore to keep working when offline (using only the bestTimes signal) and never crash or surface a stack trace.
**Affected:**
- `apps/ios/SoloCompass/Services/NowScore/NowScoreEngine.swift`（如建）
- 集成 `Services/NetworkMonitor.swift` + `Services/SentryService.swift`

**Acceptance Criteria:**
- [ ] WeatherSignal / SunsetSignal 任何 throw → engine catch + 该 signal contribution = `(0.5, 0.0, nil)`（中性 + 0 权重，等于退出加权平均）
- [ ] 离线模式：WeatherSignal contribution.weight = 0，UI 不显示 "晴 / 雨" 文案
- [ ] 任何 unexpected error（非 WeatherError.noAPIKey 等已知态）→ `SentryService.capture(error, context: "NowScoreEngine.\(signalKey)")`
- [ ] 新增 `NowScoreOfflineDegradeTest`：注入 throwing WeatherService → nowScore 仍返回，只少了 weather 维度
- [ ] 新增 `NowScoreSentryReportTest`：注入 unexpected error → 验证 SentryService mock 收到 capture
- [ ] Typecheck / lint pass
- [ ] Tests pass

---

## 4. Functional Requirements

- **FR-1** `Experience.nowScore(at:)` 返回 `NowScore` value type，含 `value: Double in [0, 1]`、`reason: String?`、`breakdown: [String: Double]`
- **FR-2** `isBestNow()` 内部行为变为 `nowScore(at:).value >= 0.7`；签名不变，向后兼容
- **FR-3** `NowSignal` 协议有至少 4 个实现：BestTimes / HourOfDay / Weather / Sunset
- **FR-4** WeatherService 12 小时 SwiftData 缓存，离线只读缓存
- **FR-5** SolarEvents 纯函数计算，无网络依赖
- **FR-6** 任何 signal 失败 → 中性 contribution（0.5, 0.0, nil），不影响其他 signal
- **FR-7** nowScore p95 < 5ms（100 experiences × 1000 calls test）
- **FR-8** ExperienceCardView 在 nowScore >= 0.7 时渲染 reason 副标题；< 0.7 不渲染 badge
- **FR-9** MapViewModel.nowCount + markerState 排序全部接入 nowScore
- **FR-10** 所有 user-visible 新文案走 NSLocalizedString，en + zh-Hans 双语对齐

---

## 5. Non-Goals (Out of Scope)

- ❌ **CrowdSignal**（实时人流）：需要外部 API（Google Popular Times / BestTime.app）且数据质量参差，留 v2
- ❌ **UserPaceSignal**（个人节奏匹配）：需要 UserPreferences 改造 + 用户教育，独立 PRD
- ❌ **SeasonalSignal**（季节性事件，雨季/旱季/花期）：种子数据未结构化，独立 PRD
- ❌ **Pro-only 高级 reason**（"为什么是你的最佳时刻" 个性化）：变现层，独立 PRD
- ❌ **Web / Bot 端**：本 PRD 只 iOS；apps/web、apps/bot 不动
- ❌ **Backend recommendation 模型**：本 PRD 完全 client-side
- ❌ **改 `Experience` SQLite schema**：所有新增字段都是计算属性 + 单独缓存表（WeatherCacheRecord）
- ❌ **与 58-US PRD 任何 US 直接合并**：本 PRD 与 prd-full-fix-roadmap 并行，但**US-NS-007 必须与 US-P1-003 (nowCount cache) 协调 rebase 顺序**

---

## 6. Design Considerations

- **没有新增主要 UI 组件**——只在 `BestNowBadge` 副标题位置渲染 reason 文案
- **配色**：reason 文案使用 `CT.fgMuted`（次要信息），不抢主标题；badge 边框颜色不变
- **动画**：US-NS-008 的 pulse 动画 0.6s 周期，opacity 0.7 → 1.0，仅 nowScore >= 0.9 触发，避免视觉噪音
- **可解释性视觉化**（v1.x 可选）：长按 BestNowBadge → bottom sheet 展开 breakdown（"日落 35% + 天气 18% + 营业 27%"），不在 v1 范围

---

## 7. Technical Considerations

### 7.1 Schema 变更
- 仅新增 `WeatherCacheRecord` 一张 SwiftData @Model，无 migration（首次启动自动建表）

### 7.2 外部依赖
- OpenWeather API：免费档 60 calls/min，缓存 12 小时 + 0.01° 坐标精度 → 单城市 < 30 calls/day，远低于配额
- 若用户拒绝定位 → 用 selectedCity 的中心坐标兜底
- API key 缺失：`Secrets.openWeatherAPIKey == nil` → `WeatherError.noAPIKey` → 中性降级

### 7.3 SolarEvents 数学
- NREL SPA 算法（Solar Position Algorithm）的简化版（< 100 行 Swift 实现）
- 已有 Swift 包 `LunarHelper`/`SwiftAstronomy` 可参考，**但不引依赖**——本 PRD 不增 SPM 依赖

### 7.4 与 58-US 的协调
- US-NS-007 与 prd-full-fix-roadmap.md 的 US-P1-003 (nowCount cache) **冲突点**：都改 nowCount。哪个先 merge 都需要 rebase 另一个。建议 US-P1-003 先做（纯性能优化），US-NS-007 在它之上改语义。
- US-NS-008 与 US-P2-035 (Filter Now 视觉同步) 类似主题——本 PRD 的 US-NS-008 是 superset，建议 merge 时把 US-P2-035 标 obsoleted。
- US-NS-006 触动 `ExperienceCardView.swift`，与 US-P0-004 (SkeletonBadgeView，已 merged in PR #292) 不冲突（位置不同）

### 7.5 测试基线
- 新增 ~12 个 XCTest 函数（每 US 1-2 个）
- iOS test target 总数 489 (PR #292 前) → 547 (58-US 完成后) → ≈ 559 (本 PRD 完成后)

---

## 8. Success Metrics

| 指标 | 当前 | 目标 |
|---|---|---|
| `Experience.nowScore` 存在 | ❌ | ✅ |
| Signal 协议实现数 | 0 | ≥ 4 |
| WeatherService 接入 | ❌ | ✅ + 12h cache |
| SolarEvents 纯函数 | ❌ | ✅ |
| BestNowBadge 含 reason 文案 | ❌ | ✅ |
| nowScore p95 latency | n/a | < 5ms |
| 全部 BestNow* 测试通过率 | 100% | 100%（不破） |
| 新增 NowScore* 测试数 | 0 | ≥ 12 |
| 离线场景 nowScore 不抛 | n/a | ✅ |
| Sentry 月度 `NowScoreEngine.*` 上报 | 0 | > 0（验证机制有效）|
| 新增本地化 key (en + zh-Hans) | 0 | ≥ 10 each |

---

## 9. Open Questions

- **OQ-1**：OpenWeather API key 谁来 provision？放 `Secrets.plist` 还是要求 user-supplied？*待 ops 决策*
- **OQ-2**：SolarEvents 算法用 NREL SPA 简化版还是引 `SwiftAstronomy` 包？引包减少 50 行代码 + 测试压力，但增 dependency。*待 lead 决策*
- **OQ-3**：reason 文案最多 3 个 signal——是按 weight 还是按 contribution.value 取 top-3？*待 PM 决策*
- **OQ-4**：US-NS-007 / 008 是否要等 prd-full-fix-roadmap 的 US-P1-003 / US-P2-035 都 merge 后再开始？*建议是*
- **OQ-5**：v2 是否要做 CrowdSignal？需要付费数据源（BestTime.app $99/mo），值不值得？*待 PM*
- **OQ-6**：BestNowBadge reason 在 zh-Hans 下的"日落 23 分钟后" 当 23 分钟变 0 时怎么处理？"日落刚到"？"日落 0 分钟"？*待 UX*
- **OQ-7**：是否要 expose nowScore 到 share card / Open Graph？"我在此刻 92% 完美时刻打卡了京都东山" 有传播潜力，但增 share 复杂度。*待 PM*

---

## 10. Cross-Reference

| 文档 | 关系 |
|---|---|
| [tasks/prd-full-fix-roadmap.md](./prd-full-fix-roadmap.md) | 并行 PRD；US-NS-007 / 008 与其 US-P1-003 / US-P2-035 协调 |
| [docs/EVAL_REPORT.md](../docs/EVAL_REPORT.md) | EVAL 没覆盖 nowScore 方向（属于产品演化，不是修复债务） |
| Issue #296 (Ralph Linux 接力) | 本 PRD 完成后可加入 ralph 队列；建议独立 batch，不和 58-US 混跑 |
| GitHub issue [拟开]：Product Evolution Roadmap | 本 PRD 是其中"方向 ① 时间动态化"的具体落地 |

---

## 11. Phasing 建议

**Phase 1 (Week 1)**：基础设施
- US-NS-001 NowScore 类型
- US-NS-002 NowSignal 协议 + BestTimes / HourOfDay
- US-NS-003 WeatherService + 缓存
- US-NS-010 离线降级 + Sentry

**Phase 2 (Week 2)**：信号 + UI
- US-NS-004 WeatherSignal
- US-NS-005 SunsetSignal
- US-NS-006 BestNowBadge reason 副标题
- US-NS-007 MapViewModel 排序接入
- US-NS-008 Filter Now 渐变高亮
- US-NS-009 性能保障

---

_本 PRD 是「P0 时间动态化」方向的可执行版。所有 file:line 锚点基于 `main @ 996e421`，对当前 `apps/ios/SoloCompass/Models/Experience.swift:472` 的 `isBestNow()` 实现真实有效。_
