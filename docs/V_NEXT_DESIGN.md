# Solo Compass — Next Major Version Design (v1.0)

> 状态: Draft v0.2 (已过代码级验证) · 2026-07-01
> 目标: 把 Solo Compass 从"地图工具"演化成"独行者沉迷的 AI 旅伴",建立可付费、可留存、可病毒传播的产品形态
> 范围: iOS only (利用 Live Activity + 灵动岛 + Apple Music 的平台壁垒)
> 实施清单: 见仓库根 [`todo.md`](../todo.md) (92 个任务 ID,P1.0–P3.6 + 横向 X.1-X.4)

---

## 0. 设计原则 (Decision Lens)

每一个功能必须能回答这 4 个问题之一:

1. **它每天用几次?** (utility → Pro 留存)
2. **用户为什么会截图发朋友圈?** (情绪 → 病毒拉新)
3. **用户离开了会损失什么?** (沉淀 → 反 churn lock-in)
4. **Google Maps 为什么做不出来?** (差异化 → 护城河)

**淘汰原则**: 答不出任意一个,砍。

---

## 1. 当前 App 的事实底座 (现状审计)

### 1.1 已有强项 (要复用)

| 资产 | 现状 | 利用方式 |
|------|------|---------|
| **Chat Agent + 10 tools** | `VoiceAgentOrchestrator.swift` + `VoiceAgentToolRouter.swift` (explore_nearby/build_route/filter_by_category/show_details/save_to_favorites/dismiss_recommendation/search_places/navigate_to/filter_visible/expand_radius) | 升级为 v1.0 的"Solo Agent",所有新玩法走 tool 扩展 (新增 ≥8 个 tool case) |
| **灵动岛 4 场景** | `apps/ios/SoloCompassWidgets/` (独立 widget extension target) — Kind 定义在 `apps/ios/SoloCompass/Shared/SoloCompassActivityAttributes.swift` 双 target 共享 | 新场景接入: soloAgentHint, timeCapsule, dailyOmen |
| **24 个 @Model** | SwiftData 离线-first (实际 grep `@Model` 共 24 个,explorer 报告口径略有出入) | 加 4 个新 model (VisitRecord/TasteProfile/TimeCapsule/AgentMemorySnapshot) |
| **暖琥珀 CT 设计系统** | 40+ tokens + SF Rounded | 全 App 视觉一致性,新组件零成本沿用 |
| **TravelerNote/PlaceCorrection** | 已过 schema parity | 个人档案的天然地基,无需从零 |
| **订阅状态机** | free/proTrial/pro/proExpired + StoreKit2 | 直接挂载新付费层,无需改造 |
| **ChatSession 持久化** | ChatSessionRecord + ChatMessageRecord | 升级为"agent 跨会话记忆"的载体 |

### 1.2 关键缺口 (v1.0 必须补)

| 缺口 | 影响 | v1.0 必补 |
|------|------|----------|
| **没有 VisitLog/TravelLog** | 个人档案/时空胶囊/口味演化都无法做 | 加 `VisitRecord @Model` + 新建 `VisitTrackingService` (借鉴现有 PresenceService 隐私契约,但 PresenceService 本身是 Companion Mode geohash 广播,职责不同不复用) |
| **没有时段触发的主动推送调度层** | 孤独时段向导/胶囊/每日签都无法做 | 基于现有 `NotificationService` (已实现 UNUserNotificationCenter 基础 + deep-link) 之上加 `ProactiveNudgeScheduler` |
| **没有口味嵌入** | 反算法策展只能用 tag,精度不够 | 加 `TasteProfile @Model` (本地嵌入向量) |
| **没有跨会话记忆** | Solo Agent 每次都重新认识用户,无沉淀感 | ChatOrchestrator 加 `AgentMemorySnapshot @Model` 注入 |
| **Onboarding 没城市/没 vibe** | 冷启动推荐质量差 | 在 OnboardingView 加 city + 3-pic vibe pick 两步 |

### 1.3 冗余 / 该砍 / 该合并 (v1.0 减法清单)

> 经验法则: 一个功能如果"看起来在但没人点",就是 UI 噪音。

#### 🔪 SettingsView 14 section → 6 section

**砍/合并**:
- ❌ **AI Provider** (DeepSeek API key override) — debug-only,普通用户从来不点,移到隐藏的 `Settings → About → 7 次点击解锁` 开发者菜单
- ❌ **Admin unlock** — 全球 2 个邮箱用,占一个 section 没必要,合并到 About
- ❌ **Stats** (已探索/最爱计数) — 不该在 Settings,应该是档案 tab 的首屏内容,**搬走**
- ❌ **Companion opt-in** — 实验性 toggle,合并到 Notifications 之下作为子项
- ❌ **Export Markdown** — 低频,合并到 Data 之下
- ❌ **Filter Bar Customization** — 自定义 tag 应该长按 FilterBar 原地编辑,不应该在 Settings 里二次入口

