# Solo Compass — AI Capability Audit (2026 Q2)

**Date**: 2026-05-17
**Branch reviewed**: `main` @ `2f1ffda`
**Auditor**: Claude Code (Opus 4.7)
**Scope**: 全栈 AI 能力（iOS AIService + Voice Agent + Web `packages/ai`）

---

## TL;DR

Solo Compass 已建立**多层级 AI 能力框架**（推荐、OSM 合成、语音意图、多轮 Agent），DeepSeek 集成完整，成本控制清晰。但存在 **10 项明显的设计 gap**，其中 **2 项 P0 阻断 MVP 商业模式**：

- **P0-1**: Agent 缺当前时间注入 → 30% 推荐时段错配
- **P0-2**: Voice Agent 配额未独立 → 3 段对话耗光每日配额

**建议**：优先在本周完成 P0 修复（4-6h），下周推进 P1 工具集 + 重试链路（15h）。

---

## 1. 当前 AI 能力清单

| 功能 | 文件:行 | 模型 | 状态 |
|------|---------|------|------|
| 体验推荐 | `AIService.swift:146-165` | `deepseek-v4-pro` | ✅ |
| 推荐解释 | `AIService.swift:167-177` | `deepseek-v4-pro` | ✅ |
| 单轮语音意图 | `AIService.swift:179-195` | `deepseek-v4-pro` | ✅ |
| OSM POI 合成 | `AIService.swift:510-570` | `deepseek-v4-pro` | ✅ 最完整 |
| 语音 Agent 多轮 | `AIService.swift:237-274` | `deepseek-v4-pro` | ⚠️ 缺时间 + 配额 |
| 意图解析（本地） | `packages/ai/src/parse-intent.ts` | 本地正则 | ✅ 零成本 |
| 体验结构化提取 | `packages/ai/src/prompts/structure-experience.ts` | `deepseek-v4-pro` | ✅ |
| 体验排名 | `packages/ai/src/prompts/rank-experiences.ts` | `deepseek-v4-pro` | ✅ 含 withRetry |

**Voice Agent 工具集**（5 个）— 定义于 `VoiceAgentToolRouter.swift`：
- `explore_nearby(lat, lon, radius_meters)`
- `filter_by_category(category)`
- `show_details(experience_id)`
- `save_to_favorites(experience_id)`
- `dismiss_recommendation(experience_id)`

---

## 2. 模型与 Provider

### 2.1 选型
- 全栈统一用 DeepSeek（OpenAI-compatible）
- 三种调用类型（synthesis / explanation / voice）可通过环境变量独立指定模型，但实际共用同一 key

### 2.2 配额与降级

| 维度 | 机制 | 评价 |
|------|------|------|
| 日配额 | Pro: 30 synthesis / 60 explanation；Free: 0/0 (`AIService.swift:756-762`) | ✅ |
| 合成缓存 | SHA256 缓存键 + 30 天 TTL | ✅ 命中不计配额 |
| 成本追踪 | `cost-tracker.ts` JSON 日志 + PostHog | ✅ |
| Voice Agent 配额 | **未实现独立类型**（共用 `.synthesis`） | 🚨 **P0** |
| iOS 重试 | 无 | ⚠️ P1 |
| Web 重试 | `withRetry()` 已封装 | ✅ |

### 2.3 API Key 风险
iOS 端 key 走 `Secrets.plist` 或环境变量，仍内嵌于 app 二进制。`ARCHITECTURE.md` 提到 Epic E US-031 计划用 Supabase Edge Function 代理，目前 feature flag 后面。

---

## 3. Prompt 质量

| Prompt | 行数 | 领域知识 | 主要问题 |
|--------|------|---------|---------|
| 单句语音处理 | 2 | ❌ 无 | 过简 |
| 推荐 | 4 | ⚠️ 浅 | 无时间感知、无多样性约束 |
| OSM 合成 | 47 | ✅ 详尽 | 过度依赖 OSM 标签 → solo score 都挤在 7.0-7.5 |
| Voice Agent | 系统 prompt 在代码中手写 | ✅ 强 | **仅英文**，PRD 写了中英双语但未落地 |
| 体验提取 | 60 | ✅ 极严格 | 可能过度拒绝 |
| 排名 | 18 | ✅ 中等 | 距离剪枝阈值硬编码 |

