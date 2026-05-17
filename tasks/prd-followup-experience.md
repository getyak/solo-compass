# PRD: Voice Agent 追问体验（Follow-up Experience）

**Status**: Draft
**Owner**: TBD
**Created**: 2026-05-17
**Target Sprint**: 4 weeks
**Platform**: iOS only (apps/ios/SoloCompass)
**Related Audit**: `docs/AI_AUDIT_2026Q2.md` 第 11 章

---

## 1. Introduction / Overview

当前 Solo Compass 的 Voice Agent 只能处理单次、扁平的指令（"找咖啡"、"看详情"、"收藏"）。用户**无法基于已经看到的推荐结果进行追问**——"安全吗？"、"哪个更近？"、"换个更便宜的"、"为什么没推那个？"——这些自然的多轮追问全都失效。

根因有三：
1. **AI 看不到完整数据**：注入的 visibleExperiences 只有 `id + title + category`，丢弃了 `soloScore.breakdown`、`confidence`、`realInconveniences` 等 15+ 字段。
2. **工具集只支持单数操作**：5 个现有工具无 compare / find_alternative / query_attribute / refine_filter / explain / acknowledge_uncertainty。
3. **会话状态薄**：无 `turnLog` 快照 → "第二个" 解引用易错；无 `activeConstraints` → 修正循环失败；无 confidence 暴露 → AI 编造而非承认未知。

本 PRD 交付**完整 4 周 sprint**：6 个新工具 + 4 个 UI 组件 + 数据可见性升级 + 引用机制 + 5 个北极星指标埋点，目标是让用户能进行**深度、连续、有上下文的追问**。

---

## 2. Goals

- **G1**: 平均追问深度 ≥ 3.5 轮/会话（当前基线 ~1.2 轮）
- **G2**: 追问解决率 ≥ 65%（追问后产生 tool call 或 save/navigate/detail 转化）
- **G3**: 解引用准确率 ≥ 85%（"第二个 / 那家"映射到正确 experience ID）
- **G4**: 不确定性诚实度 ≥ 70%（`basedOnCount < 3` 时 AI 主动声明，不编造）
- **G5**: 追问转化率 ≥ 50%（追问 → 收藏/导航/详情 的比例）
- **G6**: 8 类追问意图（属性 / 对比 / 替代 / 解释 / 细节 / 场景 / 修正 / 元）中至少 6 类可用

---

## 3. User Stories

工时单位：1d = 1 个工程日。每个 US 含埋点验收（per 用户答案 5A）。

### 阶段 W1: 数据基础 + 诚实度（P0）

#### US-001: 升级 visibleExperiences 富集字段注入
**Description**: 作为 Voice Agent，我需要看到每个 visible experience 的 solo score 分项、confidence、风险、howTo、bestTimes 等字段，以便回答追问而不编造。

**Acceptance Criteria**:
- [ ] 在 `apps/ios/SoloCompass/Services/AIService.swift` 新增 `buildVisibleExperiencesContext(experiences:limit:)` 静态方法
- [ ] 注入格式包含字段：`id`、`title`、`category`、`soloScore.overall`、`soloScore.breakdown` 全 6 维（seatingFriendly / soloPatronRatio / staffPressure / soloPortioning / ambianceFit / safety）、`soloScore.basedOnCount`、`confidence.level`、`confidence.lastVerifiedAt`、`realInconveniences` 全文（截断到 200 字符/条）、`howTo` 步骤摘要（前 2 步）、`bestTimes` 时段
- [ ] Top 10 by `soloScore.overall`（替代当前 top 5）
- [ ] `serializeAgentMessages()` 调用此方法注入到 system message 续段
- [ ] Token 预算监控：单次注入不超过 1500 tokens（超出时按 confidence level 降序裁剪）
- [ ] 单测覆盖：空列表、单个 experience、10 个 experience、超长 inconveniences 截断
- [ ] 埋点：`voice_agent.visible_experiences_injected{count, tokens}` 上报到 Analytics
- [ ] Typecheck（`xcodebuild build`）通过
- [ ] 单测（`xcodebuild test`）通过