**保留并优化** (合并后 6 section):
1. 旅行风格 + 偏好类目 (合并: Travel Style + Preferred + Disliked → 一个 "你的喜好" 编辑器)
2. 距离 + 语言 (合并: 简短地理设置)
3. 外观 (主题)
4. 通知 (含 Companion opt-in)
5. 订阅
6. 数据 (含 Export + 清空 + 恢复购买 + About 隐藏开发菜单)

**预期效果**: SettingsView 滚动减少 60%+,用户能"看完"。

#### 🔪 FilterBar Now/All/Favorites + 8 category → 收敛

**问题**: 当前 11+ 个 chip 滚动,信息过载。
**改造**:
- Now 升级为 v1.0 的 **"Solo Agent 入口"** (常驻第一位,点击直接出现"现在该去哪"的建议)
- All / Saved 合并到一个 "我的" segmented control (代码中 "Saved" 是当前命名,不是 "Favorites")
- 8 个 category 改为 **"≡ More"** 抽屉式展开 (默认折叠 3 个高频:咖啡/美食/文化,其余进抽屉)
- 自定义 tag 长按 chip 原地编辑

**预期效果**: 主界面 chip 从 11+ 降到 5,认知负担降一半。

#### 🔪 MeSheet 入口分散 → 双 tab 结构

**问题**: Profile + EntitlementBanner + Empty + 社交 + Admin + Settings 6 个 section 都堆一起,主次不分。
**改造**:
- 顶部 segmented: `[档案 | 我]`
- **档案 tab**: 新增的 Travel Archive (见 §3)——这是用户最常回看的内容,放第一
- **我 tab**: Profile + 订阅 + 社交 + 设置入口

**预期效果**: 用户每次进 MeSheet 第一眼看到的是自己的旅行沉淀,不是冷冰冰的设置入口。

#### 🔪 BottomInfoSheet vs ChatSheet vs ExperienceDetailView 三层 sheet 冗余

**问题**: 点一个 POI → BottomInfo (peek) → 上滑 ExperienceDetail (全屏) → Ask Solo → ChatSheet (半屏) → 三层堆叠,用户迷路。
**改造**:
- BottomInfoSheet 的 peek 内容嵌入到 ExperienceDetail 的 hero,**砍 BottomInfoSheet 中间层**
- 点 POI → 直接半屏 ExperienceDetail (mid detent),上滑全屏
- Ask Solo 不再开新 sheet,直接在 ExperienceDetail 底部嵌入 mini ChatBar (scoped chat)
- 全局 ChatSheet 只在地图主屏的 dock FAB 触发

**预期效果**: sheet 层级 3→2,Ask Solo 体验从"跳转"变"原地展开",符合 iOS sheet 哲学。

---

## 2. v1.0 产品形态 (核心叙事)

### 2.1 一句话定位

> **"一个常驻地图的 AI 旅伴,陪你度过 1-2 周的城市深漫,记得你去过哪、懂你喜欢什么、在你孤独时陪你坐一会。"**

### 2.2 三层功能架构

```
┌─────────────────────────────────────────────────────────────┐
│                    L1: Solo Agent (永远在线)                  │
│   ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│   │ 现在该去哪    │  │  孤独时段陪伴 │  │  盲盒 Trip       │   │
│   │ (每天 3-5次)  │  │  (情感峰值)   │  │  (冲动 $1.99)    │   │
│   └──────────────┘  └──────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ 喂入
                              │
┌─────────────────────────────────────────────────────────────┐
│                  L2: Taste & Archive (沉淀层)                │
│   ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│   │ 口味画像      │  │  旅行档案     │  │  时空胶囊        │   │
│   │ (反算法策展)  │  │  (被动沉淀)   │  │  (1 年后触达)    │   │
│   └──────────────┘  └──────────────┘  └─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              ▲
                              │ 演出
                              │
┌─────────────────────────────────────────────────────────────┐
│              L3: Ambient (iOS 平台壁垒,无感存在)              │
│   ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐   │
│   │ 灵动岛 hint   │  │ Live Activity│  │  Apple Music     │   │
│   │ (锁屏决策)    │  │ (跟路而行)    │  │  (今日 OST)      │   │
│   └──────────────┘  └──────────────┘  └─────────────────┘   │
```

### 2.3 付费层与功能映射

