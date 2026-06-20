# Solo Compass — UI/UX Deep Audit TODO

> Date: 2026-06-16
> Branch: test/amap-shenzhen-5km-experience
> Audit method: Simulator screenshots (iPhone 17 Pro, Chiang Mai seed data) + source code review

---

## P0 — Critical (Blocks core experience)

- [x] **#1 Empty state for non-seed cities is a dead end** — `BottomInfoSheet.swift`, `MapViewModel.swift` — Launching in Shenzhen/Bangkok 等非清迈城市显示 "No experiences nearby"，只有 "Expand to 25 km" 和 "Clear filters"，两者都无用。应增加城市级空状态引导："This city doesn't have experiences yet — try Chiang Mai" + 一键切城 CTA
- [x] **#2 Distance shows 12,398.6km — absurdly large** — `BottomInfoSheet.swift` NearbyExperienceRow — 模拟器在 SF 但展示清迈数据时距离显示 12,398.6km，跨洲距离无意义。超过 500km 时应隐藏距离或显示 "In Chiang Mai"
- [x] **#3 Bottom sheet lacks loading skeleton** — `BottomInfoSheet.swift` — sheet 展开到数据加载之间有 ~500ms 空白区域，无 shimmer/skeleton/spinner。`SkeletonView.swift` 已存在但未接入
- [x] **#4 Location permission banner is non-actionable** — `CompassMapView` — 黄色 banner "Can't find your location..." 无 "Open Settings" 按钮，用户必须手动去系统设置

---

## P1 — High (Hurts usability)

- [x] **#5 FilterBar category icons lack labels** — `FilterBarView.swift` — 类别 pill 仅显示 emoji 图标无文字，新用户无法区分 food/culture 等图标含义。需增加文字标签或长按提示
- [x] **#6 "Now" filter shows 0 items at midnight with no explanation** — `FilterBarView.swift`, `MapViewModel.swift` — 深夜时 Now 筛选无结果且无提示。应增加时间感知空状态："It's late — most spots are closed"
- [x] **#7 PeekSummaryCard text truncation on long titles** — `PeekSummaryCard.swift` — 标题 "Eat khao soi at the family s..." 被截断，Experience.title 是完整句子非短名。应允许 2-3 行或使用 shortName
- [x] **#8 DayPage/Me screen is sparse and low-value** — `MeSheet.swift` — 显示 "Tuesday" + "Still up?" + "0 SIGNALS" + "Nothing surfaced yet." 全是空状态，"signal" 概念无解释，orb 动画装饰性强但令人困惑
- [x] **#9 Map pin density — clusters are hard to distinguish** — `CompassMapView.swift`, `MarkerIconView.swift` — 中等缩放下 4-5 个 pin 重叠，无聚合注释或防重叠逻辑。应使用 MapKit ClusterAnnotation
- [x] **#10 "Smart" sort has no explanation** — `BottomInfoSheet.swift` SortMode picker — 默认排序 "Smart" 无解释其依据，用户不理解或不信任排名。应增加 "(based on time, distance & score)" 副标题
- [x] **#11 Dark mode contrast issues on cards** — `BottomInfoSheet.swift` smart-pick gradient — `CT.sunGoldSoft.opacity(0.55)` → `CT.surfaceWhite` 渐变在暗色模式下视觉层次反转，金色看起来像错误状态

---

## P2 — Medium (Quality & polish)

