# PRD: Companion v2 — 从工具到伙伴(可信 × 懂你)

**Status:** Draft · **Date:** 2026-06-05 · **Owner:** Xinwei
**Source RFCs:** [`docs/architecture/data-source-quality.md`](../docs/architecture/data-source-quality.md) · [`docs/architecture/agent-memory-context.md`](../docs/architecture/agent-memory-context.md)
**Theme:** 从"可用"到"好用" —— 让 Solo Compass 从"陌生人给陌生地方做泛泛推荐"变成"懂你的人,给你可信的地方,做贴心的推荐"。

---

## 1. Introduction / Overview

Solo Compass 目前是一个**功能可用但缺乏温度与信任**的旅行助手:它有真实的 agent 工具循环、有多源数据接入、有 solo-score 评分体系。但两条暗线拖累了"好用":

- **不可信**:AI 在数据缺失时硬编码占位符("营业到 21 点"、"7.8 分"、solo 友好度六维度几乎全靠猜),用户分不清哪条是真数据、哪条是 AI 编的。一套写好的高质量数据源框架(`packages/sources`)**从未通电**。
- **不懂你**:agent 跑在"健忘症"上——会话一关全忘,从不从用户的去过/收藏/反馈里学习。丰富的用户信号(`MicroSurveyRecord` 等)**全是孤岛**,一个都没喂给 agent。

**Companion v2 把这两条线整合成一个产品叙事**:`MicroSurveyRecord` 这批用户信号是支点——它既喂"懂你"(用户画像),又喂"可信"(真实 solo 评分)。本版本同时为 **L5 语义记忆**(pgvector)提前铺路,使后续个性化检索成为可能。

**用户能直接看见的四件事(本版本的脸面):**

1. **可信度透明徽章** —— 一眼看出"AI 推测 / 多源印证 / 用户验证"。
2. **"懂你"的个性化推荐语** —— "你上次喜欢那家安静咖啡馆,这家同样适合一个人"。
3. **记得上次的对话** —— 语音 agent 关掉重开,接着上次聊。
4. **真实营业状态 / 数据补齐** —— 营业时间、评分从占位符变真实数据。

---

## 2. Goals

- **G1（可信）** 数据源框架通电:OSM → Wikivoyage → Google Places 真实落库,关键字段"真实填充率"(非占位符)显著上升。
- **G2（可信）** 诚实降级:AI 缺数据时标记 `null` 并显式标"未验证",不再编造;置信度对用户透明可读。
- **G3（懂你）** agent 拥有跨会话记忆 + 用户画像 + 每轮新鲜上下文;推荐语个性化。
- **G4（支点）** 用户行为信号(completion/favorite/survey)回流,既驱动画像,也覆盖 AI 猜测的 solo-score。
- **G5（铺路）** 为 L5 语义记忆铺设数据与接口地基(embedding 入口、用户信号聚合层),本版本不交付完整 RAG 检索 UI。
- **G6（纪律）** 全程可灰度、可降级、TS↔Swift schema parity 不破。

**北极星指标:** 用户对推荐的信任度与"被理解感"同步提升(见 §8 Success Metrics)。

---

## 3. User Stories

> 分五个 Epic。**Epic A/B = 可信线**,**Epic C/D = 懂你线**,**Epic E = 支点(连接两线)**,**Epic F = L5 铺路**。
> 每个 US 控制在一个聚焦会话内可实现。UI story 标注 Simulator 验证(本项目 iOS UI 用 Simulator,非 dev-browser)。

### Epic A — 数据源通电(可信·后端/TS)

#### US-A1: 编译 pipeline 骨架跑通(仅 OSM)

**Description:** 作为开发者,我需要一条真实 pipeline 调用 `getActiveAdapters → OsmAdapter.fetch → 落库`,以证明框架可通电。

**Acceptance Criteria:**

- [ ] 新增 `scripts/compile-experiences.ts`,以 `cityCode` 为入参调用 `getActiveAdapters`
- [ ] 仅启用 OSM adapter,`fetch({ cityCode, maxResults })` 返回 `Candidate[]`
- [ ] Candidate 经 `structureExperience` 结构化后 upsert 到 Supabase(复用 `seed-load` upsert 逻辑)
- [ ] 提供 `--dry-run` 模式:只打印不落库
- [ ] `pnpm typecheck` + `pnpm test` 通过

#### US-A2: 接入 Wikivoyage 指南源 + attribution

**Description:** 作为用户,我希望体验描述基于真实旅游指南而非纯 AI 想象,以获得更可信的内容。