| 层级 | 价格 | 功能 |
|------|------|------|
| **Free** | $0 | 地图、Experience 浏览、收藏、基础档案沉淀(被动)、Solo Agent 每天 1 次 |
| **Pro** | $9.99/月 | Solo Agent 无限 + 跨会话记忆、口味画像 + 私密策展、孤独时段陪伴、时空胶囊、活档案(月度洞察)、灵动岛深度集成、每日 OST、城市签 |
| **增值** | $1.99-$4.99/次 | 盲盒 Trip $1.99、SOS Plan $2.99/次、未走的路 $4.99/trip、年度 Travel Book 印刷 $30-50 |

---

## 3. 大方向 (5 个 Pillar)

### Pillar 1: Solo Agent v2 — Chat 升级为"决策者"

**当前 Chat 是工具调用器,v1.0 升级为有记忆、有人格、有时段意识的旅伴**。

#### 1.1 跨会话记忆 (Memory Snapshot)
- 新增 `AgentMemorySnapshot @Model`: 用户去过的城市、最爱 3 个地方、当前 trip 上下文、最近 7 天聊天摘要
- 每次新会话 ChatOrchestrator 自动注入 system prompt
- **沉迷点**: 用户感觉"它真的认识我",每次开口都不用从头讲

#### 1.2 时段意识 (Time-Aware Agent)
- Solo Agent 知道现在是早/午/傍晚/夜,知道你的孤独时段
- 主动语气调整: 早上"今天想做什么"、傍晚"要不要去坐一会"
- **入口**: FilterBar 第一位的 Now 升级为 Solo Agent 按钮

#### 1.3 新 Tool 扩展 (基于现有 VoiceAgentToolRouter)
- `suggest_now_action(context)` — "现在该去哪"决策
- `open_blindbox(duration)` — 启动盲盒 Trip
- `bury_capsule(text|voice)` — 埋下时空胶囊
- `recall_pattern(period)` — 调出口味演化洞察
- `compose_ost(today_visits)` — 生成今日 OST

#### 1.4 Chat 中可以"演"的玩法 (从情绪付费方向收回 Chat)
**这些不需要独立 UI,Chat agent 就能交付**:
- **未走的路 (回溯讨论)** — Trip 结束后用户问"我那天还能怎么走" → agent 用反事实生成,聊天中输出文字+地图卡片,$4.99 单次解锁
- **本地圈层观察** — "曼谷有什么值得看的非游客圈子" → agent 输出场景描述卡片(Pro 内含)
- **SOS Plan** — "下雨了我不知道去哪" → agent 直接生成 4 小时替代路线 (Pro 用户每月 3 次免费,免费用户 $2.99/次)

**设计原则**: 凡是"对话能完成的"绝不做独立 UI,Chat 越用越值钱。

---

### Pillar 2: Taste Profile + 反算法策展

**当前没有 vibe embedding,推荐只能用 category tag,精度不够**。

#### 2.1 Onboarding 加 vibe 采集步
- 第 4 步: 3 张照片或 3 个去过的店 (从 Apple 相册联动) → 调 LLM 生成 vibe 描述 + 嵌入向量
- 第 5 步: 语音/文字一句话补充"你在城市里最想要什么样的下午"
- **新 @Model**: `TasteProfile { embedding: Data, descriptors: [String], confidence: Double, updatedAt: Date }`

#### 2.2 私密策展 (Pro)
- 每周一,agent 从城市的长尾池子里挑 3 个匹配你 vibe 但**只对你可见**的 Experience
- 推送通知: "本周给你挑了 3 个新地方"
- 在档案 tab 有"我的私藏"section,Pro 解锁后陆续积累

#### 2.3 口味演化曲线 (Pro 档案玩法)
- 每月 1 号,agent 分析过去 30 天访问记录,输出: "你这个月更偏书店少咖啡了"、"你在东京选静、在曼谷选闹"
- 卡片形式,可截图分享 (情绪溢价)

#### 2.4 反算法过滤器 (免费层就给)
- FilterBar 加一个 "✦ 我的菜" toggle,开启后所有结果按 taste 匹配度排序而非默认 Solo Score
- **这是免费用户的钩子**: 用了几次后,Pro 的"私密策展"才有动力升级

**沉迷设计**: TasteProfile 用得越久越懂你,迁移成本 = 重新喂数据 + 等几周才生效,**这就是天然 lock-in**。

---

### Pillar 3: Travel Archive + 时空胶囊 (核心 Lock-in)

**这是用户离开 App 损失最大的一层**。

#### 3.1 被动旅行档案 (免费层就给)
- 新增 `VisitRecord @Model`: experienceId / visitedAt / dwellSeconds / weather / coordSnap
- 触发条件: 用户在某 Experience 200m 内停留 >5 分钟 (复用现有 CLCircularRegion)
- 自动归类: 按 trip (基于城市+连续时段聚类)、按月、按 category
- **入口**: MeSheet 顶部 segmented 的 "档案" tab,首屏就是