**工时**: 1d

---

#### US-002: 新增 `query_attribute` 工具
**Description**: 作为用户，我想问"这家有座位吗 / 安全吗 / 有 wifi 吗"等是非属性问题，AI 应基于真实数据回答，不知道时明说不知道。

**Acceptance Criteria**:
- [ ] 在 `apps/ios/SoloCompass/Services/VoiceAgentToolRouter.swift` 新增工具定义（JSON schema 见 §5 FR-2）
- [ ] 实现 `executeQueryAttribute(args:)` 方法
- [ ] 支持 attribute 枚举：`seating_friendly`、`solo_safe`、`safe_for_women`、`has_wifi`、`crowded_hours`、`noise_level`、`toilet_access`、`parking`、`pet_friendly`、`wheelchair_accessible`
- [ ] 数据源映射：`seating_friendly → breakdown.seatingFriendly`、`solo_safe → breakdown.safety`、`crowded_hours → bestTimes` 反推、其他 → 查 `realInconveniences` 关键词；无数据则返回 `{ok: true, answer: "UNKNOWN", explanation: "no data"}`
- [ ] 返回结构：`{ok, experience_id, attribute, answer: "YES"|"MAYBE"|"NO"|"UNKNOWN", explanation, confidence_level}`
- [ ] System prompt 加段落引导调用此工具（见 FR-7）
- [ ] 单测：每个 attribute 至少 1 个 case（含 UNKNOWN 路径）
- [ ] 埋点：`voice_agent.tool_call{name: "query_attribute", attribute, answer}` 上报
- [ ] Typecheck + 单测通过

**工时**: 2d

---

#### US-003: 新增 `acknowledge_uncertainty` 工具 + 诚实度 Prompt 规则
**Description**: 作为用户，我希望当数据不可靠时（评价数 < 3 或 30 天未验证）AI 主动声明"我不太确定"，而不是编造。

**Acceptance Criteria**:
- [ ] 在 `VoiceAgentToolRouter` 新增 `acknowledge_uncertainty(topic, reason)` 工具
- [ ] 实现 `executeAcknowledgeUncertainty(args:)` 返回 `{ok, topic, message, suggestion}`
- [ ] System prompt 添加"DATA CONFIDENCE RULES"段落（中英双语）：
  - `confidence.level ≤ 1` → 必须说"还没有用户报告"
  - `basedOnCount < 3` 或 `lastVerifiedAt > 30 天` → 必须调 `acknowledge_uncertainty`
  - 禁止使用绝对化语言（"大家都说"、"最好的"、"绝对"）
- [ ] 单测：3 个场景（低 confidence、缺数据、时间过期）
- [ ] 埋点：`voice_agent.uncertainty_acknowledged{topic, reason}` 上报；并埋 `voice_agent.uncertainty_should_acknowledge` 作为基线（基于真实数据状态判断"应该承认"的次数），用于计算诚实度比率
- [ ] Typecheck + 单测通过

**工时**: 1.5d

---

### 阶段 W2: 对比能力 + UI 引导（P0/P1）

#### US-004: 新增 `compare_experiences` 工具
**Description**: 作为用户，我想说"这三个对比一下"、"A 和 B 哪个更安静"，AI 应返回结构化对比 + 明确的 winner。

**Acceptance Criteria**:
- [ ] 在 `VoiceAgentToolRouter` 新增 `compare_experiences(experience_ids, dimension)` 工具
- [ ] 支持 dimension 枚举：`safety`、`quietness`、`seating`、`solo_friendly`、`cost`、`crowdedness`、`accessibility`
- [ ] `experience_ids` 参数：minItems=2, maxItems=5
- [ ] 实现按 dimension 排序逻辑，返回 `{ok, comparison: [{id, title, score, rank}], winner_id, summary}`
- [ ] cost 维度用启发式（按 `category` 推断价格 tier，文档化映射表）
- [ ] crowdedness 维度用 `1 - breakdown.soloPatronRatio` 反推
- [ ] System prompt 加规则："对比时必须用此工具，不可逐个念字段"
- [ ] 单测：每个 dimension 1 个 case + 边界（2 个 / 5 个 / 重复 ID）
- [ ] 埋点：`voice_agent.tool_call{name: "compare_experiences", dimension, count, winner_id}` 上报
- [ ] Typecheck + 单测通过