**Acceptance Criteria:**

- [ ] pipeline 启用 `WikivoyageAdapter`,其 `rawText` 进入 `structureExperience`
- [ ] `sourceName` + `fetchedAt` 写入 `Experience.sources`(attribution 链)
- [ ] 多源命中同一地点时,`sources` 数组累计(为多源印证铺路)
- [ ] 单测:mock Wikivoyage `fetch`,断言 attribution 正确写入
- [ ] `pnpm typecheck` 通过

#### US-A3: 接入 Google Places + 预算控制

**Description:** 作为用户,我希望看到真实评分和营业时间,以判断"现在能不能去、值不值得去"。

**Acceptance Criteria:**

- [ ] pipeline 启用 `GooglePlacesAdapter`,绑定 `BudgetTracker`(`GOOGLE_PLACES_DAILY_CAP_USD`)
- [ ] 超预算时 adapter 静默跳过且记录日志,pipeline 不崩
- [ ] `BudgetTracker` 跨多次脚本运行可持久化预算计数(解决 in-process 重启清零,见开放问题)
- [ ] 集成测:dry-run 断言不超预算
- [ ] `pnpm typecheck` 通过

#### US-A4: 扩展 Candidate 携带结构化信号 + 来源元信息

**Description:** 作为开发者,我需要 `Candidate` 能携带 rating/hours/sampleSize/sourceWeight,以便后续质量加权融合与诚实降级。

**Acceptance Criteria:**

- [ ] `Candidate` 增加可选 `sourceWeight` 与 `signals { rating?, ratingCount?, priceLevel?, openingHours?, liveStatus? }`
- [ ] Google Places adapter 填充 `signals`;OSM/Wikivoyage 留空(向后兼容)
- [ ] 若需改 `structureExperience` 签名,保持旧调用兼容(可选参数)
- [ ] 若触碰 `packages/core/experience.ts` 的 sources 字段 → `pnpm parity:check` 通过
- [ ] `pnpm typecheck` + `pnpm test` 通过

### Epic B — 诚实降级 & 信任透明(可信·iOS UI)

#### US-B1: AI 缺数据不再编造占位符

**Description:** 作为用户,我不希望被假装的"营业到 21 点"误导,缺数据时应如实标注。

**Acceptance Criteria:**

- [ ] 移除/改造 AI 合成 prompt 中的硬编码降级(`"9-21"`、`7.0-8.0`):无真实信号时对应字段输出 `null`
- [ ] solo-score 六维度:无真实数据来源的维度标记为"基于 AI 推测",不伪装成已验证
- [ ] 单测:构造"仅 OSM、无信号"的输入,断言 hours/rating 为 null 而非占位符
- [ ] iOS `xcodebuild build` 通过

#### US-B2: 可信度透明徽章(用户可见 #1)

**Description:** 作为用户,我想一眼看出一条数据是"AI 推测、多源印证、还是用户验证过的",以决定信任程度。

**Acceptance Criteria:**

- [ ] 体验卡片显示可读徽章,映射 `confidence.level`(0–5)+ `HealthStatus`(healthy/fading/questioned/may_be_gone)
- [ ] 徽章用人话表达三档:🤖 AI 推测 / ✅ 多源印证 / 👤 用户验证(而非裸 `L1`)
- [ ] 点击徽章展开详情:信号来源、样本量、最近验证时间
- [ ] 缺数据字段在卡片上显示"未验证"而非空白或假值
- [ ] 复用 `packages/core/confidence.ts` 的 `healthFromConfidence`,不新造评级逻辑
- [ ] iOS `xcodebuild build` 通过 + Simulator 视觉验证(`#Preview` 不足)

#### US-B3: 真实营业状态展示(用户可见 #4)

**Description:** 作为用户,我想知道一个地方"现在开着吗",以避免白跑一趟。

**Acceptance Criteria:**

- [ ] 卡片展示来自编译腿的真实营业时间(来源 Google Places),无数据时显示"营业时间未知"
- [ ] 若有 `liveStatus`,显示"营业中 / 已打烊"状态点
- [ ] 数据来源标注(来自 Google Places / OSM),与 US-B2 徽章一致
- [ ] iOS `xcodebuild build` 通过 + Simulator 视觉验证

### Epic C — Agent 记忆地基(懂你·iOS)

#### US-C1: 每轮刷新实时上下文(L1)

**Description:** 作为用户,我在对话中走动或过了一段时间后,agent 应基于我"当下"的位置和时间回应,而非开场快照。

