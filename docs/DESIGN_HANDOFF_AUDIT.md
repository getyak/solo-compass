# SoloCompass 设计交付对照审计（Design Handoff Audit）

> 一次性工程记录：把 Claude Design 的 HTML/CSS 原型（`SoloCompassApp-handoff`，
> 列表视图 + 路线锚定同伴系统）对照到现有 SwiftUI 实现，做像素级差距审计与修复。
> 设计原型为真值（颜色/间距/字体/状态），SwiftUI 复刻其视觉输出，而非其结构。

## 来源

- Claude Design handoff bundle `solocompassapp`（两条主线）：
  - **chat1** — 地图下拉信息列表视图 + POI 详情打磨（内嵌 Solo 对话、旅人共建笔记层）
  - **chat2** — 路线锚定同伴系统（路线详情、招募模块、verified、opt-in、申请、审批、群聊、完成庆祝）
- 原型文件：`SoloCompass.html` → `styles.css`(3490) / `data.js` / `route.jsx` / `sheet.jsx` / `app.jsx` / `companion.jsx`

## Design Token → Swift（`CompareTokens.swift` 的 `CT`）

本次为 `CT` 补全了缺失 token，并修正了 status tone 的取值：

| 设计 token | CT 成员 | 值 |
|---|---|---|
| --surface-white / --surface-sunken | CT.surfaceWhite / CT.surfaceSunken | #FFF / #F3EEE6 |
| --border-subtle / --border-default | CT.borderSubtle / CT.borderDefault | #EDE8DF / #D6CEC0 |
| --sun-gold / -deep / -soft | CT.sunGold / sunGoldDeep / sunGoldSoft | #C9A677 / #A07F4B / #F5E9D2 |
| verified green / dot | CT.verifiedGreen / verifiedGreenDot | #1F7B4D / #2FA46A |
| status tone open/forming/closed/completed | CT.toneOpen/Forming/Closed/Completed | accent / #B57420 / #1F7B4D / fgMuted |

既有保留：bgWarm #FAF8F6 · fgPrimary/Muted/Subtle · accent #5D3000 / accentHover / accentSoft / accentBorder。

## 审计与修复

并行 agent 审计（7 域）+ 对抗式验证，产出 **66 个已验证差距**；按文件级隔离并行修复。

| 域 / 文件 | 关键修复 |
|---|---|
| FilterBarView | NOW pill 改 sun-gold 边/点/计数；分类 disc 34×34 全不透明边；rail padding 6/5 |
| CompassMapView（city pill） | 文字 accent 色 + 暖白 0.78 半透明底 |
| RouteCard | 重构为纵向卡：route-tag 头部 + now-pill + 22×22 stop-strip + 脉冲 recruit-mini + 卡片边/影/按压 |
| VerifiedBadge | badge 32px 圆底 + 绿色；inline 0.12 绿；header 绿渐变 + 发光点 + 常量环；AvatarStack 5/24 |
| AvatarStack | 重叠 -size×0.32；环 1.5pt；+N 气泡 sunken 底 muted 字 |
| StopsList | 序号 "01/02" mono；disc 30×30；连接线 1.5/borderDefault；顶部 hairline；字号/chevron 修正 |
| RecruitingModule | status-pill 品牌色+大写；host 头像 36；空槽虚线边；host-msg 引用卡；CTA accent 实底胶囊 |
| RouteDetailView | meta-row 底边线；AI 洞察 locked 虚线卡；tags pill 区；dock 状态机 CTA（开始/申请/审批/等待/群聊）|

新增 localization key（en + zh-Hans 同步）：`route.card.tag/now`、`route.detail.aiInsight.title/locked/unlock`、`route.detail.tags.title`、`route.detail.start`、`route.detail.cta.requestJoin/review/waiting/groupChat`。

## 已知偏差（有意保留）

- **RouteDetailView topbar**：仍用系统 NavigationStack toolbar（share），未替换为设计的 40×40 悬浮玻璃三件套（back/share/more）。原因：改导航 chrome 会影响返回手势/标题，风险/收益比不佳；视觉差异小。可后续单独迭代。
- **RecruitingModule 空槽尺寸**：保持 22×22（设计 36×36），仅补齐虚线边样式，避免未要求的布局位移。
- **route-tag 时长**：用编译期 `durationLabel`（1h30m/45min）渲染 `estimatedDuration`(Int 分钟)，而非原型字符串。

## 已知预存测试失败（与本次改动无关）

main 基线 iOS CI 当前为红（build scope 错误，已由并行修复解决）。测试套件中以下用例为数据/环境驱动的预存失败，相关源文件本次均未改动：
- `EmptyStateAnnouncementTest`（en strings bundle 加载 / NearbySection 反射）
- `MapViewModelCityRegionSyncTests.testColdStartCameraMatchesSelectedCity`（城市坐标）
- `NowCountCacheTests.testInitialCountIsZero`（缓存初值）

本次另修复了多处测试在渲染含 `NowHintRow` 的视图时缺 `.environment(BestNowClock.shared)` 注入导致的 fatal crash，使测试套件可完整执行。

## 验证

- iOS app target：`xcodegen` + `xcodebuild build` → **BUILD SUCCEEDED**（0 error）。
