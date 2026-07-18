# Solo Compass Agent 系统深度分析

> 范围：iOS 端聊天 + 语音 agent 全链路（VoiceAgentOrchestrator / Session / ToolRouter / AIService / ChatSheet）。
> 视角：架构、并发、Tool Calling、Context、可观测性、降级、瓶颈与风险。
> 调研基线 commit：`d4801d5`（main）
> 互补阅读：`docs/architecture/agent-pipeline.md`（旧 AgentRouter 删除决策）、`docs/architecture/agent-memory-context.md`、`docs/PRD/voice-agent.md`、`AGENT_LOOP_REDESIGN.md`。

---

## 0. 一句话定位

当前 agent 是一个 **单 turn / 单 agent / 串行 tool-calling 的语音对话编排器**，跑在 `@MainActor` 上，靠 DeepSeek（OpenAI 兼容协议）做规划与回答，9 个本地工具承担所有副作用，UI 通过 `cardsByMessageId` + `reasoningSummaryByMessageId` 把推理过程外化成卡片/chip。它"能跑"，但还不是真正的 **agent loop 系统**：缺分层、缺并行、缺持久化记忆、缺 schema-forced 输出、缺可恢复性。

---

## 1. 主循环结构

### 1.1 调用链（自顶向下）

```
ChatSheet (SwiftUI)
  ↓ onSend(text) / VoiceService transcript stream
VoiceAgentOrchestrator.handleTextInput(_:) / handleTranscript(_:)
  ↓
runTurn(transcript:)              ← 单 turn 入口
  ├─ session.beginUserTurn(...)   ← 切到 .thinking
  ├─ while shouldContinue:
  │    ├─ sendToAIStreaming()
  │    │    └─ AIService.sendAgentMessageStreaming() → AsyncThrowingStream<StreamEvent>
  │    │         ├─ .contentDelta → publishStreaming()（节流 80ms / 60 char）
  │    │         ├─ .toolCall     → 累积到 pending toolCalls
  │    │         └─ .done         → session.appendAssistantTurn()
  │    ├─ if .toolExecuting:
  │    │    ├─ executePendingTools()
  │    │    │    └─ VoiceAgentToolRouter.execute(call)  ← 一次一个，串行
  │    │    ├─ appendCard(from: ToolEffect)
  │    │    ├─ session.appendToolResult(...)
  │    │    └─ session.resumeThinkingAfterTools() → 继续 while
  │    └─ else:
  │         ├─ archiveReasoningTrace()
  │         ├─ session.finishSpeakingTurn()
  │         ├─ speakResponse(finalText)（AVSpeechSynthesizer）
  │         └─ persistConversation() → ChatHistoryStore (SwiftData)
  └─ shouldContinue = false
```

参考：`VoiceAgentOrchestrator.swift:303-611`、`VoiceAgentSession.swift:80-349`、`AIService.swift:445-668`。

### 1.2 并发模型

- **所有状态都在 `@MainActor`**：`VoiceAgentOrchestrator`、`VoiceAgentSession`、`VoiceService` 均为 `@MainActor @Observable final class`。SwiftUI 直接读 published 字段无需 `await`。
- **唯一逃逸 main actor 的点**：`AIService.sendAgentMessageStreaming` 内的 URLSession 流读、`SFSpeechRecognizer` 回调（独立后台队列）、`AVAudioEngine` 的 input tap（实时音频线程）。它们都用 `Task { @MainActor in … }` 回灌主线程。
- **取消**：`turnTask?.cancel()` + 置 nil；在 `stop()`、`rebindContext()`、`restoreConversation()` 各调一次，防止双击 / 快速切场景时的 race。
- **节流**：streaming token 用 80ms / 60 char 双门控（`VoiceAgentOrchestrator.swift:86-114`），防 markdown parser 抖动；最终消息 `force: true` 旁路门控。

---

## 2. 会话状态机

`VoiceAgentSession` 是真正的 FSM 中枢（`VoiceAgentSession.swift:108-116`）：