**Acceptance Criteria:**

- [ ] `VoiceAgentOrchestrator` 每轮模型调用前注入/更新一条 `LIVE CONTEXT` system 消息(location/localTime/viewportBBox)
- [ ] 该消息每轮覆盖、不计入 `messagesMaxCount`、不堆积
- [ ] system prompt 中的静态 `CONTEXT SNAPSHOT` 退化为只放不变信息
- [ ] 单测:会话中改变 location/time,断言下一轮 LIVE CONTEXT 反映新值
- [ ] iOS `xcodebuild build` + XCTest 通过

#### US-C2: 压缩改结构化事实抽取(L1)

**Description:** 作为用户,我提过的关键约束("膝盖不好不能走远")不该在长对话里被丢掉。

**Acceptance Criteria:**

- [ ] `VoiceAgentSession.compactIfNeeded` 改为抽取 `SessionFacts`(约束类事实),而非朴素截断
- [ ] 抽取用规则/关键词,零额外 LLM 调用
- [ ] 单测:11+ 条消息触发压缩后,断言关键约束仍保留在 SessionFacts
- [ ] iOS `xcodebuild build` + XCTest 通过

#### US-C3: 跨会话对话恢复(L2 · 用户可见 #3)

**Description:** 作为用户,我关掉语音对话再打开时,希望它记得我们上次聊到哪。

**Acceptance Criteria:**

- [ ] 新增 `@Model AgentMessageRecord { conversationId, role, content, toolCallsJSON?, createdAt }`
- [ ] 会话 key = `scopedExperience?.id ?? "global"`,global 与 per-card chat 各自独立线程
- [ ] 新增 `Services/Memory/ConversationStore.swift` 负责读写/恢复
- [ ] 恢复时:最近 N 条原样恢复,更旧轮用 SessionFacts 摘要成一条 system 消息
- [ ] 单测:写入会话 → 重建 store → 断言最近 N 条恢复、旧轮被摘要
- [ ] Simulator 验证:关闭 sheet 重开,agent 引用上次内容

### Epic D — 用户画像与个性化(懂你·iOS)

#### US-D1: UserProfileService 合成用户画像(L3)

**Description:** 作为开发者,我需要把孤岛行为数据聚合成一段可注入的用户画像。

**Acceptance Criteria:**

- [ ] 新增 `Services/Memory/UserProfileService.swift`(`@MainActor`,纯本地)
- [ ] `snapshot()` 聚合 `UserCompletionRecord` / `UserFavoriteRecord` / `MicroSurveyRecord`,category 由 experienceId 反查
- [ ] `renderForPrompt()` 产出 ≤300 tokens 的紧凑画像;无记录返回 `nil`
- [ ] 单测:构造 fixtures 断言画像内容;空数据返回 nil
- [ ] iOS `xcodebuild build` + XCTest 通过

#### US-D2: 画像注入 system prompt

**Description:** 作为用户,我希望 agent 知道我的长期偏好,而不必每次重新解释。

**Acceptance Criteria:**

- [ ] `buildSystemPrompt` 在 `CONTEXT SNAPSHOT` 后追加 `TRAVELER PROFILE` 区块(来自 US-D1)
- [ ] 画像**不含坐标**(沿用现有约定)
- [ ] 画像为 nil 时 prompt 完全退回当前行为(零风险降级)
- [ ] iOS `xcodebuild build` 通过

#### US-D3: "懂你"的个性化推荐语(用户可见 #2)

**Description:** 作为用户,我希望推荐理由是针对我的("你上次喜欢安静咖啡馆"),而非泛泛的好评。

**Acceptance Criteria:**

- [ ] 排序/推荐文案在画像存在时,引用用户历史偏好生成个性化一句话
- [ ] 新用户(无画像)回退到当前通用推荐语,无突兀空引用
- [ ] 文案口吻遵循现有"calm/factual、无 amazing/感叹号"约定
- [ ] Simulator 验证:有历史的账号看到个性化推荐语

### Epic E — 用户信号回流(支点·连接两线)

#### US-E1: 共享"用户信号聚合"组件

**Description:** 作为开发者,我需要一个被画像(懂你)和 solo-score(可信)共用的信号聚合层,避免两套重复读 SwiftData。

**Acceptance Criteria:**

- [ ] `UserProfileService` 暴露可复用的聚合结果(comfort/pressure 均值、completion 计数、disliked 品类)
- [ ] solo-score 覆盖逻辑与画像逻辑消费同一聚合,不各读各的
- [ ] 单测:同一组 fixtures 同时驱动两条消费,结果一致
- [ ] `pnpm parity:check` 通过(若涉及 core soloScore 字段)