---

## 4. Agent / Tool Use 分析

### 4.1 工具集覆盖度
**有**：探索、类别过滤、详情、收藏、忽略
**缺**：
- `filter_by_time_window(start, end)`
- `filter_by_distance(max_km)`
- `filter_by_duration(min, max)`
- `search_text(query)`
- `mark_completed(id, rating?)`

### 4.2 多轮对话状态
- ✅ `VoiceAgentSession` 完整：messages、state machine、recursionDepth ≤ 3
- ✅ 上下文窗口：`messagesMaxCount = 11`，溢出时 `compactIfNeeded()` 合并早期轮次
- ⚠️ 压缩摘要只基于用户输入，无工具执行上下文
- ❌ 无跨会话记忆（与 `PRODUCT_BRIEF` "memory of your day" 目标冲突）

### 4.3 Planner/Executor 分离
- ✅ Orchestrator: `VoiceAgentSession` + `AIService.sendAgentMessage()`
- ✅ Executor: `VoiceAgentToolRouter`
- ⚠️ 工具执行前无 cost prediction

---

## 5. 语音体验

| 维度 | 状态 |
|------|------|
| STT | ✅ `SFSpeechRecognizer` 流式（含 partial transcripts） |
| TTS | ❌ 设计上不支持（PRD L400 明确） |
| 部分转录利用 | ❌ UI 不显示，Agent 不预思考 |
| Barge-in | ❌ 不支持（PRD L404） |
| 回声消除 | ❌ `AVAudioSession` 未开启 AEC |

---

## 6. 个性化与记忆

| 维度 | 状态 |
|------|------|
| 偏好类别 | ✅ 注入推荐 prompt |
| 收藏 | ✅ 存储 |
| 已完成记录 | ❌ 无 UI 也无 schema |
| 评分 | ❌ 无 |
| 历史去重 | ❌ 推荐 prompt 不知道 |
| 跨会话记忆 | ❌ 设计上排除 |

---

## 7. 错误处理与可观测性

### 7.1 降级路径
| 场景 | 降级 |
|------|------|
| API key 缺失 | ✅ Solo-Score 排序 |
| Synthesis 配额耗尽 | ✅ skeleton experiences |
| Synthesis 网络失败 | ✅ skeleton fallback |
| Voice intent API 失败 | ✅ 空 ids + 本地化文字 |
| Agent tool 失败 | ✅ `{ok:false, error}` 回填 |
| 推荐 API 失败 | ❌ **无降级** |
| Overpass 失败 | ❌ 仅异常 bubble up |

### 7.2 可观测性
- ✅ Web: token 计数 + 成本追踪完整
- ⚠️ iOS: 无 token 计数（仅 max_tokens 限制）
- ⚠️ Voice Agent: PRD §9 定义 7 个指标，**代码无埋点**

---

## 8. 改进建议（按优先级）

### 🚨 P0 — 本周必修（合计 4-6h）

#### P0-1: Agent 注入当前时间上下文
**问题**：`VoiceAgentSession` 每轮注入 visibleExperiences 和坐标，但漏 `CURRENT_LOCAL_HOUR`。
**影响**：上午询问可能推荐"晚 7 点"的体验，30% 时段错配。
**方案**：在 `serializeAgentMessages()` (`AIService.swift:279-308`) 前注入 `CURRENT_LOCAL_HOUR: <int>` 系统消息行。
**工作量**：2h

#### P0-2: Voice Agent 配额独立化
**问题**：`sendAgentMessage` 复用 `.synthesis` 配额（30 次/天），5 轮对话耗 ~10 次 → 用户聊 3 段就耗光。
**影响**：MVP 商业模式失败。
**方案**：
1. `AIService.ModelKind` 新增 `.voiceAgent` case
2. `dailyLimit(for:)` 返回 20（Pro）/ 0（Free）
3. `VoiceAgentSession.start()` 入口 `checkAndIncrementQuota(kind: .voiceAgent)`
4. 仪表板独立追踪

**工作量**：4h

---

### ⚠️ P1 — 下两周（合计 ~45h）

