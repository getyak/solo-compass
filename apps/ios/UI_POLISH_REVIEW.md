# Solo Compass iOS — UI/UX 打磨审查报告

> 生成于 feat/ui-polish-pass 分支。审查方式：模拟器截图（地图主页 / Solo Score 浮层 / NEARBY 列表 / PeekSummaryCard / 体验详情上下半）+ 三个并行子 agent 源码静态审查。
> idb 在 Xcode 26.4 环境崩溃，聊天/设置/城市选择界面为纯源码审查。

## P0 — 不可用 / 深色模式不可读（必修）

| # | 维度 | 文件:行号 | 问题 | 修复方向 |
|---|------|-----------|------|----------|
| P0-1 | 对比度 | ExperienceDetailView.swift:1228–1232 | Mark Done 按钮 `Color.primary` 背景在深色=白，前景也是 `.white` → 白底白字不可见 | 背景改语义色（accentColor / Color(.label)+前景 systemBackground），保证 ≥4.5:1 |
| P0-2 | 对比度 | ChatCardViews.swift:28,123,183 / ChatCardStack.swift:82,92 | `CT.fgPrimary`(#1F1A14) 硬编码近黑，深色底不可读 | 改用语义色 `.primary`/`.secondary`/`.tertiary` |
| P0-3 | 对比度 | ChatSheet.swift:982–995 | VoiceMicButton 非 listening 态 `Color.black.opacity(0.85)`，深色几乎不可见 | 改 `Color(.tertiarySystemBackground)`，与 ChatInputBar.micButton 一致 |
| P0-4 | 对比度 | ChatCardStack.swift:92 | ReasoningTracePanel step 文字 `CT.fgMuted` 对比度 2.5:1 | 改 `.secondary` |
| P0-5 | 交互 | BottomInfoSheet.swift:377–410 / CompassMapView.swift:704–726 | PeekSummaryCard 无关闭路径，关详情后残留浮层 | onTap 时若 selectedExperience!=nil 调 clearSelection；ExperienceCardView 加显式关闭按钮 |
| P0-6 | 本地化 | en.lproj/Localizable.strings:1245–1248,1218–1219 | sort.smart/distance/now、sheet.count.* 在 en 写死中文 → 英文设备中英混排 | en 改英文（Smart/Distance/Solo/Now/Now %d/Nearby %d），zh-Hans 保留中文 |

## P1 — 明显影响体验（建议同批修）

| # | 维度 | 文件:行号 | 问题 | 修复方向 |
|---|------|-----------|------|----------|
| P1-1 | 显示 | ConfidenceBadge.swift:55 | `L2 · 0 signals` 技术黑话 | 映射为 Low/Medium/High/Verified |
| P1-2 | 显示 | LocationCard.swift:57–59 | 裸露经纬度 37.8623,-122.2814 | 默认隐藏/收进 DisclosureGroup |
| P1-3 | 功能 | ExperienceCardView.swift:708 vs ExperienceDetailView 时间 pill | 剩余时间格式不一致 25m vs 249min | 统一 format string，>60min 转小时 |
| P1-4 | 显示 | ExperienceDetailView.swift:496–541 | Why it matters / AI Insight 内容冗余 | 合并/差异化标题 |
| P1-5 | 显示 | ExperienceDetailView.swift:1487–1510 | Best times 时间轴用 category 色，语义不清 | 固定语义绿色 + 图例 |
| P1-6 | 布局 | ExperienceDetailView.swift:374–397 | 罗盘整行留白过多信息密度低 | 嵌入 LocationCard 或缩窄 |
| P1-7 | 功能 | ExperienceDetailView.swift:1176–1192 / LocationCard.swift:132 | 两处导航按钮行为重复 | 收敛单一入口 |
| P1-8 | 功能 | BottomInfoSheet.swift:742–767 | 所有卡片距离都是 Far 13-15km，与"附近"矛盾 | walkTimeChip 阈值/Far 文案带数字 |
| P1-9 | 布局 | BottomInfoSheet.swift:872–886 | NearbyExperienceRow 标题 lineLimit(1) 截断 | lineLimit(2)+minimumScaleFactor |
| P1-10 | 功能 | ExperienceCardView.swift:327–330 | offset/opacity 重复叠加位移翻倍 | 删除重复的 offset(y:dragOffset)/opacity |
| P1-11 | 动画 | BottomInfoSheet.swift:477–492 | isDragging=false 在 withAnimation 块外 | 移入块内 |
| P1-12 | 功能 | SettingsView.swift:532,735 | `.constant()` alert binding 无法关闭可能死循环 | 改可写 @State binding |
| P1-13 | 动画 | CityPickerSheet.swift:336–343 | 呼吸动画 reduceMotion 守护写错位置 | 守护写进 .animation 修饰符 |
| P1-14 | 布局 | CityPickerSheet.swift:42–134 | List 在 VStack 内 medium detent 可能坍塌 | header 移进 Section 或 List 加 maxHeight |
| P1-15 | 功能 | ChatCardViews.swift:50 | ChatExperienceCard 固定 width 220 大字体截断 | minWidth/maxWidth 或 scaledMetric |
| P1-16 | 功能 | SettingsView.swift:762–766 | entitlementLabel 硬编码英文 Pro/Free | NSLocalizedString |
| P1-17 | 功能 | ChatInputBar.swift:368–384 | mic tap+longpress 手势竞争录音立即停 | 分离 tap 与 PTT 路径 |

## P2 — 打磨（择优）

- ExperienceDetailView: NearbyCard 固定宽不随 DynamicType(1064)；toast .padding(.bottom,96) 魔术数字(220)；HeartBurst 被圆形裁切(1147)；section 间距无层次(67-119)；soloScore 展开动画漏 reduceMotion(854)；时间格式硬编码24hr(1290)
- 地图: nightlife moon.stars 视觉过轻；SortCountToolbar 按钮点击区<44pt(592-626)；卡片切换无 transition 需 .id(704-726)；ai.now.hint==sheet.now.headline 文案重复；nearby.proximity.sparse "Quiet" 语义偏移
- 聊天/设置: MessageBubble toolIndicator 幽灵缩进40pt(150)；voiceStatusLabel 漏 reduceMotion(500)；ChatRouteProposalCard 无 minWidth(102)；空状态判断未排除 tool 行(297)；API key SecureField monospaced 不缩放(73)；城市分隔符硬编码(255)