**工时**: 2d

---

#### US-005: 建议追问芯片 UI
**Description**: 作为用户，我希望每次 AI 回复后看到 3 个建议追问芯片，点一下就能继续追问，降低"接下来该问什么"的认知负担。

**Acceptance Criteria**:
- [ ] 在 `AIService.swift` 新增 `suggestedFollowUps(lastResponse:lastToolName:userLocale:) -> [String]` 静态方法
- [ ] 路由规则：刚 `filter_by_category` → `[最近的, 安全吗, 有座位吗]`；刚 `show_details` → `[怎么去, 要多久, 能带笔记本吗]`；刚 `explore_nearby` → `[筛选咖啡, 最近的, 对比一下]`；刚 `compare_experiences` → `[选第一个, 看详情, 换一组]`；其他 → 空列表
- [ ] 所有芯片文案走 `NSLocalizedString`，en + zh-Hans 两份资源
- [ ] 在 `apps/ios/SoloCompass/Views/Voice/ConversationSheet.swift` 每条 assistant bubble 下方渲染横向滚动芯片（最多 3 个）
- [ ] 芯片点击 → 填充 `textDraft` 状态（用户可二次编辑或直接发送）
- [ ] 芯片样式：Capsule + accentColor.opacity(0.15) + caption2 字号
- [ ] 埋点：`voice_agent.followup_chip_shown{tool_name, chips: [...]}`、`voice_agent.followup_chip_tapped{tool_name, chip_text}` 上报
- [ ] Typecheck + 单测通过
- [ ] 在 iPhone 16 Pro Simulator 中验证视觉效果（启动 `xcodebuild test` + 手动 launch app 截图）

**工时**: 1.5d

---

#### US-006: 约束 Breadcrumb UI + activeConstraints 状态
**Description**: 作为用户，我希望在对话顶部看到当前活跃的过滤约束（"咖啡馆 / 安静 / 5 分钟步行"），并能点 × 移除单个约束。

**Acceptance Criteria**:
- [ ] 在 `apps/ios/SoloCompass/Services/VoiceAgentSession.swift` 新增 `public struct QueryConstraint { dimension: String; value: String; appliedAtTurn: Int; appliedBy: String? }`
- [ ] 新增 `public private(set) var activeConstraints: [QueryConstraint] = []`
- [ ] 新增方法：`addConstraint(_:)`、`removeConstraint(dimension:)`、`replaceConstraint(_:)`、`clearConstraints()`
- [ ] `addConstraint` 时若同 dimension 已存在则替换（不重复）
- [ ] 在 `ConversationSheet.swift` 顶部（messageList 上方）渲染横向滚动 breadcrumb 芯片
- [ ] 每个芯片格式：`{dimension}: {value}` + 右侧 `xmark.circle.fill` 按钮
- [ ] 点 × → 调 `session.removeConstraint(dimension:)`，并触发隐含 user turn：`beginUserTurn(transcript: "取消 {dimension} 限制")`
- [ ] activeConstraints 为空时整个 breadcrumb 区域隐藏（不留空白）
- [ ] 埋点：`voice_agent.constraint_added{dimension, value, source: "user"|"tool"}`、`voice_agent.constraint_removed{dimension, source: "user_tap"|"tool"}` 上报
- [ ] Typecheck + 单测通过
- [ ] 在 Simulator 中验证视觉效果

**工时**: 1.5d

---

### 阶段 W3: 替代 + 引用机制（P1）

#### US-007: 新增 `find_alternative` 工具
**Description**: 作为用户，我想说"换个更便宜的"、"离我更近的"、"更安静的"，AI 应基于参考 experience 找到改进维度上更好的替代选项。