#### P1-3: 推荐 Prompt 多样性 + 距离感知重写
**问题**：12 行 prompt 仅注入偏好类别。
**方案**：扩展 `UserContext` 添加 `completedExperienceIds` + `dismissedExperienceIds`；prompt 添加 "Diversity Constraint" + "Distance Tuning" + "Learned Style" 三节。
**工作量**：6h

#### P1-4: OSM 合成信号分层
**问题**：solo score 都 7.0-7.5，失去区分度。
**方案**：合成前检测 OSM 标签丰富度：
- `< 3 tags` → skeleton mode 不调 AI
- `tourism=viewpoint / amenity=cafe` 等高信号 → 当前 strict prompt
- 显式 confidence level 阶梯

**工作量**：8h

#### P1-5: Agent 工具集扩展（过滤维度）
**问题**：只有 `filter_by_category`，多维过滤需 5-6 轮对话。
**方案**：新增 `filter_by_time_window` / `filter_by_distance` / `filter_by_duration` / `search_text` 4 个工具，更新 system prompt 示例。
**工作量**：8h

#### P1-6: iOS 重试 + 多模型 fallback
**问题**：iOS 端无重试，单次失败即 30s 超时。
**方案**：新增 `sendMessageWithRetry()` 包装，指数退避 (1s, 2s, 4s) ≤ 3 次，仅 5xx/超时重试。
**工作量**：4h

#### P1-7: 部分转录 UI 反馈
**问题**：说话时无视觉反馈。
**方案**：ConversationSheet 实时显示 partial transcript。可选：稳定的 partial 触发"思考中"动画。
**工作量**：6h

#### P1-8: System Prompt 中英双语动态选择
**问题**：PRD 写了双语 prompt，代码只用英文。
**方案**：`VoiceAgentSession` 新增 `detectedLanguage`，`serializeAgentMessages()` 按语言选择 system prompt。
**工作量**：3h

#### P1-9: 完成 + 评分闭环
**问题**：schema 有 `completionCount`，但无 UI 也无 Agent 工具。
**方案**：
1. Detail sheet 添加"我已完成"按钮 + 1-5 星评分
2. 新增 `UserExperienceRecord` 模型
3. Agent 工具 `mark_completed(id, rating?)`
4. 推荐 prompt 注入信号

**工作量**：10h

---

### P2 — 阶段二（扩展性）

#### P2-10: Synthesis Prompt 城市参数化
**问题**：示例硬编码曼谷，扩展到东京/欧洲时失效。
**方案**：`cityMetadata: CityConfig` 入参；新建 `packages/data/src/city-osm-profiles.ts` 定义每城市标签规范。
**工作量**：12h

---

## 9. 改进汇总表

| # | 标题 | 优先级 | 预期 ROI | 工作量 |
|---|------|--------|---------|--------|
| 1 | Agent 时间上下文 | P0 | 高 | 2h |
| 2 | Voice Agent 配额分离 | P0 | 极高 | 4h |
| 3 | 推荐 prompt 多样性 | P1 | 高 | 6h |
| 4 | OSM 合成分层 | P1 | 中 | 8h |
| 5 | 过滤工具集 | P1 | 高 | 8h |
| 6 | iOS 重试 | P1 | 高 | 4h |
| 7 | 部分转录 UI | P1 | 中 | 6h |
| 8 | 中英双语 prompt | P1 | 中 | 3h |
| 9 | 评分闭环 | P1 | 高 | 10h |
| 10 | 城市参数化 | P2 | 低 | 12h |

**P0 总计**：6h
**P1 总计**：45h
**P2 总计**：12h

---

## 10. 下一步建议

1. **今天/明天**：将 P0-1、P0-2 拆为 2 个独立 PR 提交
2. **本周内**：完成 P0 验证（Voice Agent 配额日志、时段推荐准确率回测）
3. **下两周**：按 P1-3 / P1-5 / P1-6 / P1-9 优先级推进（用户体感最强的 4 项）
4. **建立基线指标**：在 P1 工作开始前埋好 PRD §9 的 7 个 voice agent 指标，否则改进无法度量

---

## 11. 追问体验深度诊断（C 端关键缺口）

