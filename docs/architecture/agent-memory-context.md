# RFC: Agent Memory & Context Architecture

**Status:** Draft · **Date:** 2026-06-05 · **Scope:** iOS (`apps/ios/SoloCompass`) · **Storage:** Local-first (SwiftData)

> 把现有的"无记忆 agent loop"升级为"有上下文、有记忆、会学习"的旅行 agent。
> 这是 MCP 工具抽象层与 Skills 技能包的**地基** —— 没有这一层,工具调用与技能选择都只能基于"当下这句话",无法个性化。

---

## 1. 背景与问题陈述

Solo Compass 的 iOS 端**已经有一套真实的 agentic 系统**(不是 prompt 模板):

- **`VoiceAgentOrchestrator`** — `think → tool_execute → repeat` 工具循环,带硬上限
  (`recursionDepthMax=3`, `toolCallsMaxPerTurn=5`, `messagesMaxCount=11`, `turnTimeout=30s`)。
- **`AgentRouter`** — `Intent → Query → Guide` 三段流水线(feature flag 默认开)。
- **9 个硬编码工具**(`VoiceAgentToolRouter.allTools`)。
- **`ContextManager`** — 每次会话注入 location / viewport / preferences / time 快照。

**但这套 agent 跑在"健忘症"上。** 当前成熟度:

> **单会话有状态 + 实时上下文(Stage 2 早期)** —— 一次对话内记得,sheet 一关全忘,且**从不从用户历史学习**。

### 1.1 最刺眼的事实:记忆素材全在,却没接给 agent

SwiftData 里**已经躺着丰富的用户信号,但 agent 一个都看不到**:

| 信号                                        | 收集    | 持久化 | **喂给 agent?**                  | 证据                                            |
| ------------------------------------------- | ------- | ------ | -------------------------------- | ----------------------------------------------- |
| 对话历史                                    | ✅ 内存 | ❌     | ❌ 冷启动                        | `VoiceAgentSession.swift:130`                   |
| 去过的体验 `UserCompletionRecord`           | ✅      | ✅     | ❌ **孤岛**                      | `Persistence/Models/UserCompletionRecord.swift` |
| 收藏 `UserFavoriteRecord`                   | ✅      | ✅     | ❌ **孤岛**                      | `Persistence/Models/UserFavoriteRecord.swift`   |
| 微调查 `MicroSurveyRecord`(舒适度/压力 1–5) | ✅      | ✅     | ❌ **孤岛**                      | `Persistence/Models/MicroSurveyRecord.swift`    |
| 偏好 `UserPreferences`                      | ✅      | ✅     | ⚠️ 静态注入,手动设、**从不学习** | `Models/UserPreferences.swift`                  |

**结论:提升 memory 的第一步不是"造数据",而是"接线"。** 数据已存在,只缺一条把它们汇成"用户画像"并注入 system prompt 的管道。这把最高价值那步的成本大幅降低 —— 无需先建埋点、攒数据。

### 1.2 两个实现级缺陷(真实代码事实)

1. **Context 只在会话开始拍一次,之后不刷新。**
   `buildSystemPrompt(experience:)` 在 session 开始把 `ctx.jsonString()` 焙进 system prompt(`VoiceAgentOrchestrator.swift:99` 调用 + `:449` 附近的 `CONTEXT SNAPSHOT (JSON)` 区块),后续轮次不再重拍。
   → 用户在对话中走动、过了一小时、地图划走,agent 仍拿着开场快照。对**地图优先、位置驱动**的 App 是体验硬伤。

2. **压缩是"朴素文本截断",不是 LLM 摘要。**
   `VoiceAgentSession.compactIfNeeded()`(`:278-311`)超过 11 条丢弃中间消息,拼成 `"Earlier user turns (summarised): …"`。名为 summarised 实为有损丢弃 —— 关键信息(如"我膝盖不好不能走远")可能在第 5 轮被截掉。

---

## 2. 设计目标 / 非目标

**目标**

- G1 让 agent 在**每一轮**看到新鲜的实时上下文(位置/时间/视口)。
- G2 让 agent 看到**用户画像**(由已存在的 completion/favorite/survey 合成)。
- G3 对话可**跨会话恢复**(关掉重开记得上次)。
- G4 行为信号可**反推偏好**(用户初始自报常常不准)。
- G5 全程**本地优先**:隐私好、离线可用、无后端强依赖。
- G6 为 MCP 工具抽象层 / Skills 技能包提供共享的用户状态地基。

**非目标(本 RFC 不做)**