**Acceptance Criteria**:
- [ ] 在 `VoiceAgentToolRouter` 新增 `find_alternative(reference_id, change_type, max_distance_meters?)` 工具
- [ ] 支持 change_type 枚举：`cheaper`、`closer`、`quieter`、`safer`、`more_crowded`、`less_crowded`、`faster_service`、`different_category`
- [ ] 在 visibleExperiences 池中按 change_type 启发式排序，返回 top 5 替代候选
- [ ] 返回结构：`{ok, original_id, alternatives: [{id, title, improvement}], best_id}`
- [ ] `improvement` 字段说明改进幅度（如 `+2.5 on safety` 或 `-30% estimated cost`）
- [ ] System prompt 加规则："用户说'更 X 的'时必须用此工具，不可仅 dismiss"
- [ ] 调用此工具时同步触发 `addConstraint` 添加对应维度（如 `find_alternative(cheaper)` → `addConstraint({dimension: "cost", value: "low"})`）
- [ ] 单测：每个 change_type 至少 1 个 case
- [ ] 埋点：`voice_agent.tool_call{name: "find_alternative", change_type, found_count}` 上报
- [ ] Typecheck + 单测通过

**工时**: 2d

---

#### US-008: 新增 `refine_filter` 工具
**Description**: 作为用户，我想说"也要 wifi 的"、"不要咖啡馆"、"换成饭店"，AI 应正确执行 add/remove/replace 操作并刷新 visibleExperiences。

**Acceptance Criteria**:
- [ ] 在 `VoiceAgentToolRouter` 新增 `refine_filter(operation, dimension, value?)` 工具
- [ ] operation 枚举：`add`、`remove`、`replace`
- [ ] dimension 枚举：`category`、`distance`、`quietness`、`safety`、`crowdedness`、`time_of_day`、`facility`（facility 涵盖 wifi/parking/pet 等）
- [ ] 实现逻辑：调用 `VoiceAgentSession.addConstraint/removeConstraint/replaceConstraint`，然后通过 `MapViewModel` 重新过滤或 explore
- [ ] 返回结构：`{ok, operation, dimension, active_constraints: [...], visible_count}`
- [ ] System prompt 加规则："用户修正意图时必须用此工具，不可仅靠对话历史推断"
- [ ] 单测：3 个 operation × 关键 dimension 共 6 个 case
- [ ] 埋点：`voice_agent.tool_call{name: "refine_filter", operation, dimension, visible_count_after}` 上报
- [ ] Typecheck + 单测通过

**工时**: 2d

---

#### US-009: TurnLog 快照机制 + 解引用 Prompt
**Description**: 作为用户，我说"第二个"或"那家咖啡馆"时，AI 应正确锁定到我当时看到的那条 experience，即使后续 visibleExperiences 顺序已变。

**Acceptance Criteria**:
- [ ] 在 `VoiceAgentSession.swift` 新增 `public struct Turn { userMessage: String; visibleExperiencesSnapshot: [String]; timestamp: Date }`
- [ ] 新增 `public private(set) var turnLog: [Turn] = []`
- [ ] 在 `beginUserTurn(transcript:)` 中接收 visibleExperiences 快照参数并 append 到 turnLog
- [ ] 修改 `serializeAgentMessages()` 注入最近 5 轮 turnLog 摘要：`Turn N: "<user msg>" [saw: id1, id2, id3, ...]`
- [ ] 修改 `compactIfNeeded()` 保留 turnLog 不丢失（独立于 messages 压缩）
- [ ] System prompt 加"REFERENCE RESOLUTION RULES"段落（中英双语）：
  - "第一个/第二个/the N-th" → 映射到当时 turn 的 snapshot[N-1]
  - "那家咖啡馆/那个" → 在 turnLog 中按 title 模糊匹配
  - 不确定时反问 "你是指 {name} 吗?"
- [ ] 调用 `MapViewModel.visibleExperiences.map(\.id)` 作为快照源
- [ ] 单测：3 个场景（顺序变 / 列表压缩后 / 模糊名匹配）
- [ ] 埋点：`voice_agent.reference_resolved{user_phrase, resolved_id, source: "ordinal"|"name"|"asked_clarification"}` 上报
- [ ] Typecheck + 单测通过