> **核心结论**：当前系统的追问能力 ≈ 0。用户必须一口气说完所有意图，无法基于推荐结果进行深度、连续、有上下文的追问。这是 C 端体验最致命的缺口，也是与 ChatGPT 类产品的本质差距来源。

### 11.1 当前追问能力的真实状态

| 场景 | 能否处理 | 根因 |
|------|---------|------|
| "这家真的安全吗" | ❌ | `soloScore.breakdown.safety` 只是数值；语音上下文不注入 breakdown |
| "第一个和第二个对比一下" | ❌ | `VoiceAgentToolRouter.allTools` 无 compare 工具 |
| "给我便宜点的" | ❌ | 无 `find_alternative` 工具；schema 无价格字段 |
| "为什么推这个不推那个" | ⚠️ 浅 | `explainRecommendation` 单轮、无反事实、不知会话历史 |
| "上次说的那家" | ❌ | `compactIfNeeded` (`VoiceAgentSession.swift:254-287`) 会丢失 id 映射 |
| "这个能带笔记本吗" | ❌ | schema 无设施属性；无 `query_attribute` 工具 |
| "数据准吗" | ❌ | `confidence` 字段从不进 prompt；无 `acknowledge_uncertainty` 工具 |

### 11.2 追问的 8 类用户意图分类

| # | 类型 | 典型话术 | 当前 | 缺失 |
|---|------|---------|------|------|
| 1 | **属性** | "晒不晒""有座位吗""安全吗" | ❌ | `query_attribute(id, attribute)` + breakdown 注入 |
| 2 | **对比** | "三个对比""哪个更近" | ❌ | `compare_experiences(ids, dimension)` + 结构化输出 |
| 3 | **替代** | "便宜点的""更安静的" | ⚠️ 迂回 | `find_alternative(ref_id, change_type)` |
| 4 | **解释** | "为什么推这个""为什么没推 X" | ⚠️ 单轮 | `explain_recommendation(id, against_id?)` 反事实 |
| 5 | **细节** | "地铁怎么去""有 wifi 吗" | ❌ | 数据模型缺字段 + 工具缺失 |
| 6 | **场景** | "晚上去合适吗""女生安全吗" | ⚠️ 部分 | `evaluate_scenario(time/gender/weather)` |
| 7 | **修正** | "不是那个，我要 X" | ⚠️ 易错 | `refine_filter` + activeConstraints 状态 |
| 8 | **元追问** | "数据准吗""多久更新" | ❌ | `acknowledge_uncertainty` + confidence 暴露 |

### 11.3 五个架构层缺陷

#### 缺陷 A: 数据可见性断裂（影响全部追问）
**问题**：`voice-agent.md:298` 注入格式仅 `id + title + category`，丢弃了 `soloScore.breakdown`、`confidence`、`realInconveniences` 等 15+ 字段。AI 看不到的字段无法被追问。

**修复**：扩展 `AIService.swift:279-308 serializeAgentMessages()`，新增 `buildVisibleExperiencesContext` 函数，将 visible top 10 注入为：
```
- exp_osm_123: "Sit with locals at café" [coffee]
  solo_safety=8.5 seating=7.2 quietness=6.1 confidence=L3 risks=[crowd,price]
```
**工时**：1d。**P0**。

#### 缺陷 B: 引用机制缺失（影响多轮）
**问题**：用户说"第二个"时，AI 依赖 `visibleExperiences` 顺序，但顺序在 explore/filter 后会变；`compactIfNeeded()` (`VoiceAgentSession.swift:254-287`) 压缩历史时丢 id 映射。

**修复**：`VoiceAgentSession` 新增 `turnLog: [Turn]`，每轮 `beginUserTurn` (`VoiceAgentSession.swift:175`) 时记录当时的 `visibleExperiencesSnapshot: [String]`；压缩时保留 snapshot 不丢。System prompt 加 "解引用规则" 段。**工时**：1.5d。**P1**。

#### 缺陷 C: 比较能力缺失（对比是第二高频意图）
**问题**：`VoiceAgentToolRouter.swift:50-120` 的 5 个工具全是单数操作。

