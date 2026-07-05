# PRD: Solo Confidence Refactor v1 — 把产品彻底收敛到「信心层」

| 字段     | 值                                                              |
| -------- | --------------------------------------------------------------- |
| 版本     | v1.0 草稿                                                       |
| 创建日期 | 2026-07-05                                                      |
| 范围     | apps/ios/SoloCompass 为主 · packages/core schema 为辅           |
| 力度     | 彻底重构 — 单一北极星,砍掉偏离信心层的功能面                    |
| 关联     | 复用并升级 `prd-now-score-v1.md`;回归 `docs/PRODUCT_BRIEF.md`  |
| 前置研究 | 数字游民/独行者需求金字塔(见 §3)                              |

---

## 1. 为什么要重构:一次「回归初心」

`docs/PRODUCT_BRIEF.md` 定义的产品是锋利的:

> 打开 App 就是地图,地图上自动显示周边值得做的事——为**独自**旅行者设计的活地图。

它的反目标(Anti-goals)白纸黑字写着:

- **No social feed.** No following, no posting, no likes.
- **No gamification.** No points, badges, leaderboards.
- **Group features** 明确 out of scope:"The product is solo."

但当前 iOS 代码库已经严重偏离自己定的边界。实际存在的功能面:

| 偏离面           | 代码证据(实际文件)                                                      | 属于需求金字塔哪层 |
| ---------------- | -------------------------------------------------------------------------- | ------------------ |
| 结伴 / 路线同行  | `Views/Companion/` 30+ 文件、`CompanionService`、`RouteCompanion`          | 第 4 层 归属/社交  |
| 好友社交图谱     | `Views/Friends/`、`FriendsService`、friend-code、QR 加好友                 | 第 4 层 归属/社交  |
| 聊天 / Agent 对话 | `Views/Chat/` 20+ 文件、`ChatService`、`SoloOrb`、`SoloAgentBubbleQueue`   | 偏 assistant,散焦 |
| 娱乐化包装        | `Blindbox`、`Brag`、`Capsule`、`Omen`、`Insight`、`BragCardComposer`       | gamification 味    |

**诊断:产品在往「belonging 层(社交)」和「gamification」漂移——而这两层既是市场血海(nomadtable / TripBFF / NomadHer / Nomad List Friend Finder 全在打),又正是 brief 自己列的反目标。** 真正的差异化资产 `SoloScore`(`packages/core/src/solo-score.ts`)、`Confidence`(`confidence.ts`)、`NowScore`(`Models/NowScore.swift`)反而被淹没在这些面里。

这次重构的目标:**把这三个资产从配角提为唯一主角,砍掉/降级偏离信心层的一切。**

---

## 2. 北极星:一个问题

整个产品只回答一个问题,所有界面、排序、文案都服务于它:

> **「我一个人,现在,去这里,会不会是段好体验?」**
> *"If I go here, alone, right now — will it be good?"*

拆成三个可计算的子问题,恰好对应已有的三个资产:

| 子问题                     | 资产           | 现状                                             |
| -------------------------- | -------------- | ------------------------------------------------ |
| 现在是不是好时机?          | **NowScore**   | 已有 v1 骨架(bestTimes/天气/日落),需提为主角  |
| 一个人去尴不尬、安不安全?  | **SoloScore**  | schema 完整(6 维),UI 未成主线                  |
| 这条信息可不可信、新不新?  | **Confidence** | schema + 衰减逻辑完整,健康度点未贯穿全局         |

**信心 = NowScore × SoloScore × Confidence。** 这是 Google/Apple 地图、小红书、Nomad List 都算不出来的合成量,是护城河。

---

## 3. 定位依据:独行者需求金字塔(前置研究结论)

到新城市的需求分四层,竞争密度递变:

1. **生存/落地(24h)** — 上网、住得安全、机场进城。→ 血海(Nomad List、Google Maps、eSIM),**不参战**。
2. **功能/立足(72h)** — 能干活的咖啡馆、吃饭、通勤、建立节奏。→ 一堆平庸目录,**可切入但非主战场**。
3. **独自的底气(solo 独有)** — 「一个人现在去行不行/尴不尴尬/安不安全」。→ **几乎无人做 = 主战场 = 信心层**。
4. **归属/社交** — 认识人、结伴。→ 极度拥挤,**规避**(两个独行者自然相遇 OK,但不为它建功能)。

数据支撑:压垮数字游民的第 1、2 大原因是**孤独与漂泊疲劳**,而非找不到景点;且现有 app「为旅行设计而非为在一地生活设计」,头几天需求断裂、靠多 app 拼凑。信心层正是把「独自决策」这件断裂的事缝起来。

> 结论:主攻第 3 层,轻触第 2 层,规避第 1、4 层。

---