- N1 向量 / 语义 RAG(L5)—— 列为未来,不在本期。
- N2 后端同步 memory / 多设备漫游 —— 本期纯本地;预留接口但不实现。
- N3 模型微调 / 个性化训练。
- N4 触碰 `AgentRouter` 的拓扑改造(条件边/回环)—— 那是另一份 RFC。

---

## 3. 记忆分层模型(核心)

"Agent memory" 不是一个东西,是多层。当前只有最浅的半层。

```
┌─ L5 语义长期记忆(RAG)──────────── ❌ 本期不做(N1)
│   用户历史 embedding,按相似度召回"你以前喜欢的安静咖啡馆"
│
├─ L3 用户画像(结构化长期记忆)──── ★ 本期重点,最高 ROI
│   "去过 12 家 solo 咖啡馆,食物评 4.5,讨厌夜店" ← 由孤岛数据合成
│   数据已存在,只缺合成 + 注入
│
├─ L2 跨会话对话记忆 ────────────── 本期实现
│   关掉重开还记得上次聊到哪(ConversationRecord 当前只存元数据)
│
└─ L1 单会话工作记忆 ─────────────── ⚠️ 已有但有缺陷 → 本期修补
    会话内消息历史 + context;缺陷:context 不刷新、压缩有损截断
```

> 注:L4 = 偏好学习闭环(见 4.4),逻辑上依附 L3 之上、L5 之下,故编号保留。

**实现顺序(投入产出比排序):L1 修补 → L3 接线 → L2 持久 → L4 学习 → L5 按需。**
不要从 L5 开始 —— 最贵、最性感、对当前阶段最不划算。

---

## 4. 分层详细设计

### 4.1 L1 — 单会话工作记忆(修补)

**问题 A:context 不刷新。**
方案:把 context 从"焙进 system prompt"改为"每轮作为一条轻量 system 消息刷新"。

- `ContextManager.snapshot()` 已是 `< 50ms` 的 actor 调用,适合每轮调。
- 在 `VoiceAgentOrchestrator` 进入模型调用前,注入/更新一条 `role: .system` 的 `LIVE CONTEXT` 消息(只保留**易变字段**:location、localTime、viewportBBox)。
- system prompt 里的 `CONTEXT SNAPSHOT` 退化为**只放不变信息**(用户画像、scope),易变信息交给每轮的 LIVE CONTEXT。
- 这条 LIVE CONTEXT 消息**不计入** `messagesMaxCount`、每轮被新值覆盖(避免堆积)。

**问题 B:压缩有损。**
方案:`compactIfNeeded` 从"截断拼接"升级为"**结构化事实抽取**"。

- 引入 `SessionFacts`:从被丢弃的消息里抽取**约束类事实**(`"can't walk far"`, `"vegetarian"`, `"on a budget"`),而非随便丢。
- 短期可用规则/关键词抽取(零额外 LLM 调用,符合成本约束);中期可选一次 Haiku 级摘要(留 TODO)。
- 抽取出的 facts 并入 L3 的 session 级画像(见 4.2),压缩不再丢关键约束。

**改动面:** `VoiceAgentSession.swift`(compact 逻辑 + LIVE CONTEXT 消息类型)、`VoiceAgentOrchestrator.swift`(每轮刷新)。**无新依赖。**

### 4.2 L3 — 用户画像(接线,最高 ROI)

把已存在的孤岛数据合成一段**人类可读的画像**,注入 `buildSystemPrompt`。

**新增组件:`UserProfileService`(`@MainActor`,纯本地)**

```swift
/// 从 SwiftData 行为记录合成一段注入 system prompt 的用户画像。
/// 纯本地、可降级(无数据 → 返回 nil,system prompt 不变)。
@MainActor final class UserProfileService {
    /// 由 completion/favorite/survey 聚合出的结构化画像。
    func snapshot() -> UserProfileSnapshot

    /// 渲染成注入 system prompt 的紧凑文本(≤ ~300 tokens)。
    func renderForPrompt() -> String?
}

struct UserProfileSnapshot: Sendable {
    let completedCount: Int                 // UserCompletionRecord 计数
    let topCategories: [(ExperienceCategory, Int)]  // 由 completed+favorited 的 experience 反查 category 聚合
    let favoriteCount: Int                  // UserFavoriteRecord
    let comfortBias: Double?                // MicroSurveyRecord.comfort 均值
    let pressureAversion: Double?           // MicroSurveyRecord.pressure 均值(低=怕压力场合)
    let dislikedSignals: [String]           // recommend=="no" 的体验反查出的品类
    let recencyWindow: DateInterval         // 近 N 天
}
```

**数据来源(全部已存在,字段已确认):**