#### US-E2: 用户验证覆盖 AI 的 solo-score

**Description:** 作为用户,我和其他独行者的真实反馈应该比 AI 猜测更权威。

**Acceptance Criteria:**

- [ ] 当某体验的 `MicroSurveyRecord` 样本量达到阈值(PRD v2 定义,如 ≥5)时,用户聚合 solo-score 覆盖 AI solo-score
- [ ] 覆盖后 `confidence.level` 相应提升(用户验证层),徽章(US-B2)随之变"👤 用户验证"
- [ ] 样本不足时保留 AI 评分并标"AI 推测"
- [ ] 单测:跨阈值前后断言评分来源切换 + confidence 提升

#### US-E3: 行为反推偏好建议(L4,不静默覆盖)

**Description:** 作为用户,系统发现我常去某类地方时,应建议我更新偏好,而不是偷偷改我的设置。

**Acceptance Criteria:**

- [ ] `UserProfileService` 计算 inferred(行为)vs declared(自报)偏好偏差
- [ ] 偏差显著时,在 UI 给出**建议**("发现你常去咖啡馆,加入偏好?"),用户确认才生效
- [ ] 绝不静默覆盖 `UserPreferences` 手设值
- [ ] 提供隐私开关(默认开,可关),关闭后不做行为推断
- [ ] Simulator 验证:模拟多次 completion 后出现建议入口

### Epic F — L5 语义记忆铺路(本版本只铺地基)

#### US-F1: 用户信号 embedding 入口(铺路,不交付检索 UI)

**Description:** 作为开发者,我需要为将来 pgvector 语义检索预留 embedding 生成与存储入口。

**Acceptance Criteria:**

- [ ] 定义 embedding 数据契约:对 completed/favorited experience 与画像 snapshot 生成可选 embedding 字段(后端侧)
- [ ] `UserProfileService.snapshot()` 输出作为 embedding 输入源(接口对齐,不实现实际检索)
- [ ] 文档化:`docs/architecture/` 注明 L5 接口契约与本版本边界
- [ ] 仅铺设接口与数据列,**不交付**用户可见的语义检索功能
- [ ] `pnpm typecheck` 通过

---

## 4. Functional Requirements

**可信线**

- FR-1: 系统必须提供 `scripts/compile-experiences.ts`,通过 `getActiveAdapters` 调用 OSM/Wikivoyage/Google Places adapter 并落库。
- FR-2: Google Places 调用必须受 `BudgetTracker` 约束,超预算静默跳过且可跨运行持久化预算计数。
- FR-3: `Candidate` 必须支持携带 `sourceWeight` 与结构化 `signals`(rating/ratingCount/priceLevel/openingHours/liveStatus)。
- FR-4: 每条 Experience 必须记录 attribution(来源名 + 抓取时间)进 `sources`。
- FR-5: AI 合成在缺真实信号时必须输出 `null`,禁止硬编码占位符(营业时间/评分/solo 维度)。
- FR-6: 体验卡片必须展示可读的可信度徽章,三档区分 AI 推测 / 多源印证 / 用户验证,基于 `confidence.level` + `healthFromConfidence`。
- FR-7: 卡片必须展示真实营业状态;无数据显示"未知"而非假值。

**懂你线**

- FR-8: agent 每轮模型调用前必须注入新鲜的 `LIVE CONTEXT`(location/time/viewport),不计入消息上限。
- FR-9: 会话压缩必须抽取并保留约束类 `SessionFacts`,而非朴素截断。
- FR-10: 系统必须持久化 agent 对话(`AgentMessageRecord`),并在重开同 scope 会话时恢复(旧轮摘要、近 N 条原样)。
- FR-11: 系统必须合成用户画像(`UserProfileService`)并注入 system prompt;无数据时安全降级为 nil。
- FR-12: 推荐文案在有画像时必须个性化,无画像时回退通用文案。

**支点 & 铺路**

- FR-13: 画像与 solo-score 覆盖必须共用同一用户信号聚合层。
- FR-14: 当用户验证样本达阈值时,用户聚合 solo-score 必须覆盖 AI solo-score 并提升 confidence。
- FR-15: 行为反推偏好必须以"建议"形式呈现,绝不静默覆盖用户手设值,且受隐私开关控制。
- FR-16: 系统必须为 L5 预留 embedding 接口与数据契约,本版本不交付语义检索 UI。

---

## 5. Non-Goals (Out of Scope)