#### 3.2 活档案 (Pro)
- **月度洞察**: 见 2.3 口味演化曲线
- **重访 agent**: 1 年后系统主动 push "去年这周你在京都那家咖啡店待了 2 小时,今年同周你在曼谷,要不要找一家相似 vibe 的" → 灵动岛触达
- **私藏区**: 见 2.2

#### 3.3 ⭐ 时空胶囊 (Pro 的灵魂功能)
- 用户在任一 Experience 长按 → "留下时间胶囊"
- 输入: 一段文字 / 一段语音 / 一张照片
- 元数据: 当时位置、天气、口味画像快照、心情 emoji
- 触发: 1 年后(可自定义 3 / 6 / 12 个月)用户进入该 Experience ±500m → **灵动岛主动跳出**
- UI: 收到胶囊的瞬间是仪式感峰值,设计极美的全屏接受动画
- **新 @Model**: `TimeCapsule { id, experienceId, createdAt, scheduledFor, content (text/voice/photo), context (weather/taste/mood), opened: Bool }`

**沉迷设计**: 这是**真正的 lock-in 之王**。用户每攒一年的胶囊,退订成本就高一倍。**不退订的最强理由不是功能,是怕错过自己未来的惊喜**。

#### 3.4 年度 Travel Book (增值层 $30-50/本)
- 年末用户可以一键生成,把档案 + 照片 + agent 写的旅行随笔印成实体书
- Polarsteps 验证过的现金牛模型
- **入口**: 档案 tab 年末季节性 banner

---

### Pillar 4: 盲盒 Trip + 仪式感玩法 (情绪付费引擎)

**这是病毒传播 + 冲动付费的双引擎**。

#### 4.1 ⭐ 盲盒 Trip ($1.99/次, Pro 每月 5 次)
- 用户按下"今天给我 3 小时盲盒"按钮
- Agent 全程不告诉你去哪,只给"7 分钟后往北走"这种指令
- 每一步到达后才解锁下一步,灵动岛全程在演
- 结束后生成"今天你被带去了哪"复盘卡片,可分享
- **可复用现有 LiveActivity 的 route 场景**,只是终点延迟揭示
- **入口**: FilterBar 旁边一个"🎁 盲盒"按钮 (橙色琥珀渐变,吸睛但克制)

#### 4.2 城市签 (Pro 每日 1 张, $0.99 重抽)
- 每天 7am 推送: "今天属于安静的水,去一个能听见水声的地方坐 10 分钟"
- 完成微任务解锁一张极美卡片,慢慢收集成"我的曼谷图鉴"
- **设计要求**: 文案克制不卖萌 (Co-Star 占星 app 那种气质),美术极简
- 收集进度只对 Pro 可见,退订 = 失去未完成图鉴

#### 4.3 今日 OST (Pro)
- 一天结束后,agent 根据今天去过的地方生成 Apple Music playlist
- 每个 Experience 对应 1-2 首歌
- **直接走 Apple Music API + MusicKit** (iOS 原生,绕开 Spotify 政策风险)
- 1-2 周后是"一整张你的城市专辑",分享到 IG Story 天然带 logo

#### 4.4 Solo Brag (Pro 免费, $1.99 视频版)
- Trip 结束自动生成"独行成就卡": 走了 47km、去过 23 个非游客点、喝了 14 杯咖啡
- 设计成专辑封面级别美感,可设手机壁纸
- 视频版可发 IG Reels

**这 4 个玩法的共同点**: 都是 **"看到就想截图"** 的产品形态,病毒传播免费帮你做拉新。

---

### Pillar 5: 灵动岛 / Live Activity 深度集成 (iOS 平台壁垒)

**当前已有 4 场景,v1.0 扩展为 7 场景,把 Solo Agent 推到锁屏顶部**。

#### 5.1 新增 ActivityConfiguration.Kind 场景

| Kind case | 触发 | 演什么 |
|-----------|------|--------|
| `soloAgentHint` (新) | Agent 主动建议 | 一个琥珀色点 + "5:20 出门走鸭川,15 分钟刚好赶上晚霞" |
| `timeCapsule` (新) | 进入有胶囊的围栏 | "去年的今天你在这里写过一句话,要拆开吗?" |
| `dailyOmen` (新) | 每天 7am | 城市签出现,1 句话 + 1 个点 |
| `route` (已有) | 路线进行中 | 复用 |
| `countdown` (已有) | 倒计时 | 复用 |
| `recording` (已有) | 录音 | 复用 |
| `compile` (已有) | AI 合成 | 复用 |

**实施位置**:
- enum 加 case → `apps/ios/SoloCompass/Shared/SoloCompassActivityAttributes.swift` (双 target 共享文件)
- widget 渲染分支 → `apps/ios/SoloCompassWidgets/SoloCompassLiveActivity.swift` + `LockScreenLiveActivityView.swift`
- 主 app 触发 → `apps/ios/SoloCompass/Services/LiveActivityService.swift`