| 状态                | 进入条件                       | 离开条件                  |
| ------------------- | ------------------------------ | ------------------------- |
| `.idle`             | 初始 / `end()`                 | 用户输入 / 长按麦         |
| `.listening`        | 长按麦克风                     | 松开 / 静音超时           |
| `.transcribing`     | listening 结束                 | STT 给出 final            |
| `.thinking`         | `beginUserTurn()`              | 有 tool / 拿到 final text |
| `.toolExecuting(n)` | assistant turn 含 `tool_calls` | 全部 tool result 回灌     |
| `.speaking`         | `finishSpeakingTurn(text:)`    | 用户中断 / TTS 完成       |

**硬上限（PRD §5.2）**：

- `toolCallsMaxPerTurn = 5`
- `recursionDepthMax = 3`（think→tool→think 最多绕 3 圈）
- `messagesMaxCount = 11`（超过触发压缩）
- `turnTimeoutSeconds = 30`

**压缩**（`VoiceAgentSession.swift:303-349`）：保留 system + 最后 4 条 + 一行摘要把更早 user/assistant 整段抽象成一段 system note。**有损且无回滚**——多轮对话里"两轮前我说过我喜欢咖啡"这种依赖会丢。

**持久化**：`persistedConversationId: UUID` 在会话第一次有 user message 时分配；之后每个 turn 结束 `persistConversation()` 用同一 id 做 upsert，写进 SwiftData 的 `ChatSessionRecord` + `ChatMessageRecord`。System prompt **不存**，恢复时重建。

---

## 3. Agent 概念现状

`Services/Agents/` 目录下其实只有 **两个独立 agent**，且**都不在主对话循环里**：

1. **`EnrichmentAgent`**：把附近 raw POI（高德 / Overpass / MapKit 并行）合成 `Experience[]`，提供 ring-by-ring 渐进 explore。是个无 tool-call 协议的"批处理 agent"。
2. **`WebSearchEnrichmentSource`**：补营业时间 / 电话 / 网址这类客观可核字段，明确 anti-hallucination：解析失败原样返还。

**主对话循环里只有一个隐式 agent**——LLM 自己。它既是 planner、又是 verifier，工具是它的执行器。**没有 planner→executor→verifier 分层，也没有 fan-out 并行**。Tool 一次一个跑（`VoiceAgentOrchestrator.swift:598`）。

历史上确实存在过 `AgentRouter`（IntentAgent → QueryAgent → GuideAgent 三段式），但 `docs/architecture/agent-pipeline.md` 已决策删除——它从未被生产路径接通，feature flag 形同虚设。**当前架构等于回到单 LLM 自规划**。

这就是结构性瓶颈：扩展能力 = 改 prompt + 加 tool，遇到"先并行调研三个候选区，再选一个建路线"这类需求要么变成 6 轮串行（撞 recursion budget = 3），要么塞回 prompt 里赌模型一次性产 6 步 tool_calls（但目前没启用 `parallel_tool_calls`）。

---

## 4. Tool Calling 层

### 4.1 9 个工具（`VoiceAgentToolRouter.swift:80-228`）

| Tool                     | 副作用                                               | 返回                                                    |
| ------------------------ | ---------------------------------------------------- | ------------------------------------------------------- |
| `explore_nearby`         | progressive explore + 空环自动扩张                   | `{added_count, auto_expanded_stages, search_exhausted}` |
| `filter_by_category`     | `MapViewModel.selectCategory()`                      | `{visible_count}`                                       |
| `show_details`           | **不**自动开详情页，转 `ToolEffect.experiences` 卡片 | `{experience_id, title}`                                |
| `save_to_favorites`      | `UserPreferences.toggleFavorite()`                   | `{now_favorited}`                                       |
| `dismiss_recommendation` | 从可见集移除                                         | `{visible_count}`                                       |
| `search_places`          | 等价 explore + query                                 | 同 explore                                              |
| `navigate_to`            | 启动 Apple/Google Maps                               | `{ok}`                                                  |
| `build_route`            | `AIService.generateRoute()` → `RouteProposal`        | `{route_title, stop_count, estimated_minutes}`          |
| `filter_visible`         | 本地无网络过滤                                       | `{remaining_count}`                                     |