## 4. 重构后的产品原则(收敛,不新增)

保留 brief 三支柱,并补一条:

1. **Map-First** — 地图是唯一主屏。无 tab、无抽屉。(现状已符合:`CompassMapView` 是根。)
2. **Experience-as-Unit** — 点是「值得做的事」,不是「存在的地点」。
3. **AI 只筛选、不替你决定** — 从多到少 + 解释,永远给 options 不给 the answer。
4. **【新】信心可见、可证伪** — 每个推荐都必须能回答北极星的三个子问题,且把不确定性摆在明面(健康度点 🟢🟡🔴⚫ 贯穿全局)。

任何功能若把产品拉向 social feed / gamification / group,即为「smell」,本次一律砍或降级。

---

## 5. 信息架构重构

### 5.1 目标形态:会「呼吸」的地图

同一家店,晚 7 点和晚 11 点对独行者是两个地方。地图必须随 **时间 × 位置 × 独自情境** 实时变化:

- **Marker** 的视觉状态由 `NowScore` 驱动(而非静态 bestTimes 布尔)。此刻高分的点「发光/上浮」,低分的点收敛。
- **底部「此刻卡片」(Now Card)** 取代当前一堆入口,成为地图之外唯一常驻元素(详见 §6.4)。
- **Filter** 从「按类别」升级为「按信心」:Now / Solo-friendly / Trusted 三个信心维度切片。

### 5.2 功能三分:留 / 降 / 砍

| 处置       | 功能                                                                                | 理由                                                                 |
| ---------- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| **留(强化)** | 地图 `CompassMapView`、`NowScore`、`SoloScore` 徽章与雷达图、`Confidence` 健康度、Experience 详情、Archive/城市图鉴、语音意图输入 | 信心层核心                                                           |
| **降级(移出主线)** | `Chat` 对话面 → 收敛为「语音/文字问一句 → 出地图筛选结果」的**意图输入条**,不做常驻聊天室;`SoloOrb` 保留为入口不做拟人陪聊 | brief 明确「voice is restrained, not chatty」;聊天室会喧宾夺主        |
| **砍(移出 v1)** | `Views/Companion/` 全部、`Views/Friends/` 全部、`Blindbox`、`Brag`、`Capsule`、`Omen`、`Insight` 娱乐卡 | 全属第 4 层社交 / gamification,即 brief 反目标                       |

> 砍 = 从主导航与主流程移除、feature-flag 关闭、代码移入 `legacy/` 或独立 target,**不删库**(保留未来 A/B 或独立产品的可能)。降级 = 保留能力但退出主界面层级。

### 5.3 砍掉社交后,「不孤独」怎么办?

孤独是真需求,但解法不是自建社交图谱(打不过且违反反目标)。信心层的解法是**降低独自行动的心理门槛**:当 SoloScore 明确告诉你「这家 70% 客人都是一个人来的,坐吧台就行」,独自行动本身就不再孤独。把「敢一个人去」做到极致,是对孤独更本质的回应。真需要认识人时,链接到外部成熟社区(Meetup/青旅),不自建。

---

## 6. 核心功能规格

### 6.1 NowScore 提为主角(升级 `prd-now-score-v1.md`)

- `Experience.nowScore(at:)` 已有骨架(bestTimes/hourOfDay/weather/sunset 信号)。本次**新增两个信号并纳入合成**:
  - `CrowdSignal` — 此刻人流(高峰 vs 空档)。独行者往往**偏好空档**,权重可随 `UserPreferences.pace` 调整。
  - `SafetyTimeSignal` — 该时段独自前往的安全度(接入 `SoloScore.breakdown.safety` 的时段维度)。
- Marker 渲染层(`MarkerIconView` / `MapViewModel.markerState(for:)`)改由 `nowScore.value` 驱动发光/排序。
- 每个 NowScore 必须产出人类可读 `reason`(已是 v1 要求):如「日落还有 23 分钟 · 晴 · 人少」。

### 6.2 SoloScore 产品化

- schema 已完整(`overall` + 6 维 breakdown + `hint` + `basedOnCount`),现有 `SoloScoreBadge`、`SoloScoreRadarChart`。本次:
  - 把 SoloScore 徽章提到 **marker 与卡片的第一视觉位**(与 NowScore 并列),不再埋在详情里。
  - `hint`(如「Order at the bar, sit upstairs」)在卡片直接可见——这是独行者最想要的一句话。
  - `basedOnCount` 可见:诚实呈现「基于几位独行者」。为 0 时显示「AI 估算,待验证」。

### 6.3 Confidence / 健康度贯穿全局