#### 5.2 锁屏决策卡片
- Solo Agent 的所有建议都可以"不解锁手机直接决策"
- expanded region 显示: 建议、采纳/换一个、5 分钟后再提醒 三选项
- 用户的肌肉记忆变成"瞄一眼锁屏就知道下一步"

**这是 Google Maps / Mindtrip / Layla 物理上做不出来的形态优势**。

---

## 4. 信息架构 (IA) 重构

### 4.1 v1.0 主界面

```
┌─────────────────────────────────────┐
│           [Map 主屏]                  │
│                                      │
│   ╔═══════════════════════════╗     │
│   ║  Solo Agent ⚡ Now         ║     │
│   ║  [我的菜] [咖啡] [≡ More]  ║ ← FilterBar 收敛
│   ╚═══════════════════════════╝     │
│                                      │
│           [大地图]                    │
│                                      │
│      [盲盒 🎁]    [Agent FAB 💬]     │
└─────────────────────────────────────┘
       Map        Archive      Me
        ●           ○           ○
```

### 4.2 三个底部入口

| Tab | 内容 | 何时用 |
|-----|------|--------|
| **Map** (主) | 地图 + Solo Agent + FilterBar | 在路上,90% 时间 |
| **Archive** (新) | 旅行档案 + 时空胶囊 + 月度洞察 + 城市图鉴 | 回看自己,沉淀感 |
| **Me** | Profile + 订阅 + 社交 + 设置 | 工具性,低频 |

**注意**: 这是 v1.0 关键决策——**第一次给 App 加 tab bar**。之前的"无 tab、纯地图"已经不够装下沉淀层,但 tab 必须克制只 3 个。

---

## 5. 反风险设计

### 5.1 关键风险与对策

| 风险 | 对策 |
|------|------|
| LLM 编造店铺 (Mindtrip 翻车) | Solo Agent 所有建议必须 RAG 自 Experience 池,never 凭空生成 POI |
| 用户回家不续费 | 不推年付 (refuted 证据);月付 + 跨会话记忆让用户回家也想用 |
| 时空胶囊 1 年后用户忘了 → 触达感觉怪 | 年末主动做"今年你埋了 X 个胶囊"回顾,持续提醒资产存在 |
| 盲盒第一次踩雷直接流失 | 第一次盲盒走"超安全 + 高分匹配",且"重摇"按钮免费 |
| 私密策展命中率低 → 觉得被骗 | agent 必须输出"为什么这家匹配你",可解释性必须有 |
| 灵动岛通知过载 → 被关 | Solo Agent 通知一天最多 3 次,arch 设计层强制限流 |
| TasteProfile 冷启动质量差 | 头 7 天只走 high-confidence 推荐,等数据累积再放开 |
| Chat 跨会话记忆隐私焦虑 | 记忆全部 on-device SwiftData,云端不存,Settings 提供"忘记我"按钮 |

### 5.2 不做的 (从研究证据反推)

- ❌ 撮合社交 (Couchsurfing 死法)
- ❌ 自动订机酒 (信任 gap, Booking 死亡战场)
- ❌ 行程预规划 day plan (红海)
- ❌ 安全溢价 add-on (refuted: 独行女性不为这付费)
- ❌ 年付 push (refuted: 月付才是 solo travel 形态)
- ❌ Hard paywall (refuted: freemium 三层结构)

---

## 6. 三阶段交付路线图

### **Phase 1 (4 周): 沉淀地基**
**目标**: 把 Travel Archive + TasteProfile 跑通,给"回看自己"一个家

- 新增 VisitRecord @Model + ProactivePresenceService (区域驻留 5 分钟触发记录)
- 新增 TasteProfile @Model + 本地嵌入向量
- Onboarding 加 city + 3-pic vibe 两步
- MeSheet 顶部 segmented `[档案 | 我]`,Archive tab 接入
- SettingsView 14 → 6 section 砍冗余
- 暖琥珀 v2 视觉沿用,Archive tab 全新美术

**指标**: 30 天后,30% 月活用户至少进过 Archive tab 3 次以上