### 4.2 协议

- **OpenAI 兼容**：streaming 增量解析 `delta.tool_calls[idx]`；非流取 `message.tool_calls[]`。**自己 parse arguments JSON，没有强制 schema 校验**（`AIService.swift:542-545`）。
- **结果回灌**：`{ok: true, ...}` 或 `{ok: false, error: "..."}` 作为 `role: tool` 消息塞回对话历史。
- **副作用解耦**：每个 tool 跑完留下 `lastEffect: ToolEffect`，orchestrator 据此 `appendCard(...)` 到 `cardsByMessageId[assistantId]`，UI 自然出现在该轮对话气泡下方——这套 effect-pattern 是这套系统少有的干净抽象。

### 4.3 风险

- **错误是字符串**：tool 崩了 → 返回截断 JSON → 模型继续推理 → 用户看到困惑回答，没人 retry、没人提醒。
- **串行**：3 个 `explore_nearby` 必须 3 轮，模型自己也意识不到能并行。
- **没有"延后兑现"**：长任务（路线生成 2s）整段阻塞 turn loop。

---

## 5. Context 注入

两层（`VoiceAgentOrchestrator.swift:735-863`）：

**A. Session 种子（一次性）**——`buildSystemPrompt(experience:)`：

- 角色描述 + 用户当前经纬度（8 位精度）
- 可选 `<experience_context>` XML 块（scoped chat 时）
- 可选 `CONTEXT SNAPSHOT` JSON（来自 `DefaultContextManager.snapshot()` actor，含偏好 / 天气 / visible top 20）
- 9 个 tool 目录（行内描述 + 参数约束）
- 50 行规则：引用 `[exp:id]`、不虚构 id、不自动导航、最多一个澄清问题…

**B. 每轮刷新**（前缀注入）——`prependContextRefresh(to:)`：

```xml
<latest_context>
  hour: 14
  tz: Asia/Bangkok
  coord: [100.5215, 13.7458]
</latest_context>
<user>...原始 transcript...</user>
```

**风险**：

- 系统 prompt 改一次，所有现有 DeepSeek KV cache 失效。
- `<latest_context>` 是松散 XML 字符串注入到 user message，没用单独 role 或 message envelope，理论上有 prompt-injection 面。
- visible list 仅前 20，密集城区会 truncate。

---

## 6. 结构化输出 & 解析

**iOS 端解析的三类结构化对象**：

1. `AIResponse`（voice intent）：`recommendedIds[] / explanation / filterSuggestion`
2. `GeneratedRoutePlan`（route gen）：`orderedIds / title / summary / reasonNow / tags`
3. `EdgeResponse`（synthesize via Supabase Edge Function）：`experiences[]`

**解析流程**：strip 三引号 fence → 提取首个 `{` 到末尾 `}` → `JSONDecoder.decode` → 失败回 fallback。

**问题**：

- 没用 DeepSeek `response_format: { type: "json_object" }`（packages/ai 的 Node 侧用了，iOS 端没启）。
- 没用 tool-call schema 强制输出（structured output 完全靠 prompt 哀求）。
- parse 失败的 fallback 是质量明显下降的 skeleton / 贪心路径，UI 上只挂一个 `.skeleton` badge。

---

## 7. UI 渲染管线

- **消息列表**：`ChatSheet.messageList` 用 LazyVStack，每条消息后串联 `ChatCardStack`（卡片）+ `ReasoningSummaryChip`（推理总结）。
- **流式 caret**：`MessageBubble.StreamingCursor`，2pt 圆角矩形闪烁（尊重 `reduceMotion`）。
- **推理两态**：
  - 进行中 → `AgentStatusLine`（单行 spinner + 当前 step label cross-fade）
  - 完成后 → `ReasoningSummaryChip`（折叠 / 展开，展开后竖向 bullet trace）