**修复**：新增 `compare_experiences(ids, dimension)` 工具，按 `soloScore.breakdown` 维度排序，返回对比表 + winner。**工时**：2d。**P0**。

#### 缺陷 D: 修正循环缺失（用户改口时无回退）
**问题**：`VoiceAgentSession.swift:127-137` 只有 messages/state/turnCount，无"当前活跃约束"。用户说"加上有 wifi 的"，系统不知道当前已经过滤了什么。

**修复**：
1. `VoiceAgentSession` 加 `activeConstraints: [QueryConstraint]`
2. `ConversationSheet.swift:114-138` 顶部加 breadcrumb 芯片
3. 新增 `refine_filter(operation, dimension, value)` 工具

**工时**：2d。**P1**。

#### 缺陷 E: 不确定性表达缺失（AI 编造而非承认未知）
**问题**：`confidence` 字段 (`Experience.swift:245-284`) 完整存在，但 AI 在语音对话中从不读，没数据时硬编。

**修复**：
1. 新增 `acknowledge_uncertainty(topic, reason)` 工具
2. System prompt 加规则："`basedOnCount < 3` 或 `lastVerifiedAt > 30 天`必须主动调此工具"
3. `buildVisibleExperiencesContext` 暴露 `confidence_level` 和 `based_on_N_reports`

**工时**：1.5d。**P0**。

### 11.4 UI 引导追问的 4 个组件

#### 组件 1: 建议追问芯片（每次 AI 回复后）
ConversationSheet assistant bubble 下方显示 3 个芯片，基于 `lastToolName` 路由：
- 刚 `filter_by_category` → `[最近的] [安全吗] [有座位吗]`
- 刚 `show_details` → `[怎么去] [要多久] [能带笔记本吗]`
- 刚 `explore_nearby` → `[筛选咖啡] [最近的] [对比一下]`

点击芯片 → 填充 `textDraft` → 用户编辑或直接发送。

#### 组件 2: 约束 Breadcrumb（顶部状态条）
```
[咖啡馆 ×] [安静 ×] [5 分钟步行 ×]
```
显示当前 `activeConstraints`，点 × → 触发 `refine_filter(remove, dimension)`。

#### 组件 3: 长按卡片快捷修饰
地图/列表上长按 experience 卡片 ≥ 0.5s → 弹出菜单 `[更便宜] [更近] [更安静] [对比这个] [有 wifi]` → 选项触发 `onVoiceIntent("我要比这个更便宜的")`。无障碍 + 快速。

#### 组件 4: 撤销 / 重置按钮
ConversationSheet 标题栏：`[⟲ 撤销最后一步] [⊘ 重置]`，分别移除最后一个约束或清空全部。

### 11.5 六个新工具集设计

| 工具 | 用途 | 关键参数 | 工时 |
|------|------|---------|------|
| `query_attribute(id, attribute)` | 是非属性问答 | attribute ∈ {seating_friendly, solo_safe, safe_for_women, has_wifi, crowded_hours, noise_level, toilet_access, parking, pet_friendly, wheelchair_accessible} | 2d |
| `acknowledge_uncertainty(topic, reason)` | 主动声明数据不足 | topic + reason | 1.5d |
| `compare_experiences(ids, dimension)` | 2-5 个对比 | ids: array(2-5), dimension ∈ {safety, quietness, seating, solo_friendly, cost, crowdedness, accessibility} | 2d |
| `find_alternative(ref_id, change_type)` | 替代推荐 | change_type ∈ {cheaper, closer, quieter, safer, more_crowded, less_crowded, faster_service, different_category} | 3d |
| `refine_filter(operation, dimension, value)` | 动态约束 | operation ∈ {add, remove, replace} | 2d |
| `explain_recommendation(id, against_id?)` | 解释 + 反事实 | 可选对比目标 | 2d |

完整 JSON schema 见 [voice-agent-followup-tools 设计文档（待创建）]。

### 11.6 Prompt 系统重构要点

新 system prompt 必须包含以下 6 段（双语硬编码）：