**P1 走查 (2026-07-01)** — 主线全部满分通过,SettingsView 重排留单独 PR
- ✅ **P1.0 schema v1.9**: VisitRecord / TasteProfile / TimeCapsule / AgentMemorySnapshot 4 个 @Model + 迁移注册 (18/18 测试绿)
- ✅ **P1.1 #110 VisitTrackingService**: chain LocationService.onRegionEnter/Exit, 5min 计时 (注入可调) → 写 VisitRecord (7/7 测试绿)
- ✅ **P1.1 #111 Archive tab UI**: ArchiveView + ArchiveViewModel, 按城市分组时间线 + 暖琥珀 token + 中英本地化
- ✅ **P1.1 #112 地图已访问 halo**: MapViewModel.visitedExperienceIds + markerState 加 .footprinted 分支, 复用既有金色光晕样式; CompassMapView @Query 接线 (6/6 vm 测试 + 2/2 marker 性能回归绿)
- ✅ **P1.1 #113 ArchiveViewModel 单测**: 8/8 测试绿 (按城分组 / 重访去重 / activeCityCode override / dayCount 本地时区 / 孤儿丢弃)
- ✅ **P1.2 #120 OnboardingVibeStep**: PhotosPicker 3 张 + freeformVibe + commit 写 TasteProfile, 已接入 OnboardingView step 4
- ✅ **P1.2 #121 OnboardingCityStep**: segmented 4 城 + afternoon textarea, 已接入 OnboardingView step 5 (语音留 Phase 2)
- ✅ **P1.2 #122 generateTasteProfile**: AIService 加 deterministic on-device fallback (SplitMix64 PRNG → 64 维 Float embedding); vision LLM 留 future flag (14/14 测试绿, 1 个 trim-whitespace 生产 bug 被测试抓出并修复)
- ✅ **P1.2 #123 TasteUpdateService**: @MainActor singleton, 每 5 visit 触发, confidence 0.30→0.95 单例 upsert (10/10 测试绿)
- ✅ **P1.3 #132 MeSheet segmented [档案 | 我]**: Picker(.segmented) topTab + if/else 切换体, .archive 嵌 ArchiveView
- ✅ **P1.4 #190 视觉接线 + 全量回归**: SoloCompassApp 启动调 VisitTrackingService.attach + setModelContainer; CompassMapView @Query VisitRecord + onAppear/onChange → vm.attachVisitedExperienceIds; OnboardingView 5→7 step
- ✅ **P1.4 #192 Archive snapshot**: ArchiveSnapshotTests 用 ImageRenderer 写 PNG 到 /tmp (2/2 测试绿)
- 🟡 **P1.3 #130 SettingsView 14 → 6**: 推迟到单独 PR (Recon-B 标 Stats/Data/Companion 4 个 high-risk section, 跨服务深耦合)

**测试累计**: 65 项新单测全部通过 (`xcodebuild test` 在 iPhone 17 Pro / iOS latest)
- 18 V1_9SchemaRecords / 7 VisitTracking / 8 ArchiveViewModel / 6 VisitedMarkerState / 14 GenerateTasteProfile / 10 TasteUpdate / 2 ArchiveSnapshot

### **Phase 2 (6 周): Solo Agent v2 + 灵动岛主战场**
**目标**: 让用户"每天 3-5 次想到打开 App"

- ChatOrchestrator 接入 AgentMemorySnapshot 跨会话记忆
- 新增 5 个 tool (suggest_now_action, open_blindbox, bury_capsule, recall_pattern, compose_ost)
- 灵动岛加 solo_agent_hint / time_capsule / daily_omen 3 个 Kind
- ProactiveNudgeService: 本地通知调度 (孤独时段 / 早晨签 / 胶囊触达)
- FilterBar 收敛: Now 升级 Solo Agent 入口、category 抽屉化
- ⭐ **时空胶囊 MVP**: 长按 Experience → 留胶囊 → 围栏触达
- ⭐ **盲盒 Trip MVP**: $1.99 单次,复用现有 LiveActivity route

**指标**: Pro 转化率从当前基线提升 2x,DAU/MAU 从 X% 提升到 Y%

### **Phase 3 (4 周): 情绪付费引擎 + 病毒传播**
**目标**: 拉新成本降一半,靠用户主动分享

- 城市签每日推送 + 收集图鉴
- 今日 OST + Apple Music / MusicKit 集成
- Solo Brag 自动生成卡片 (找外部设计师做基础卡面)
- 月度洞察卡片 (口味演化)
- 反算法过滤器 "✦ 我的菜" toggle 上线
- SOS Plan / 未走的路 / 圈层观察 全部走 Chat agent tool 形态交付
- 年度 Travel Book 实体印刷 接入 (合作印刷服务商)

**指标**: 用户自发分享率达到 5%/月,paid acquisition 成本下降 30%+

---

## 7. 度量与验证

### 7.1 北极星指标
**Pro 月留存 (M1 → M3) 从当前基线 → 50%+** (行业 36% 中位,目标显著高于)

### 7.2 健康度二级指标
- Archive tab 周访问率 (反 churn)
- Solo Agent 每周触发次数 / 用户
- 时空胶囊埋下数 / 用户 (lock-in 强度)
- 盲盒 Trip 单次付费转化率 (情绪定价验证)
- 自发分享率 (病毒传播验证)