**工时**: 2d

---

#### US-010: 长按卡片快捷修饰菜单 UI
**Description**: 作为不想说话的用户（嘈杂环境/无障碍场景），我希望长按地图标记或列表卡片，弹出快捷修饰菜单（更便宜/更近/更安静/对比/有 wifi），实现无语音追问。

**Acceptance Criteria**:
- [ ] 在 `apps/ios/SoloCompass/Views/Map/` 相关 view 中为 experience marker / list card 添加 SwiftUI `.contextMenu { ... }`
- [ ] 菜单项：`[更便宜] [更近] [更安静] [对比这个] [有 wifi]`，每项配 SF Symbol 图标
- [ ] 点击任一项 → 触发 `onVoiceIntent(transcript: String)` callback，内容为对应的人类语句（如 "我要比这个更便宜的选择"）
- [ ] callback 最终走 `VoiceAgentSession.beginUserTurn(transcript:)`，与语音输入路径完全一致
- [ ] 文案走 `NSLocalizedString`，en + zh-Hans 资源
- [ ] 长按手势触发阈值 ≥ 0.5s
- [ ] 埋点：`voice_agent.shortcut_menu_opened{experience_id}`、`voice_agent.shortcut_menu_tapped{experience_id, action}` 上报
- [ ] Typecheck + 单测通过
- [ ] 在 Simulator 中验证视觉与交互

**工时**: 1.5d

---

### 阶段 W4: 收尾与发布（P1）

#### US-011: 撤销 / 重置按钮
**Description**: 作为用户，我希望在 ConversationSheet 标题栏有"撤销最后一步"和"重置"按钮，快速回退多轮追问的约束。

**Acceptance Criteria**:
- [ ] 在 `ConversationSheet.swift` 标题栏右侧添加两个 Image button：`arrow.uturn.backward.circle`（撤销）和 `arrow.counterclockwise.circle`（重置）
- [ ] 撤销 → 调 `session.removeConstraint(dimension: activeConstraints.last?.dimension)` 并触发 `beginUserTurn("撤销最后一个限制")`
- [ ] 重置 → 调 `session.clearConstraints()` 并触发 `beginUserTurn("重置所有限制")`
- [ ] 按钮在 `activeConstraints.isEmpty` 时禁用（灰色）
- [ ] 文案走 `NSLocalizedString`
- [ ] 埋点：`voice_agent.undo_tapped{constraint_count_before}`、`voice_agent.reset_tapped{constraint_count_before}` 上报
- [ ] Typecheck + 单测通过
- [ ] 在 Simulator 中验证

**工时**: 0.5d

---

#### US-012: 新增 `explain_recommendation` 工具
**Description**: 作为用户，我想说"为什么推这个"或"为什么推这个不推那个"，AI 应基于 solo score 分项 + confidence + risks 给出透明、可验证的理由。

**Acceptance Criteria**:
- [ ] 在 `VoiceAgentToolRouter` 新增 `explain_recommendation(experience_id, compare_against_id?)` 工具
- [ ] 返回结构：`{ok, experience_id, explanation: {solo_score_breakdown, data_freshness, risks}, comparison?: {vs_id, winner_by, detailed_diff}}`
- [ ] 若 `compare_against_id` 提供，附带 breakdown 维度差异（如 "+2.0 on safety, -1.5 on quietness"）
- [ ] System prompt 加规则："用户问'为什么'时必须用此工具，不可口头泛化"
- [ ] 单测：3 个场景（单解释 / 对比解释 / 不存在 ID）
- [ ] 埋点：`voice_agent.tool_call{name: "explain_recommendation", has_comparison}` 上报
- [ ] Typecheck + 单测通过

**工时**: 2d

---

#### US-013: 北极星指标 Dashboard 验证 + Token 预算审查
**Description**: 作为 PM，我需要 5 个北极星指标在 Analytics dashboard 可见，并确认新 system prompt + 富集字段没有撑爆 token 预算。