- `decayConfidence` / `healthFromConfidence` 逻辑已存在。本次要求:🟢🟡🔴⚫ **健康度点出现在每一个 marker 与卡片**,不只详情。
- 排序默认**压制 level ≤ 1(AI 未验证)**,不进 top 推荐(brief 已有此要求,需在 `MapViewModel` 排序落实)。
- 「⚫ 可能已不在」的点默认淡出,可手动显示。

### 6.4 「此刻卡片」(Now Card)— 新的常驻主控件

地图底部常驻一张卡,回答北极星:

```
┌─────────────────────────────────────┐
│  ☕ Ristr8to · 现在 87% 好时机          │  ← NowScore + reason
│  日落还有 23 分钟 · 晴 · 人少           │
│  🧍 Solo 8.5  「坐吧台,楼上更安静」      │  ← SoloScore.overall + hint
│  🟢 3 位独行者本周去过 · 已验证          │  ← Confidence 健康度 + basedOnCount
│  [ 带我去 ]        [ 换一个 ]           │
└─────────────────────────────────────┘
```

三行分别 = NowScore / SoloScore / Confidence,一屏答完「现在去行不行」。

### 6.5 意图输入(降级后的 Chat)

保留语音/文字问一句的能力(`VoiceService` + `parse-intent`),但结果是**地图上的筛选高亮**,不是聊天气泡流。例:「找个安静能读两小时书的地方」→ 地图筛出 work/coffee 且 SoloScore.ambiance 高、NowScore 此刻高的点。

---

## 7. Schema 影响(packages/core)

尽量不动 schema(它是护城河)。本次仅需:

- `solo-score.ts`:`breakdown.safety` 补一个**按时段**的可选结构(供 `SafetyTimeSignal` 读),不改现有字段。
- `NowScore`(iOS `Models/NowScore.swift`):新增 `CrowdSignal`、`SafetyTimeSignal` 两个 `NowSignal` 实现,主接口不变。
- `parity:check` 必须绿(TS↔Swift schema 一致性,见 `scripts/check-swift-parity.ts`)。

---

## 8. 分期 Roadmap

> 遵循 `docs/PHASES.md` 的「不跳步、每期有 gate」原则。本重构在现有 iOS 之上做减法与聚焦,分三期。

**R1 · 收敛(1–2 周)** — 纯做减法,零新功能风险
- feature-flag 关闭 Companion / Friends / Blindbox / Brag / Capsule / Omen / Insight 主入口。
- Chat 降级为意图输入条。
- Gate:主流程点击深度下降、地图→决策路径 ≤ 2 步;既有测试全绿;`parity:check` 绿。

**R2 · 信心层三合一(2–3 周)** — 让北极星可见
- NowScore 补 Crowd/SafetyTime 信号并驱动 marker。
- SoloScore 徽章 + hint 提到第一视觉位。
- Confidence 健康度点贯穿 marker/卡片。
- 上线「此刻卡片」。
- Gate:清迈 50 个种子中,任一时段都有点达到「三项皆高」的 demo;10 人可用性测试能在 30 秒说清产品做什么。

**R3 · 打磨与验证(2 周)**
- 排序调优(压制 level≤1)、离线 fallback、性能(nowScore p95 < 5ms,沿用 v1 指标)。
- Gate:回归 `docs/PHASES.md` 的 Phase 2/3 留存口径——需要这 app 的人里,周 2 留存 ≥ 40%。

---

## 9. 成功指标

沿用 brief 的「留存 > DAU」哲学:

- **主指标** — 完成率:展示的推荐里,用户真去做的 %。信心层做对了,这个数应升。
- **主指标** — 需要者的周 2 留存 ≥ 40%(Phase 2 gate)。
- **过程指标** — 地图→决策步数(应降);「此刻卡片」的「带我去」点击率。
- **反指标(应下降或归零)** — 社交/聊天停留时长。若它上升,说明又漂回第 4 层了。

---

## 10. 风险与对策

| 风险                                       | 对策                                                                   |
| ------------------------------------------ | ---------------------------------------------------------------------- |
| 砍社交功能引发已有用户流失                 | 不删库、feature-flag 灰度;若数据证明社交有真实留存,再评估拆为独立产品 |
| SoloScore/Confidence 冷启动数据不足(basedOnCount=0) | 诚实显示「AI 估算」,用第 2 层(咖啡/work)先把种子做深;人工策展前 200 条(见数据冷启动讨论) |
| CrowdSignal 数据源受限于第三方             | 先用 bestTimes + 时段先验做近似,有被动 GPS 后再增强;不阻塞 R2         |
| 「减法」被质疑「砍掉了辛苦做的功能」        | 定位为聚焦而非否定;保留代码;用完成率/留存指标验证聚焦收益             |

---

## 附:一句话总结

**游民不缺信息,缺的是替他/她做过判断的信心。把 NowScore × SoloScore × Confidence 合成的那张「此刻卡片」做到别人做不到,其余全部让路。**