- **卡片两种**：`.experiences(id, [Experience])`、`.route(id, RouteProposal)`，键是 assistant message UUID。
- **历史**：`ChatHistoryListView` 列 SwiftData 里的 sessions，点行 `restoreConversation(id:messages:)` 重放，**卡片不重建**——重放仅恢复文本对话，历史卡片永久丢失。

---

## 8. 语音链路

- **STT**：`AVAudioEngine` input tap（1024 buffer，实时线程）→ `SFSpeechAudioBufferRecognitionRequest.append` → `recognitionTask` 回调 yield `bestTranscription.formattedString` 到 `AsyncThrowingStream<String>`。partial 是 **replace**（不是 append），UI 自维护缓冲。
- **TTS**：`AVSpeechSynthesizer`，rate 0.52、pitch 1.05；每次 stop / rebind / restore 主动 `stopSpeaking(at: .immediate)`。
- **音频会话隔离不彻底**：input 用 `.record` category，TTS 跑系统默认。TTS 期间用户难以打断说话；测试 `VoiceInterruptionToastTest` 只测了 toast 文案，没测播放中按麦的复活路径。
- **严格并发**：`SWIFT_STRICT_CONCURRENCY: complete` 开着；`VoiceServiceActorIsolationTest` 编译期断言 `VoiceService` 必须是 `@MainActor`。

---

## 9. 可观测性

`AIObservability.swift` 统一入口：

| 项          | 字段 / 动作                                                                          |
| ----------- | ------------------------------------------------------------------------------------ |
| Token usage | `prompt_tokens / completion_tokens / total_tokens / latencyMs / cached`              |
| 事件        | `synthesis_success / cache_hit / quota_exceeded / tool_executed / skeleton_fallback` |
| 工具分布    | `toolCallCounts: [String: Int]`                                                      |
| 错误        | Sentry breadcrumb + `os.Logger`（不带原始 body）                                     |

**缺口**：

- 没有 turn-level trace ID 串起 user → LLM → tools → final answer。
- 没有 reasoning step 持久化（archive 只在内存）。
- 没有"模型选了哪个 tool / 跳过了哪个 tool"的 attribution。

---

## 10. 降级链

```
有 ANTHROPIC/DEEPSEEK key 且配额未满
  → 正常 streaming agent
配额超 (Pro 30/d) OR JSON parse 失败
  → skeleton：Solo Score 7.0 / 默认文案 / .skeleton badge
key 缺失
  → recommendExperiences = Solo Score 排序
  → generateRoute = nearest-neighbor 贪心
网络失败
  → 同 skeleton + lastError 保存
```

**优点**：app 永远不会"白屏"。**缺点**：离线和在线推荐差距大；fallback 没有"上一次成功的 AI 排名缓存"复用。

---

## 11. 五大瓶颈 / 风险（按影响排序）

### R1 · Tool 串行 + recursion budget = 3 → 复杂意图被静默截断

- 位置：`VoiceAgentSession.swift:41`、`VoiceAgentOrchestrator.swift:457-459`
- 表现：第 4 轮被强制 "summarize what you know" 收尾，用户看到一个含糊回答，**没有"我没想完"提示**。
- 影响：多步链式任务（先 explore 三类 → 选其一 → 建路 → 排序 → 解释）天然撞墙。

### R2 · 上下文压缩有损且不可逆

- 位置：`VoiceAgentSession.swift:303-349`
- 表现：>11 条后中间 turns 被替换成一行 system 摘要，"两轮前我说过 X" 类约束消失。
- 影响：长对话越聊越蠢；恢复历史时无法看出"被压过"。

### R3 · 卡片只在执行时生成，恢复历史会永久丢失