- `UserCompletionRecord { id, experienceId, completedAt }` → "去过几个、最近偏好"
- `UserFavoriteRecord { experienceId, id, favoritedAt }` → "明确喜欢"
- `MicroSurveyRecord { id, experienceId, comfort 1–5, pressure 1–5, recommend, submittedAt, anonDeviceId }` → "舒适度倾向、怕不怕压力场合、明确不推荐的"
- category 由 `experienceId` 反查本地 `ExperienceRecord` 得到。

**注入点(已有现成位置):**
`VoiceAgentOrchestrator.buildSystemPrompt` 里已有 `CONTEXT SNAPSHOT (JSON …)` 区块。在其后追加:

```
TRAVELER PROFILE (long-term, use to personalize — do not recite verbatim):
- Has completed 12 solo experiences; leans cafe / culture / nature.
- Comfort-seeking: prefers calm, low-pressure spots. Avoid nightlife / high-energy.
- Explicitly disliked: 2 bar-type places.
```

**降级:** 无任何记录(新用户)→ `renderForPrompt()` 返回 `nil` → 完全退回当前行为。零风险。

**改动面:** 新增 `Services/Memory/UserProfileService.swift` + 在 `buildSystemPrompt` 追加一段。**无新依赖。**

### 4.3 L2 — 跨会话对话记忆(持久)

让对话关掉重开能恢复。

**复用/扩展 `ConversationRecord`(当前只存元数据):**

- 当前:`id, requestId, participantIds, type, routeId, lastMessageAt, …`(无消息体)。
- 新增一个 `@Model AgentMessageRecord { conversationId, role, content, toolCallsJSON?, createdAt }`,
  与 voice-agent 会话绑定(用 `scopedExperience?.id ?? "global"` 作为会话 key)。

**恢复策略(避免重放整段历史炸 token):**

1. 重开会话时,按会话 key 拉最近 N 条 `AgentMessageRecord`。
2. **旧轮(超出 messagesMaxCount 的部分)→ 用 4.1 的 SessionFacts 抽取压缩成一条 system 摘要**,不逐条重放。
3. 最近 N 条原样恢复进 `VoiceAgentSession.messages`。

**为什么 L2 排在 L3 之后:** 先有画像(L3),恢复对话才显价值 —— 否则恢复的是"无记忆的旧对话",收益有限。

**改动面:** 新增 `AgentMessageRecord` + `Services/Memory/ConversationStore.swift`(读写/恢复)+ `VoiceAgentSession` 的 seed/恢复钩子。

### 4.4 L4 — 偏好学习闭环(行为反推)

**目标:** 用户初始自报的 `soloTravelStyle / preferredCategories` 常常不准。用行为信号反推真实偏好。

- 周期性(如每 N 次 completion / 应用启动)由 `UserProfileService` 计算"行为推断偏好" vs "自报偏好"的偏差。
- **不直接覆盖**用户手设值(尊重显式设置),而是:
  - 注入画像时标注"behavioral signal suggests X"(让 agent 自己权衡);
  - 或在 UI 上**建议**用户更新偏好("发现你常去咖啡馆,要不要加入偏好?")。
- 这层避免了"静默改用户设置"的反模式。

**改动面:** `UserProfileService` 增加 inferred-vs-declared 对比;可选一个轻量 UI 建议入口。**排在最后,L3 立住后再做。**

### 4.5 L5 — 语义 RAG(未来,本期 N1)

`pgvector` 召回历史交互。**需要后端、需要数据规模、最贵。** 本期只在 RFC 留位,不实现。
若将来做,接口应复用 `UserProfileService.snapshot()` 的输出作为 embedding 输入,保持分层一致。

---

## 5. 与 MCP / Skills 的关系(为什么 memory 是地基)

```
        ┌──────────────── Skills(声明式技能包)────────────────┐
        │  按"用户是谁 + 当下意图"选 {提示片段 + 工具子集}        │
        │            ↑ 需要 L3 用户画像才能选准                  │
        └───────────────────────┬──────────────────────────────┘
                                │
        ┌───────────────────────▼──────────────────────────────┐
        │  ToolProvider(MCP 工具抽象层)                          │
        │  工具调用按 memory 个性化(如默认过滤用户讨厌的品类)    │
        │            ↑ 需要 L3 画像 + L1 实时 context            │
        └───────────────────────┬──────────────────────────────┘
                                │
        ┌───────────────────────▼──────────────────────────────┐
        │  Memory & Context(本 RFC)— L1/L2/L3/L4               │
        │  共享的用户状态:实时上下文 + 用户画像 + 对话记忆        │
        └───────────────────────────────────────────────────────┘
```