**Acceptance Criteria**:
- [ ] 在 `apps/ios/SoloCompass/Services/` 新建或扩展 `AnalyticsService.swift`，提供 `trackVoiceAgentSession(turnCount, toolCallCount, duration, endReason)` 方法
- [ ] 在 `VoiceAgentSession.finishSession()` 调用此方法
- [ ] 5 个指标的派生计算文档化（在 `docs/AI_AUDIT_2026Q2.md` 第 11.7 节追加 "派生公式" 子节）：
  - 平均追问深度 = `mean(turnCount where turnCount >= 2)`
  - 追问解决率 = `count(turn >= 2 AND followed_by_tool_call) / count(turn >= 2)`
  - 解引用准确率 = `count(reference_resolved.source != "asked_clarification") / count(reference_resolved)`
  - 不确定性诚实度 = `count(uncertainty_acknowledged) / count(uncertainty_should_acknowledge)`
  - 追问转化率 = `count(turn >= 2 AND followed_by_save_or_navigate_or_detail) / count(turn >= 2)`
- [ ] Token 预算审查脚本：跑 5 个典型会话（含富集字段注入），单次 sendAgentMessage 不超过 8000 input tokens（DeepSeek context 32K 安全余量）；超出则文档化裁剪策略
- [ ] 5 个指标的 baseline 值在审查报告中记录（first week 数据采集）
- [ ] 埋点 schema 文档化到 `docs/AI_AUDIT_2026Q2.md` 第 11.7 节
- [ ] Typecheck + 单测通过

**工时**: 1d

---

#### US-014: E2E 验证 5 个真实用户故事
**Description**: 作为 QA，我需要在 Simulator 中端到端跑通 5 个典型追问场景，确认无回归。

**Acceptance Criteria**:
- [ ] 场景 1: 用户找咖啡 → 问"安全吗"（触发 `query_attribute`） → 问"对比前两个"（触发 `compare_experiences`） → 收藏赢家
- [ ] 场景 2: 用户找餐厅 → 问"换个更便宜的"（触发 `find_alternative`） → 看 breadcrumb 出现 cost 约束 → 点 × 移除
- [ ] 场景 3: 用户问"第三个怎么样"（验证 `turnLog` 解引用） → AI 正确锁定
- [ ] 场景 4: 用户问一个数据缺失的属性（如 "wifi 速度多快"） → AI 调 `acknowledge_uncertainty` 而非编造
- [ ] 场景 5: 用户长按 marker → 点"更安静" → 与语音输入产生同样的对话流
- [ ] 每个场景的 dashboard 数据点同步验证（指标已上报）
- [ ] 文档化测试报告到 `tasks/prd-followup-experience-e2e-report.md`
- [ ] 无 P0/P1 缺陷

**工时**: 1d

---

## 4. Functional Requirements

### 数据可见性
- **FR-1**: `AIService.buildVisibleExperiencesContext()` 必须注入 top 10 visible experiences 的富集字段（见 US-001 字段清单）
- **FR-1.1**: 单次注入 token 预算硬上限 1500 tokens，超出时按 confidence level 降序裁剪
- **FR-1.2**: 每个 experience 的 `realInconveniences` 单条截断到 200 字符

### 新工具集（6 个）
- **FR-2**: 新增 `query_attribute(experience_id, attribute)` 工具，attribute ∈ 10 种枚举值，返回 `{answer, explanation, confidence_level}`
- **FR-3**: 新增 `acknowledge_uncertainty(topic, reason)` 工具，AI 必须在 confidence 不足时主动调用
- **FR-4**: 新增 `compare_experiences(experience_ids, dimension)` 工具，支持 2-5 个 experience 对比 7 种 dimension
- **FR-5**: 新增 `find_alternative(reference_id, change_type, max_distance_meters?)` 工具，change_type ∈ 8 种枚举值
- **FR-6**: 新增 `refine_filter(operation, dimension, value?)` 工具，operation ∈ {add, remove, replace}
- **FR-12**: 新增 `explain_recommendation(experience_id, compare_against_id?)` 工具