- 位置：`VoiceAgentOrchestrator.swift:615`、`ChatHistoryStore`
- 表现：`appendCard` 仅在 `executePendingTools()` 期间触发；replay saved messages 不会重建卡片。
- 影响：用户翻到昨天的对话，"AI 推荐的咖啡馆卡片"消失，只剩干文字，体验断层。

### R4 · 结构化输出零强制，靠 prompt 哀求

- 位置：`AIService.swift:445-668`、`packages/ai` 与 iOS 端不对称
- 表现：iOS 没启 `response_format: json_object`，没用 tool schema 校验；解析失败默默 fallback。
- 影响：模型有时回多余 markdown / 错 id / 漏字段 → skeleton 增多 → 用户感觉 AI 不稳定。

### R5 · Tool 错误 / 超时是一团字符串

- 位置：`VoiceAgentSession.swift:233-242`、`VoiceAgentOrchestrator.swift:598-608`
- 表现：HTTP 超时 → tool 返回截断 JSON → 模型接着推理"已知信息" → 用户看到错答。
- 影响：可靠性顶层封死——重试 / 替代源 / 用户可见错误都没有。

---

## 12. 现状能力地图（自评）

| 维度                  | 当前 | 注解                                     |
| --------------------- | ---- | ---------------------------------------- |
| 单轮回答质量          | 7/10 | DeepSeek + 强 system prompt + 引用规范   |
| 多步任务能力          | 4/10 | 串行 + budget=3 + 无并行                 |
| 上下文连续性          | 5/10 | 压缩有损、无长期记忆                     |
| 工具可靠性            | 5/10 | 无 schema 校验、无 retry、无降级源       |
| 可观测性              | 6/10 | Sentry + Logger 完整，但 turn trace 缺失 |
| 用户感知透明          | 7/10 | 推理 chip + 卡片 inline，但失败不可见    |
| 离线可用              | 6/10 | 全套 fallback，但与在线断层              |
| 隐私 / Prompt 安全    | 6/10 | XML 拼接有 injection 面                  |
| 可恢复（断网 / 重启） | 4/10 | 卡片丢失、压缩有损                       |
| 扩展性（加新 agent）  | 3/10 | 单 LLM、无 planner 分层                  |

---

## 13. 关键源代码索引

| 文件                                              | 行      | 角色                                                |
| ------------------------------------------------- | ------- | --------------------------------------------------- |
| `VoiceAgentOrchestrator.swift`                    | 303-611 | turn loop / streaming / tool dispatch / persistence |
| `VoiceAgentSession.swift`                         | 80-349  | 状态机 / 消息历史 / 压缩                            |
| `VoiceAgentToolRouter.swift`                      | 80-643  | 9 个 tool 定义 + ToolEffect 副作用                  |
| `AIService.swift`                                 | 445-668 | DeepSeek streaming + tool serialization             |
| `AIModelRouter.swift`                             | 59-97   | per-kind model 路由                                 |
| `AIObservability.swift`                           | 56-153  | token / event / tool 统计                           |
| `Services/Context/ContextManager.swift`           | actor   | LLMContext snapshot                                 |
| `Services/Agents/EnrichmentAgent.swift`           | —       | POI 合成 batch agent                                |
| `Services/Agents/WebSearchEnrichmentSource.swift` | —       | anti-hallucination 字段补                           |
| `ChatSheet.swift`                                 | 325-437 | 消息列表 / 卡片 / chip 渲染                         |
| `ChatHistoryStore.swift`                          | 40-150  | SwiftData 持久化                                    |
| `VoiceService.swift`                              | 75-148  | STT 流 + actor 隔离                                 |

---

## 14. 一句话结论

> **现状是一个能跑的 demo 级 agent，不是一个 production-grade agent loop。**
> 它的天花板由三件事决定：(1) 单 agent / 串行 tool / budget=3 的循环骨架；(2) 无强 schema 的脆弱输出契约；(3) 有损压缩 + 卡片不回放的会话连续性。
> 下一阶段升级方向见 `AGENT_LOOP_REDESIGN.md`。