### 7.3 红线指标 (越低越好)
- 灵动岛通知关闭率
- SettingsView 进入次数 (越低说明默认体验越好)
- Chat agent "我不知道你在说什么"回复率

---

## 8. 工程总成本估算

| Phase | 周数 | 主要工作 | 风险 |
|-------|------|---------|------|
| Phase 1 | 4 | SwiftData 加 model + Archive UI + Settings 减法 | 低 |
| Phase 2 | 6 | Chat memory + 灵动岛 Kind + 时空胶囊 + 盲盒 | 中 (LiveActivity 调试苦) |
| Phase 3 | 4 | OST / Solo Brag / 城市签 / 印刷接入 | 中 (外部服务依赖) |
| **合计** | **14 周** | | |

**关键依赖**:
- MusicKit (iOS 原生,低风险)
- Apple Music API token 配置
- 印刷服务商对接 (Polarsteps 同款供应商)
- 外部设计师做 Solo Brag 卡面 (审美投入)

---

## 9. 决策检查表 (开工前)

每个功能开工前问一遍:

- [ ] 它每天用几次?(目标: Pro 功能日均 ≥ 2 次)
- [ ] 用户为什么会截图?(写出一句具体的分享文案)
- [ ] 用户离开损失什么?(回答: 失去什么资产)
- [ ] Google Maps 为什么做不出来?(回答: 商业模式冲突 / 形态约束 / 数据缺失)
- [ ] 它和现有的哪个 @Model / Service 复用?(目标: 新代码不超过 30%)

答不上来,不做。

---

## 附录 A: 与既有 docs 的关系

- `PRODUCT_BRIEF.md` — 不冲突,v1.0 是 brief 描述的"map-first companion"的成熟版
- `FRIENDS_DESIGN.md` — Phase 1-3 都不动好友系统,等情绪付费引擎稳了再激活社交
- `RETENTION.md` — v1.0 的核心论点(时空胶囊 + Travel Archive)是这份的实施版
- `PRD/` — v1.0 之后会拆出对应 PRD,本文档是上游设计
- `PHASES.md` — **历史路线图** (Field Week → Notion Prototype → Web Pre-MVP → iOS Native),记录 0→1 阶段;**本文档 v1.0 Phase 1-3 是 iOS Native 已上线后的下一个大版本**,不冲突
- `todo.md` (仓库根) — 本文档的实施清单,80 个任务 ID 一一映射到 Pillar/Phase

## 附录 B: 已被砍掉的方向 (备忘录)

- ~~周通行证 $4.99/week~~ (refuted)
- ~~年付 Pro 推送~~ (refuted)
- ~~Hard paywall~~ (refuted)
- ~~独食/夜归安全模式加价~~ (refuted)
- ~~Bumble Travel 式撮合~~ (Couchsurfing 死法)
- ~~AI 自动订机酒~~ (信任 gap)
- ~~Day plan generator~~ (红海)

## 附录 C: 事实底座边界 (验证过程发现, v0.1 已修正)

> 本文档 v0.1 撰写时基于 explorer agent 报告,后做了一轮代码级验证。下列边界曾被一稿弄错,已在 v0.1 修正,记录在此防止下次出错:

| 误判 | 真实情况 |
|------|---------|
| Widget 在 `apps/ios/SoloCompass/Widgets/` | 实际在 `apps/ios/SoloCompassWidgets/` 独立 target |
| `SoloCompassActivityAttributes.Kind` 在 widget 文件内 | 在 `apps/ios/SoloCompass/Shared/SoloCompassActivityAttributes.swift` 双 target 共享 |
| 要新建 `ProactivePresenceService` | `PresenceService` 已存在 (Companion Mode geohash),不复用;新建 `VisitTrackingService` 但借鉴隐私契约 |
| 要新建 `ProactiveNudgeService` | `NotificationService` 已实现 UNUserNotificationCenter 基础;v1.0 新建 `ProactiveNudgeScheduler` 作为业务调度层 |
| @Model 共 23 个 | 实际 grep 出 24 个 (差异在 TravelerNoteRecord 一处双匹配) |
| FilterBar 收藏入口名 "Favorites" | 代码命名为 "Saved" |
| IAP product ID 用 `consumable.blindbox.single` | 现有规范是反域名 `com.solocompass.pro.monthly/yearly`,新 consumable 沿用 `com.solocompass.consumable.<feature>.<sku>` |
| VoiceAgentToolRouter 当前 tool 数 | 实际 grep 出 10 个 (与 explorer 报告一致),新增 8 个不冲突 |

---

## v1.0 骨架落地状态 (2026-07-01)