### System Prompt
- **FR-7**: System prompt 必须包含 6 段（中英双语）：解引用规则 / 比较输出格式 / 数据置信度规则 / 诚实度强制 / 反事实回答模板 / 禁止编造
- **FR-7.1**: System prompt 必须根据 `VoiceAgentSession.detectedLanguage` 在中英之间动态选择（沿用 `docs/AI_AUDIT_2026Q2.md` P1-8 设计）

### UI 组件（4 个）
- **FR-8**: ConversationSheet 必须在每条 assistant bubble 下方渲染最多 3 个建议追问芯片，路由规则见 US-005
- **FR-9**: ConversationSheet 必须在 messageList 顶部渲染 activeConstraints breadcrumb，点 × 移除并触发隐含 user turn
- **FR-10**: ConversationSheet 标题栏必须提供"撤销"和"重置"按钮，无约束时禁用
- **FR-11**: 地图 marker 与列表卡片必须支持 `.contextMenu` 快捷修饰菜单（5 个动作）

### 状态与引用
- **FR-13**: `VoiceAgentSession` 必须维护 `activeConstraints: [QueryConstraint]` 和 `turnLog: [Turn]` 两个新状态
- **FR-14**: `compactIfNeeded()` 不可丢失 turnLog（独立于 messages 压缩）
- **FR-15**: `beginUserTurn(transcript:)` 必须接收并记录当时的 visibleExperiencesSnapshot

### 埋点（5 个北极星 + 工具级）
- **FR-16**: 每个新工具调用必须上报 `voice_agent.tool_call{name, ...}` 事件
- **FR-17**: `VoiceAgentSession.finishSession()` 必须上报 `voice_agent.session_ended{turnCount, toolCallCount, duration, endReason}` 事件
- **FR-18**: UI 组件交互（chip tap / breadcrumb remove / shortcut menu / undo / reset）必须各自埋点
- **FR-19**: 不确定性派生指标必须埋两个事件：`uncertainty_should_acknowledge`（基线）和 `uncertainty_acknowledged`（实际）

---

## 5. Non-Goals (Out of Scope)

- **NG-1**: 不实现 Web bot（apps/bot）的追问能力（per 答案 2A，本 PRD 仅 iOS）
- **NG-2**: 不引入新的数据模型字段（如价格 tier、营业时间、设施详情）——cost 维度仅用 category 启发式
- **NG-3**: 不实现跨会话记忆（"昨天那家咖啡馆"）——超出 voice-agent.md L398 范围
- **NG-4**: 不实现 RAG / 向量检索 / 用户嵌入向量（属于审计第 8 节高阶架构，后续 PRD 处理）
- **NG-5**: 不实现多模态输入（拍照识别），不实现 TTS
- **NG-6**: 不实现 RLHF / Learning-to-Rank 等模型层优化
- **NG-7**: 不修改 `docs/AI_AUDIT_2026Q2.md` 第 1-10 章的 P0/P1 改进项（如时间上下文 P0-1、Voice Agent 配额 P0-2），这些是并行独立 PRD
- **NG-8**: 不引入新的第三方依赖（保持 `apps/ios` 零第三方依赖原则）
- **NG-9**: 不修改 `packages/core/src/experience.ts` schema（如有 schema 改动需走 `pnpm parity:check` 流程并独立 PRD）

---

## 6. Design Considerations

### UI 复用
- 建议追问芯片复用现有 Capsule 样式（与 category filter chip 一致）
- Breadcrumb 芯片复用同样 Capsule 但带 `xmark.circle.fill` 后缀
- 长按 `.contextMenu` 使用 SwiftUI 原生（无需自建）
- 撤销/重置按钮用 SF Symbol（`arrow.uturn.backward.circle` + `arrow.counterclockwise.circle`）