- [x] **#12 "Nearby" button purpose is unclear** — `CompassMapView` — 地图右下角 "Nearby" 文字按钮功能与底部 sheet 重叠，应移除或明确其独特用途
- [x] **#13 Solo Score badge lacks context** — `SoloScoreBadge.swift` — "Solo 7.8" 无标尺说明（满分 10？100？），无颜色编码区分好坏。应加 "/10" 后缀 + 渐变色
- [x] **#14 "BEST FOR RIGHT NOW" header redundant when Now filter is off** — `BottomInfoSheet.swift` — "All" 筛选时仍显示 "BEST FOR RIGHT NOW"，暗示时间相关但卡片可能并非当前最佳
- [x] **#15 Chat input bar at bottom of DayPage is confusing** — `MeSheet.swift` — 底部 "Capture this moment" + 麦克风图标，分不清是文字输入还是语音录制，是日记还是聊天
- [x] **#16 Missing haptic feedback on map pin tap** — `CompassMapView.swift` — 点击地图 pin 显示 PeekSummaryCard 但无触觉反馈，FilterBar pill 有 haptics 但主要交互（pin tap）没有
- [x] **#17 "+" FAB button has no label/tooltip** — `CompassMapView.swift` — 右下角大黑 "+" 按钮无上下文说明，创建的是 Experience？Route？Note？
- [x] **#18 Onboarding is only 2 steps — too thin** — `OnboardingView.swift` — 仅 welcome + style-selection，未解释核心概念（Experience/Solo Score/Now/DayPage）
- [x] **#19 CJK text truncation in NowHintRow** — `BottomInfoSheet.swift` — `.lineLimit(1)` 导致中日文提示 "此刻是拍摄落日的黄金时刻" 截断。应允许 `.lineLimit(2)` 或 `minimumScaleFactor`
- [x] **#20 Walk-time estimate uses naive constant** — `PeekSummaryCard.swift` — 步行时间假设 ~80m/min 不考虑地形。应加 "~" 前缀或使用 MapKit 实际步行路线

---

## P3 — Low (Nice to have)

- [x] **#21 No pull-to-refresh on the experience list** — `BottomInfoSheet.swift` — NearbySection 无下拉刷新手势，iOS 用户普遍期望
- [x] **#22 No search functionality** — 无全局搜索，体验 50+ 时只能滚动或用筛选器，效率低
- [x] **#23 No image/photo on experience cards** — `BottomInfoSheet.swift` NearbyExperienceRow — 卡片仅文字无图片预览，`ExperienceImageService` 已存在但未接入列表卡片
- [x] **#24 Settings gear icon on DayPage is low-contrast** — `MeSheet.swift` — DayPage 右上角齿轮图标过小且低对比度
- [x] **#25 Map style options are hidden** — 无可见方式切换卫星/标准/混合地图，顶部笔形图标含义模糊
- [x] **#26 No transition animation between peek/mid/full sheet states** — `BottomInfoSheet.swift` — detent 状态切换缺乏统一的 spring 动画
- [x] **#27 "Good spots for right now" timestamp shows exact time** — `BottomInfoSheet.swift` — 显示 "00:17" 原始时间无意义，应改为 "Updated just now" 或移除
- [x] **#28 Compass/navigation icons in top bar are ambiguous** — 顶栏指南针和定位箭头与 MapKit 内置控件功能重叠
- [x] **#29 "All Cities" dropdown doesn't show current city name** — `CityPickerSheet.swift` — 左上角始终显示 "All Cities" 而非当前城市名 "Chiang Mai"
- [x] **#30 Accessibility: reduce-motion not respected everywhere** — 多处动画（pulsing/heart burst）未统一检查 `reduceMotion`

---

## Architecture & Code Quality

- [x] **#A1 BottomInfoSheet.swift is 1400+ lines** — 违反 800 行上限，应拆分 NearbyExperienceRow、RoutesSection、NowHintRow 到独立文件
- [x] **#A2 Hardcoded proximity thresholds (150m)** — 无城市密度差异配置，东京 150m = 2 个街区 vs 泰国乡村 150m = 隔壁。应按城市/类别配置
- [x] **#A3 FilterBar and Map count can desync** — `resultCount` 作为 prop 传入 FilterBar 非 source of truth，快速平移时可能显示过期计数
- [x] **#A4 Dynamic Type scaling gaps** — BottomInfoSheet 通过 `UIFontMetrics` 缩放 detent 高度，但内部 padding 硬编码（`.padding(.bottom, 28)`），AX5 下文字溢出容器

---

## Summary

| Priority    | Count  | Effort (Est.)   |
| ----------- | ------ | --------------- |
| P0 Critical | 4      | 2-3 days        |
| P1 High     | 7      | 3-5 days        |
| P2 Medium   | 9      | 5-7 days        |
| P3 Low      | 10     | 5-7 days        |
| Arch        | 4      | 3-4 days        |
| **Total**   | **34** | **~18-26 days** |