**Phase 1**: 主线 20/22 = 90.9% ✅ (报告见 `todo.md`)
**Phase 2**: 骨架 27/34, 剩余 = 独立 UI polish PR + CI/内测 + IAP StoreKit
**Phase 3**: 骨架 22/26, 剩余 = 外部资产 + 印刷商 spike + 灰度发布
**横向**: 9/10 (visual snapshot 差 UIHostingController rendering)

**GA 判定 (#393)**: 待以下条件满足才能翻 GA:
1. `ios-ci.yml` 全绿 (`xcodebuild test` 全套)
2. 灵动岛 entitlement 内测 1 周
3. 6 个 IAP consumable 在 App Store Connect 完成配置 + sandbox 购买验证
4. 印刷商合同签订 (Lulu / Shutterfly / 一印)
5. 灰度 10% → 50% → 100% 各阶段 CAC / 自发分享率符合预期

**代码 scope 已完成的 v1.0 契约地基**:
- ✅ 4 张 SwiftData @Model (VisitRecord / TasteProfile / TimeCapsule / AgentMemorySnapshot) 全部 on-device
- ✅ 7 个 P2.1 tool (suggest_now_action / open_blindbox / bury_capsule / recall_pattern / sos_plan / unwalked_path / recall_local_scene) 全部 RAG-anchored
- ✅ 6 个 consumable IAP product ID 常量 (blindbox/sos/unwalked/omen/ost/brag) 在 SubscriptionService 落库
- ✅ ProactiveNudgeScheduler 3 nudge kind + 每日预算共享上限
- ✅ 3 大仪式动画 spec (ANIMATION_SPEC.md): 胶囊接受 / 盲盒揭秘 / 城市签翻面
- ✅ AnalyticsService 5 事件 + 4 漏斗事件, `AnalyticsValue` 类型级禁 PII
- ✅ 忘记我: MemoryDigestService.forgetMe() 同事务清空 memory + taste 单例; ForgetMeService 广义版清空 4 张个人签名表 (含 VisitRecord + TimeCapsule)
- ✅ 灵动岛 3 新 Kind (soloAgentHint / timeCapsule / dailyOmen) + LiveActivityService 3 start 方法 + UserDefaults 日限流 ring
- ✅ CT v2 3 场景 token (capsuleGlow / omenGold / blindboxAmber) 保留给仪式感界面
- ✅ PRIVACY.md 4 表 on-device 承诺 + Forget me 按钮承诺 + parity check 兜底保证

---

## Phase 2 走查清单 (P2.7 #292)

> Phase 2 出口验收: 落地度 + 内测 + 走查文档三件套。本清单勾住 P2.7 #290/#291/#292 的最终交付,任何未打勾项都是 Phase 2 收官阻塞。

**代码落地** (verified 2026-07-01 recon):
- P2.0 Chat Agent 升级 4/4 ✅ (#201 memory 注入 / #202 MemoryDigestService / #203 时段意识 / #204 ForgetMeService 广义版)
- P2.1 Tool router 扩展 7/7 ✅ (7 新 tool handler + 17 case switch 全 exhaustive)
- P2.2 灵动岛 3 新 Kind 6/6 ✅ (#220-#225 Kind + Widget + LiveActivityService + 单测 6/6)
- P2.3 盲盒 Trip 4/5 (BlindboxOrchestrator + Launch + Recap + safetyPolicy 全在; IAP 消费待 App Store Connect 沙盒)
- P2.4 时空胶囊 5/6 (long-press → CapsuleComposeView → CapsuleStore CRUD → CapsuleOpenView 仪式感全在; #244 年末回顾 nudge stub 待 Analytics 累积 30 天)
- P2.5 FilterBar 收敛 2/3 (#250 SoloAgent 入口 + #252 我的菜 toggle 全在; #251 More drawer 待收敛动画调优)
- P2.6 主动 nudge 5/5 ✅ (ProactiveNudgeScheduler + 3 nudge kind + NotificationsSettingsView + dailyBudget 共享上限)

**内测清单** (P2.7 #291, 需真机):
- [ ] 灵动岛限流真机验: 24h 3 次上限、跨日重置
- [ ] 胶囊拆开动画: iPhone 12 mini + iPhone 17 Pro Max 两端粒子性能
- [ ] 盲盒 fallback: 首次盲盒无 Pro 用户走 high-confidence + high-Solo-Score 池
- [ ] Nudge 静音时段: 21:00 后不应触发 lonely-hour
- [ ] Forget me 一键清空: 4 表原子 + UI 立即反映 (NotificationsSettingsView 挂点)

**走查文档** (P2.7 #292, 本段即是):
- ✅ 主线代码落地度对照表 (上)
- ✅ 内测清单 (上)
- ✅ v1.0 契约地基快照 (前段)