- **NG-1** 不交付完整 L5 语义检索/RAG 的**用户可见功能**(仅铺接口与数据地基)。
- **NG-2** 不做 memory 的后端多设备漫游同步(本版本 memory 仍本地优先;仅 L5 embedding 涉及后端)。
- **NG-3** 不接入真实图片 / 外部评论 UGC 源(Foursquare Tips 等)——未来版本。
- **NG-4** 不改造 `AgentRouter` 的拓扑(条件边/回环)——另立 RFC。
- **NG-5** 不做模型微调 / 个性化训练。
- **NG-6** 不让 iOS 运行时直连 Google Places(成本控制,走编译腿进库)。
- **NG-7** 不强制统一 TS 框架与 iOS 运行时为单一代码(双轨分工,见 RFC §5)。

---

## 6. Design Considerations

- **可信度徽章**:复用现有 `ConfidenceBadge.swift`,把裸 `L{level}` 升级为人话三档 + 详情弹窗;颜色沿用 health 状态(🟢🟡🔴⚫)。
- **个性化推荐语**:口吻遵循现有 rank prompt 的"calm/factual"约定,禁 amazing/感叹号。
- **跨会话恢复 UI**:重开 sheet 时恢复消息流,顶部可有"继续上次对话"轻提示。
- **行为建议入口**:轻量、非打扰(如 Settings 或 explore 后一次性卡片),用户主动确认。
- **复用既有组件**:`ContextManager`、`confidence.ts`、`EnrichmentAgent` dedup、`seed-load` upsert、`FeatureFlags` 灰度。

---

## 7. Technical Considerations

- **TS↔Swift parity**:任何触碰 `packages/core`(experience/confidence/solo-score)的改动必须 `pnpm parity:check` 双向通过。
- **双数据哲学调和**:`Candidate.rawText`(走 AI 解析)与 `Candidate.signals`(结构化直用)并存(RFC §1.3/§3.3)。
- **灰度**:可信线用 `SOURCES_ENABLED` 名单 + `getActiveAdapters` 的 `enabled`;懂你线沿用 iOS `FeatureFlags`。
- **降级链**:每层独立可降级——无画像→nil;ContextManager 失败→静态 prompt;ConversationStore 失败→单会话;超预算→跳过。
- **成本**:L1/L3 聚合零额外 LLM 调用;编译腿可用便宜模型批处理,不挤占用户端 30/天合成配额。
- **隐私**:memory 本地优先,画像注入不含坐标;L4 行为推断有隐私开关;L5 embedding 上后端需评估 anon 身份复用(`MicroSurveyRecord.anonDeviceId`)。
- **目标城市**:编译腿初始覆盖现有 seed 城市(VTE、CMI/cmi),后续扩展来源见开放问题。

---

## 8. Success Metrics

**可信(信任度)**

- 关键字段(营业时间/评分)"真实填充率"(非占位符占比)较通电前显著上升(目标:核心城市 ≥70%)。
- 带"多源印证 / 用户验证"徽章的体验占比上升。
- 用户对"营业状态准确性"的负反馈下降。

**懂你(被理解感)**

- 老用户(有画像)看到个性化推荐语的会话占比 ≥ 目标值。
- 跨会话对话恢复成功率(重开后正确恢复上下文)≥ 95%。
- 长对话中关键约束保留率(SessionFacts 命中)≥ 目标值。

**支点**

- 达验证阈值后由用户 solo-score 覆盖 AI 的体验数量稳定增长。
- 行为偏好建议的用户接受率(衡量推断质量)。

**北极星**:信任度与被理解感**同步**提升,而非此消彼长。

---

## 9. Open Questions

1. 编译腿目标城市清单的权威来源?复用 `DiscoveredCityRecord` 还是单独配置?(当前 seed 仅 VTE/CMI)
2. `BudgetTracker` 跨运行持久化用什么存储?(`budget.ts` 注释提示 production 需持久化)
3. solo-score 用户覆盖阈值定多少?(PRD v2 提及 ≥5,需确认)
4. 画像注入 token 上限真机量后定值?(初定 ≤300)
5. L5 embedding 上后端时是否复用 `MicroSurveyRecord.anonDeviceId` 作为用户身份?隐私影响?
6. L2 跨会话恢复的"近 N 条"N 取多少?与 `messagesMaxCount=11` 如何协调?
7. Epic 间依赖:Epic B(诚实降级 UI)依赖 Epic A(真实数据落库)到什么程度才能验证?是否需要先有最小真实数据集?