1. **解引用规则**：`"第二个" → visibleExperiences[1].id`，不确定时反问 "Do you mean [name]?"
2. **比较输出格式**：禁止啰嗦逐个念，必须用结构化对比 (winner + score diff)
3. **数据置信度规则**：`L0-1` → "还没用户报告"；`L2` → "有人经过"；`L3+` 可放心引用
4. **诚实度强制**：`basedOnCount < 3` 必须调 `acknowledge_uncertainty`
5. **反事实回答模板**："为什么没推 X" → 调 `explain_recommendation(target, against_id)`
6. **禁止编造**：店名/营业时间/价格/菜单不在 schema 时必须说"不知道"，不能猜

### 11.7 五个北极星指标

| 指标 | 定义 | 埋点位置 | 目标值 |
|------|------|---------|--------|
| **平均追问深度** | 每会话第 2 轮以上的轮数 | `VoiceAgentSession.finishSession` 触发 `AnalyticsService.trackVoiceAgentSession(turnCount)` | ≥ 3.5 轮 |
| **追问解决率** | 追问后产生 tool call 或用户满意确认的比例 | `VoiceAgentToolRouter.execute()` 后 + 用户点赞事件 | ≥ 65% |
| **解引用准确率** | 用户说"第二个"时 AI 锁定正确 experience 的比例 | `turnLog.visibleExperiencesSnapshot` vs 实际 `show_details` id | ≥ 85% |
| **不确定性诚实度** | confidence < 2 时 AI 主动调 `acknowledge_uncertainty` 的比例 | 工具调用计数 / 低 confidence 情况数 | ≥ 70% |
| **追问转化率** | 追问 → save/navigate/detail 的比例 | ConversationSheet 后续触发的 action 事件 | ≥ 50% |

### 11.8 4 周 Sprint 计划

| 周 | 目标 | 交付物 | 工时 |
|---|------|--------|------|
| **W1** | 属性问答 + 诚实度 | `query_attribute` + `acknowledge_uncertainty` + visibleExperiences 字段升级 | ~4.5d |
| **W2** | 对比 + UI 引导 | `compare_experiences` + 建议追问芯片 + breadcrumb | ~4.5d |
| **W3** | 替代 + 引用机制 | `find_alternative` + turnLog 快照 + `refine_filter` | ~4.5d |
| **W4** | 验收 + 埋点 + 发布 | 5 个北极星指标埋点 + E2E 测试 + token 预算审查 | ~3d |

**总工时**：约 14-16 个工程日（单人 4 周可达，含 buffer）。

### 11.9 风险与边界

| 风险 | 缓解 |
|------|------|
| Token 预算爆炸（新 prompt + 更多字段注入） | W1 同步监控 token；W2 做字段裁剪规划 |
| 解引用错误率高（无快照机制） | W3 优先 turnLog；P0 prompt 加"反问澄清"规则兜底 |
| 语音转文本歧义（"第二个" → "地二个"） | Prompt 加音似词修正；鼓励用户说店名 |
| 工具频繁失败（如 explore_nearby 超时） | 降级到现有 dismiss + explore 迂回；记录失败指标 |

### 11.10 与第 1-10 章改进的优先级整合

| 本章追问能力 | 依赖 | 与现有 P0/P1 关系 |
|------------|------|------------------|
| visibleExperiences 字段升级 | 无 | **独立**，可立即做，是其他工具的基础 |
| `query_attribute` | 字段升级 | 不依赖 P0-1/P0-2，可并行 |
| `acknowledge_uncertainty` | 无 | 独立，最低成本 |
| `compare_experiences` | 字段升级 | 受益于 P1-5 工具集扩展 |
| `find_alternative` | P1-3 多样性约束 | 应在 P1-3 之后做 |
| `refine_filter` + breadcrumb | 无 | 独立 UI 工作 |
| turnLog 快照 | 无 | 独立，但与 P0-1 时间上下文同期做最佳 |

**诚实评估**：当前 4 周 sprint 可以做到"能处理 80% 常见追问"，但要达到 ChatGPT 那种自然流畅，还需要：
1. 更丰富的数据模型（价格、营业时间、设施细节）
2. 实时信息整合（天气、人流、活动）
3. 反馈闭环学习（P1-9 评分 + 长期数据积累）

**这是 9 周+ 的长期工作。当前 4 周目标是"打开追问的大门"，而非"关闭所有数据缺口"。**