- **Skills** 没有 L3,技能选择只能靠当下这句话 → 选不准。
- **MCP/工具** 没有 memory,每次调用都是"陌生人",无法个性化默认值。
- **多 agent 协作** 需要共享的持久 state → 没有 L2/L3,各 agent 各说各话。

**因此 memory/context 不是与 MCP/Skills 并列的需求,而是它们脚下的地基。先做这一层。**

---

## 6. 隐私与降级(本地优先的红利)

- **隐私:** L1–L4 全部本地 SwiftData,不出设备。符合 `docs/PRIVACY.md` 与产品定位。画像注入 prompt 时**不含坐标**(沿用现有 `renderExperienceContext` 的"never include coordinates"约定)。
- **降级链:** 每层独立可降级。无记录 → 画像为 nil;ContextManager 失败 → 退回静态 prompt;ConversationStore 失败 → 退回单会话。**任一层故障不影响 agent 基本可用。**
- **成本:** L1 facts 抽取与 L3 画像合成都用规则/聚合,**零额外 LLM 调用**。仅 L2 旧轮摘要可选一次 Haiku 级调用(留 TODO,默认规则版)。

---

## 7. 数据模型增量汇总

| 模型                     | 状态               | 用途                                    |
| ------------------------ | ------------------ | --------------------------------------- |
| `UserCompletionRecord`   | 复用               | L3 画像来源                             |
| `UserFavoriteRecord`     | 复用               | L3 画像来源                             |
| `MicroSurveyRecord`      | 复用               | L3 画像来源(comfort/pressure/recommend) |
| `UserPreferences`        | 复用               | L4 自报偏好基线                         |
| `ConversationRecord`     | 复用               | L2 会话元数据                           |
| **`AgentMessageRecord`** | **新增**           | L2 对话消息体持久化                     |
| `LIVE CONTEXT` 消息类型  | 新增(内存)         | L1 每轮刷新                             |
| `SessionFacts`           | 新增(内存→可入 L3) | L1 压缩抽取的约束事实                   |
| `UserProfileSnapshot`    | 新增(内存)         | L3 合成画像                             |

新增服务:`Services/Memory/UserProfileService.swift`、`Services/Memory/ConversationStore.swift`。

---

## 8. 实施路线图

| 阶段     | 内容                                                   | 层  | 成本 | 风险             |
| -------- | ------------------------------------------------------ | --- | ---- | ---------------- |
| **P0a**  | context 每轮刷新(LIVE CONTEXT 消息)                    | L1  | 低   | 低               |
| **P0b**  | 压缩改结构化事实抽取(SessionFacts)                     | L1  | 低   | 低               |
| **P0c**  | `UserProfileService` 合成画像 + 注入 buildSystemPrompt | L3  | 中   | 低(可降级)       |
| **P1**   | `AgentMessageRecord` + ConversationStore + 恢复        | L2  | 中   | 中               |
| **P2**   | 行为反推偏好(inferred vs declared)                     | L4  | 中   | 中(避免静默覆盖) |
| **未来** | pgvector 语义记忆                                      | L5  | 高   | —                |

每阶段独立可上线、独立可灰度(沿用现有 `FeatureFlags` 习惯)、独立可降级。

---

## 9. 验证

- **L1:** 单测 — 会话中改变 location/time,断言下一轮 LIVE CONTEXT 反映新值;压缩后断言关键约束(如 "can't walk far")仍在 SessionFacts。
- **L3:** 单测 — 构造 completion/favorite/survey fixtures,断言 `renderForPrompt()` 产出预期画像;无记录时返回 nil。
- **L2:** 单测 — 写入会话 → 重建 store → 断言最近 N 条恢复、旧轮被摘要。
- **集成:** iOS Simulator 真机验证(`#Preview` 不足以验证 agent 行为)—— 跨 sheet 关闭重开,确认 agent 记得上文。
- 遵循 `CLAUDE.md`:改动后 `xcodebuild build` + 相关 XCTest;触碰 `packages/core` 的话 `pnpm parity:check`(本 RFC 主要在 iOS 层,预计不触碰 core schema)。

---

## 10. 开放问题

1. L2 恢复时,scope 切换(global ↔ per-card chat)是否各自独立的会话线程?当前倾向:是(用 scope key 区分)。
2. 画像注入的 token 预算上限定多少?初定 ≤300 tokens,需在真机量。
3. L4 行为反推是否需要用户可见的"隐私开关"?倾向:是(设置项,默认开,可关)。
4. `MicroSurveyRecord.anonDeviceId` 已为 Epic E 后端同步预留 —— L5 上后端时是否复用该 anon 身份?