### 本地化
- 所有用户可见文案（chip 文案、breadcrumb dimension 名、shortcut menu 项、undo/reset toast）走 `NSLocalizedString`
- 中英两份资源同步更新：`Resources/en.lproj/Localizable.strings` + `Resources/zh-Hans.lproj/Localizable.strings`

### Token 预算
- 富集字段注入 + 新 system prompt 会使 input tokens 上升预估 ~30%
- US-013 必须验证单次 sendAgentMessage 不超过 8000 input tokens

---

## 7. Technical Considerations

### 依赖与集成点
- **依赖 AIService.swift**: `serializeAgentMessages` 和 `sendAgentMessage` 路径
- **依赖 VoiceAgentSession.swift**: messages、state machine、compactIfNeeded
- **依赖 VoiceAgentToolRouter.swift**: allTools 注册 + execute dispatch
- **依赖 MapViewModel.swift**: visibleExperiences source of truth + selectCategory/dismissFromVisible
- **依赖 ConversationSheet.swift**: 主要 UI 渲染
- **新增依赖**: AnalyticsService.swift（如不存在则创建）

### 与第 1-10 章改进的并行关系
- 本 PRD 与第 1-10 章 P0/P1 改进**正交**，不互相阻塞
- 推荐顺序：P0-1（时间上下文，2h）+ P0-2（配额分离，4h）先做完，再启动本 PRD W1，token 预算更稳

### 性能要求
- 单次 sendAgentMessage 端到端延迟 < 5s（含工具执行）
- UI 状态更新无可感知卡顿（@MainActor + Observable）
- Token 预算监控见 FR-1.1 + US-013

### 测试
- 单测覆盖每个新工具的核心路径（每工具 ≥ 3 个 case）
- E2E 5 个场景（US-014）
- 类型与构建：每个 US 必须 `xcodebuild build` + `xcodebuild test` 通过

---

## 8. Success Metrics

| 指标 | 基线（预估） | 目标值 | 测量窗口 |
|------|------------|-------|---------|
| 平均追问深度 | ~1.2 轮 | ≥ 3.5 轮 | 上线后 2 周 |
| 追问解决率 | < 20% | ≥ 65% | 上线后 2 周 |
| 解引用准确率 | 不可测 | ≥ 85% | 上线后 4 周（需 ≥ 100 个引用样本） |
| 不确定性诚实度 | < 10% | ≥ 70% | 上线后 2 周 |
| 追问转化率 | < 15% | ≥ 50% | 上线后 4 周 |

**附加成功标准**:
- 8 类追问意图中至少 6 类可用（属性 / 对比 / 替代 / 解释 / 修正 / 元 必须；细节 / 场景 可后续 PRD）
- Token 预算未爆（单次 ≤ 8000 input tokens）
- 无 P0/P1 缺陷
- iOS 端 zero 第三方依赖原则保持

---

## 9. Open Questions

1. **冲突解决**：用户长按"更便宜"快捷修饰时，若 visibleExperiences 中无更便宜的候选，UI 该如何反馈？toast / 静默 / AI 主动说明？
2. **多轮约束的优先级**：用户先后说"安静的"和"热闹的"应当后者覆盖前者，还是反问澄清？默认行为待定（建议先做覆盖，后续根据数据调整）
3. **AnalyticsService 后端**：埋点上报到哪个数据汇？PostHog（与 Web cost-tracker 一致）/ Supabase / 本地 SwiftData？US-013 验证时需明确（建议默认 PostHog 复用）
4. **场景追问意图（#6）**：是否本 sprint 实现 `evaluate_scenario` 工具？当前 PRD 未含。若纳入需增加约 2d。
5. **细节追问意图（#5）**：依赖 schema 字段（地铁、设施详情），本 PRD 不解决，留待数据模型扩展 PRD。
6. **Voice Agent 配额（P0-2）**：本 PRD 工具调用增加约 2-3x，是否会撑爆 PRD 第 1-10 章的 P0-2 独立配额？需在 P0-2 落地后回测。
7. **解引用反问的体验设计**：AI 反问 "你是指 X 吗？" 时，用户如何快捷确认？是否需要 UI 层"是/否"快捷按钮？
