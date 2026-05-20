# PRD: Solo Compass 体验与架构演进 v1（UI 重构 + AI 深度赋能 + Roadmap）

> **版本**: v1.0
> **创建日期**: 2026-05-20
> **作者**: Solo Compass Product Team
> **状态**: Draft — 等待 Eng Review
> **目标交付窗口**: 12 周（分 3 个 Phase）

---

## 1. Introduction / Overview

Solo Compass 当前已具备「地图为家」的核心骨架（`CompassMapView` + `ExperienceDetailView` + `VoiceAgentOrchestrator`），但在三个层面存在明显的「未完成感」：

1. **UI/UX 视觉与交互层**：顶部筛选栏占用纵向视野、Bottom Sheet 暴露占位文案与硬编码评分、Chat Overlay 出现未本地化键值、City Picker 出现多语言重复项——这些细节让产品距离「Apple-grade 数字游民工具」的定位有可感知差距。
2. **AI 智能层**：当前 `VoiceAgentOrchestrator` 仅基于文本 prompt + 基础定位，未充分利用「地图视野 POI + 用户偏好 + 时间/天气」的多模态上下文；评分依赖 OSM 标签推断，缺少真实评论支撑；单一 LLM 调用承担意图识别、数据查询、内容生成三种职责，难以独立优化。
3. **延展能力层**：缺乏「离开地点之后」的体验闭环（PKM 笔记导出）、缺乏面向 hacker/极简审美人群的主题化能力、缺乏弱网/离线场景下的可用性兜底。

本 PRD 将以「**第一性原理 + 工程化交付**」的方式，把上述三层重构为可分阶段实施的里程碑。

---

## 2. Goals

### 2.1 业务目标
- **G1**：将 App Store 评分从当前基线提升 ≥ 0.4 颗星（基于"视觉质感"和"AI 帮助度"两个用户评论关键词频次）
- **G2**：Chat Overlay 的会话完成率（用户发起 → 收到有意义回复 → 不立即关闭）从基线提升 ≥ 25%
- **G3**：数字游民核心用户（Remote Worker 偏好）日活留存（D7）提升 ≥ 15%

### 2.2 技术目标
- **G4**：消除所有用户可见的未本地化字符串、占位文案、硬编码评分
- **G5**：建立 `ContextManager` 协议，让 LLM 输入从「文本 prompt」升级为「结构化多模态上下文」
- **G6**：建立后端 RAG 数据管道，让独行评分从「OSM 标签推断」升级为「真实评论 + LLM 抽取」
- **G7**：将 `VoiceAgentOrchestrator` 拆分为三个职责清晰的 Agent（Intent / Query / Guide）

### 2.3 体验目标
- **G8**：所有交互动画达到 60 FPS（地图缩放、Bottom Sheet 拖拽、FAB 弹簧动效）
- **G9**：Chat 首字延迟（TTFB）< 800ms（流式响应）
- **G10**：所有 P0 视觉细节通过「Apple HIG + 数字游民审美」专家评审

---

## 3. User Stories

> 共 18 个故事，跨 3 个 Phase。每个故事可在 1-2 个开发会话内独立交付。

### Phase 1：UI/UX 重构（Week 1-4）

#### US-001：顶部筛选栏改为悬浮胶囊 + 滚动收起
**Description**: 作为一名地图浏览者，我希望顶部筛选栏不要永久占据屏幕纵向空间，让我能更专注于地图本身。

**Acceptance Criteria**:
- [ ] `FilterBarView` 从全宽工具栏改为悬浮胶囊样式（`Capsule` + `.regularMaterial`）
- [ ] 向下滑动地图时筛选栏自动半透明 + 收起（基于 `MapCameraPosition` 变化监听）
- [ ] 向上滑动或点击地图空白处恢复完整可见
- [ ] 收起/展开过程使用 `.spring(response: 0.35, dampingFraction: 0.8)`
- [ ] Typecheck (`xcodebuild build`) 通过
- [ ] 在 iPhone 16 Pro Simulator 上手动验证：地图视野提升 ≥ 60pt

#### US-002：地图主界面引入毛玻璃质感与触觉反馈
**Description**: 作为对视觉敏感的用户，我希望地图覆盖层（FAB / 标签芯片）有 Apple-grade 的玻璃拟态质感与微交互。

**Acceptance Criteria**:
- [ ] 所有悬浮按钮使用 `.regularMaterial` 背景 + `.shadow(.drop)` 阴影
- [ ] FAB 点击时触发 `UIImpactFeedbackGenerator(style: .soft)` 触觉反馈
- [ ] 按钮按下使用 `.scaleEffect(0.92).animation(.spring(...))` 弹簧动效
- [ ] 选中 POI 时地图相机偏移确保 Bottom Sheet 不遮挡 Pin（偏移量 = `sheetHeight * 0.4`）
- [ ] Typecheck 通过
- [ ] Simulator 验证视觉一致性

#### US-003：Bottom Sheet 引入骨架屏避免占位文案
**Description**: 作为用户，我不希望看到"我们还没有这个地方的精选故事..."这种暴露未完成感的文案。

**Acceptance Criteria**:
- [ ] 新增 `SkeletonView` 组件（共享于 `Views/Shared/`），支持 `redacted(reason: .placeholder)` 与 `shimmer` 动效
- [ ] `ExperienceDetailView` 的「为什么值得」模块：有故事则渲染，无故事则**不显示该 Section**（不再显示占位文案）
- [ ] 数据加载中状态使用骨架屏（3 行文本占位 + shimmer）
- [ ] Typecheck + `pnpm parity:check` 通过
- [ ] Simulator 验证：进入一个无故事的 POI，不应看到任何"还没有"文案

#### US-004：独行评分改为雷达图 + 真实差异化数据
**Description**: 作为用户，我希望独行评分能反映不同维度的真实差异，而不是清一色 7.0。

**Acceptance Criteria**:
- [ ] 新增 `SoloScoreRadarChart` 组件（5-6 个维度：座位友好 / 员工不打扰 / Wi-Fi / 噪音 / 安全 / 灯光）
- [ ] 当 `solo_score` 各维度差异 < 0.5 时退化为水平进度条 + 高亮 top-1（避免雷达图视觉欺骗）
- [ ] 评分数据源切换：优先使用后端 RAG 抽取（详见 Phase 2），fallback 到 `packages/core/src/solo-score.ts` 计算
- [ ] 至少 3 个种子 POI 数据需具备差异化评分（≥ 1.5 维度差）
- [ ] Typecheck 通过
- [ ] Simulator 验证雷达图渲染正确

#### US-005：导航按钮视觉优化 + 比例平衡
**Description**: 作为用户，我希望导航按钮（主操作）和复制按钮（次操作）的视觉权重符合 iOS HIG。

**Acceptance Criteria**:
- [ ] 导航按钮：使用 `LinearGradient` 强调色（`accentColor → accentColor.opacity(0.85)`）+ SF Symbol `arrow.triangle.turn.up.right.diamond.fill`
- [ ] 复制按钮缩小为 ghost button（仅图标 `doc.on.doc`，无背景填充）
- [ ] 两按钮高度统一为 44pt（满足 iOS HIG 最小可点击区域）
- [ ] Typecheck 通过

#### US-006：Chat Overlay 状态机重构
**Description**: 作为开发者和用户，我希望 Chat 模块有清晰的状态边界，避免"AI 功能尚未配置" 和 `chat.error.retry` 这类硬编码字符串直接暴露给用户。

**Acceptance Criteria**:
- [ ] 定义 `ChatUIState` 枚举：`.idle / .listening / .processing / .responding(stream) / .error(ChatError) / .unconfigured`
- [ ] 每个状态对应一个 `ViewModifier`，统一处理背景、动画、文案
- [ ] `.unconfigured` 状态显示友好引导卡片（"配置 Anthropic API Key 启用 AI 向导"）+ Settings 跳转
- [ ] `.error` 状态显示重试按钮 + 错误类型分类（网络 / API / 权限）
- [ ] Typecheck 通过
- [ ] Simulator 验证：手动清空 `Secrets.plist` 中的 API Key，UI 显示引导而非裸键值

#### US-007：Chat 本地化字符串全量修复
**Description**: 作为非英语用户，我不应该在 UI 中看到 `chat.title`、`chat.voice.idle` 这类未翻译的键值。

**Acceptance Criteria**:
- [ ] 全仓搜索 `chat\.[a-z]+\.[a-z]+` 模式，确认所有键值在 `Resources/en.lproj/Localizable.strings` 有定义
- [ ] 中文（zh-Hans）、日文（ja）翻译同步补全
- [ ] 增加 CI 检查脚本 `scripts/check-localization.ts`：扫描代码中 `NSLocalizedString` 调用与 strings 文件是否一致
- [ ] Typecheck + 新 CI 通过

#### US-008：语音输入背景波纹动效（Siri-like）
**Description**: 作为语音用户，我希望语音输入时有可视化反馈，让我知道系统正在听。

**Acceptance Criteria**:
- [ ] 新增 `VoiceWaveformView`，订阅 `AVAudioEngine.installTap` 的音量数据
- [ ] 使用 `Canvas` + `TimelineView(.animation)` 渲染 3 层渐变波纹
- [ ] 波纹振幅与音量线性映射（归一化 0-1 → 振幅 0-40pt）
- [ ] 性能：60 FPS @ iPhone 12 及以上
- [ ] Typecheck 通过
- [ ] Simulator 验证（外接麦克风或语音模拟）

#### US-009：City Picker 数据去重 + 双语显示
**Description**: 作为用户，我不应该在城市列表中看到同一个城市的三个不同语言版本（Vientiane / ນະຄອນຫຼວງວຽງຈັນ / 万象）。

**Acceptance Criteria**:
- [ ] `CityPickerSheet` 数据源按 `geonameId` 聚合去重
- [ ] 显示格式：`{本地语言名} {系统语言名}`（例：`万象 Vientiane`、`Tokyo 東京`）
- [ ] 排序：先按当前定位距离，后按字母序
- [ ] 数据清洗脚本：`scripts/dedupe-cities.ts` 处理 `packages/data` 中的 seed
- [ ] Typecheck + `pnpm parity:check` 通过
- [ ] Simulator 验证：搜索"Vientiane"只出现 1 条结果

#### US-010：Preferences 升级 InsetGrouped 样式
**Description**: 作为用户，我希望设置页有 iOS 原生系统级的质感。

**Acceptance Criteria**:
- [ ] 所有 Preferences 列表使用 `.listStyle(.insetGrouped)`
- [ ] 每个 Row 左侧增加圆角填充图标（如 Apple Settings 风格）
- [ ] Section Header 使用 `.font(.subheadline.weight(.medium)).foregroundStyle(.secondary)`
- [ ] 分组逻辑：账户 / 偏好 / AI & 隐私 / 关于
- [ ] Typecheck 通过

---

### Phase 2：AI 架构深度赋能（Week 5-9）

#### US-011：Spatial Context Engine（ContextManager 协议）
**Description**: 作为开发者，我需要一个统一的上下文聚合层，让 LLM 调用拥有完整的「时空 + 偏好」感知。

**Acceptance Criteria**:
- [ ] 新增 `Services/Context/ContextManager.swift`，定义 `ContextManager` 协议
- [ ] 输入：`CLLocation` + `MKMapRect`（视野 BBox）+ `UserPreferences` + `Date` + `WeatherSnapshot?`
- [ ] 输出：标准化 JSON schema（参考 `packages/core/src/llm-context.ts` 同步定义）
- [ ] `VoiceAgentOrchestrator` 改为消费 `ContextManager.snapshot()` 而非裸 prompt
- [ ] 单元测试覆盖率 ≥ 80%（`SoloCompassTests/ContextManagerTests.swift`）
- [ ] `pnpm parity:check` 通过（TS ↔ Swift schema 同步）

#### US-012：RAG 数据管道 v1（Go backend）
**Description**: 作为产品，我希望独行评分基于真实评论数据，而非 OSM 标签推断。

**Acceptance Criteria**:
- [ ] 新增 `apps/api` Go 服务（gin + pgvector）
- [ ] 实现 `/internal/reviews/fetch.go`：从 Google Places API + OpenStreetMap notes 抓取评论
- [ ] 实现 `/internal/reviews/extract.go`：调用 Claude API 进行情感分析 + 维度抽取（Wi-Fi / 噪音 / 座位 / 员工友好 / 灯光 / 安全）
- [ ] 抽取结果写入 PostgreSQL（`reviews_extracted` 表 + pgvector 嵌入）
- [ ] iOS 新增 `Services/ReviewsService.swift` 调用 `/v1/experiences/{id}/solo-score`
- [ ] 兜底机制：API 不可用时降级到本地 `solo-score.ts` 计算
- [ ] Backend 单元测试覆盖率 ≥ 70%
- [ ] iOS 集成测试通过

#### US-013：多 Agent 编排（Intent / Query / Guide）
**Description**: 作为开发者，我需要把单一 LLM 调用拆分为职责清晰的多 Agent，让每个 Agent 独立优化。

**Acceptance Criteria**:
- [ ] 重构 `VoiceAgentOrchestrator` 为 `AgentRouter`，根据用户输入分发到三个 Agent
- [ ] `IntentAgent`：判别用户意图（FindExperience / ChangeSettings / GetRecommendation / SmallTalk），使用轻量 prompt（< 500 tokens）
- [ ] `QueryAgent`：将自然语言转化为本地 Core Data 查询或后端 GraphQL 调用
- [ ] `GuideAgent`：生成有温度的推荐文案，使用流式响应（SSE）
- [ ] Agent 之间通过 `AgentMessage` 协议传递结构化数据
- [ ] E2E 测试：3 类典型对话场景全通过

#### US-014：AI 上下文性能优化
**Description**: 作为用户，我希望 Chat 首字延迟 < 800ms。

**Acceptance Criteria**:
- [ ] `ContextManager.snapshot()` 调用耗时 < 50ms（基准测试）
- [ ] 视野 POI 数量超过 50 时自动按相关度筛选 top-20
- [ ] Anthropic API 使用 `stream: true` + prompt caching（`cache_control: ephemeral`）
- [ ] 性能基准测试纳入 CI：`xcodebuild test -only-testing:SoloCompassTests/PerformanceTests`

---

### Phase 3：Roadmap 探索（Week 10-12）

#### US-015：漫游笔记 PKM 导出
**Description**: 作为数字游民，我希望打卡的咖啡厅能自动生成 Markdown 笔记，导出到 Notion / Obsidian / Flomo。

**Acceptance Criteria**:
- [ ] 新增"导出笔记"按钮在 `ExperienceDetailView`
- [ ] 生成 Markdown 模板：`{标题} / 坐标 / 时间 / 天气 / 体验标签 / 用户备注`
- [ ] 支持三种导出目标：复制到剪贴板、Notion Web Clipper URL、Share Sheet
- [ ] Frontmatter 兼容 Obsidian Properties
- [ ] Typecheck + Simulator 验证

#### US-016：Obsidian/Hacker 深色主题
**Description**: 作为终端/极简审美用户，我希望有一个纯黑高对比度主题。

**Acceptance Criteria**:
- [ ] 新增 `Themes/ObsidianTheme.swift`，定义颜色 token（背景 `#0D1117`、强调色 `#39FF14` 或 `#00D9FF`）
- [ ] 地图瓦片切换为 Carto Dark Matter 或自定义 MapKit `.hybrid` + 滤镜
- [ ] POI 图标改为发光点阵（5x5 mini grid）
- [ ] 主题切换入口在 Preferences > 外观
- [ ] Typecheck 通过

#### US-017：离线优先数据持久化
**Description**: 作为弱网环境用户（跨国移动 / 山区徒步），我希望已访问城市的数据离线可用。

**Acceptance Criteria**:
- [ ] 用户访问城市时自动缓存其 POI 数据到 Core Data
- [ ] 缓存 TTL 7 天，超期后台静默刷新
- [ ] 离线模式 UI 提示：「📡 离线模式 - 显示缓存数据」
- [ ] 缓存大小限制 100MB，超出 LRU 淘汰
- [ ] Typecheck 通过

#### US-018：Edge AI 探索（Phase 3 stretch）
**Description**: 作为前瞻技术探索，验证 iOS 端侧运行小模型实现离线意图识别的可行性。

**Acceptance Criteria**:
- [ ] 集成 Apple `NaturalLanguage` framework 实现基础意图分类
- [ ] 评估 `MLX` 框架运行 < 100MB Embedding 模型（如 nomic-embed-text）的性能
- [ ] 产出技术 spike 文档：`docs/edge-ai-feasibility.md`
- [ ] 不要求生产集成，仅交付可行性报告

---

## 4. Functional Requirements

### Phase 1（UI）
- **FR-1**: 顶部 `FilterBarView` 必须支持悬浮胶囊样式 + 滚动收起动画
- **FR-2**: 所有悬浮 UI 元素必须使用 `.regularMaterial` 背景
- **FR-3**: FAB 点击必须触发触觉反馈 + 弹簧动效
- **FR-4**: `ExperienceDetailView` 不得显示占位文案，无数据时整段 Section 隐藏
- **FR-5**: 独行评分必须支持雷达图渲染，差异 < 0.5 时退化为高亮进度条
- **FR-6**: Chat Overlay 必须实现 6 态状态机，每态有独立 UI
- **FR-7**: 不得在用户可见位置出现 `chat.*` 等 i18n key 字面量
- **FR-8**: 语音输入必须显示音量响应波纹动效
- **FR-9**: City Picker 必须按 `geonameId` 去重 + 双语显示
- **FR-10**: Preferences 必须使用 `.insetGrouped` 样式

### Phase 2（AI）
- **FR-11**: 必须实现 `ContextManager` 协议聚合 location/viewport/preferences/time
- **FR-12**: 必须建立后端 RAG 数据管道生成真实评分
- **FR-13**: `AgentRouter` 必须将单一 LLM 调用拆分为 Intent/Query/Guide 三 Agent
- **FR-14**: Chat 首字延迟必须 < 800ms（P95）

### Phase 3（Roadmap）
- **FR-15**: 必须支持 Markdown 笔记导出（剪贴板 / Notion / Share Sheet）
- **FR-16**: 必须提供 Obsidian 风格深色主题
- **FR-17**: 必须支持已访问城市离线缓存
- **FR-18**: Edge AI 仅交付可行性报告，不要求生产集成

---

## 5. Non-Goals（明确排除）

- 不重构地图底层 SDK：仍使用 MapKit，不引入 Mapbox / MapLibre
- 不引入第三方依赖：iOS 端保持 zero-dep 原则
- 不做 Android/Web 跨端同步：本 PRD 仅 iOS + 后端
- 不做用户社交功能：评论、点赞、UGC 全部不在范围
- 不替换 Anthropic API：仍使用 Claude，不切换到 OpenAI/Gemini
- 不做支付/订阅改造：`SubscriptionService` 保持现状
- 不做地图瓦片自托管：Obsidian 主题使用第三方瓦片源或滤镜
- Phase 3 的 Edge AI 不要求落地：仅探索 spike

---

## 6. Design Considerations

### 6.1 视觉规范
- **配色**：遵循 iOS 17 Dynamic Color，明暗模式自适应
- **字体**：SF Pro Display（标题）+ SF Pro Text（正文）+ SF Mono（坐标 / 代码）
- **圆角**：卡片 16pt、按钮 12pt、芯片 999pt（Capsule）
- **间距**：8pt grid system（4/8/12/16/24/32/48）
- **动效**：默认 `.spring(response: 0.35, dampingFraction: 0.8)`

### 6.2 可复用组件清单
- `SkeletonView`（US-003）
- `SoloScoreRadarChart`（US-004）
- `GlassmorphismCapsule`（US-001/002）
- `VoiceWaveformView`（US-008）
- `BilingualCityRow`（US-009）

### 6.3 参考产品
- **Apple Maps**：FAB 玻璃质感、底部 Sheet 拖拽
- **Things 3**：InsetGrouped 列表的图标与圆角
- **Notion Calendar**：极简主题色彩
- **Obsidian**：深色主题对比度参考

---

## 7. Technical Considerations

### 7.1 架构图
```
iOS App
├── Views (SwiftUI)
│   ├── Map (CompassMapView + FilterBarView 重构)
│   ├── Experience (ExperienceDetailView + SkeletonView + RadarChart)
│   ├── Chat (ChatStateMachine + VoiceWaveformView)
│   └── Settings (InsetGroupedList + ObsidianTheme)
├── Services
│   ├── Context/ContextManager (US-011)
│   ├── Agents/{IntentAgent, QueryAgent, GuideAgent} (US-013)
│   ├── ReviewsService (US-012 client)
│   └── ThemeService (US-016)
└── Persistence
    └── OfflineCache (CoreData + LRU, US-017)

apps/api (Go - 新增)
├── reviews/
│   ├── fetcher (Google Places + OSM)
│   ├── extractor (Claude API)
│   └── store (Postgres + pgvector)
└── handlers/
    └── solo-score endpoint
```

### 7.2 数据契约同步
- 任何修改 `packages/core/src/experience.ts` 或新增 `llm-context.ts` 必须运行 `pnpm parity:check`
- Go API schema 通过 `openapi.yaml` 生成 Swift Codable 类型

### 7.3 性能预算
- Chat 首字延迟：P50 < 500ms / P95 < 800ms
- 地图首屏：< 1.5s（含 POI 渲染）
- App 冷启动：< 2s
- 内存峰值：< 200MB

### 7.4 兼容性
- 最低 iOS 17.0（现状）
- 测试设备：iPhone 12 / iPhone 16 Pro / iPad Pro 11"

### 7.5 关键依赖
- Anthropic SDK（API caching + streaming）
- Google Places API（评论数据源，需评估配额成本）
- Apple WeatherKit（天气上下文，可选）

---

## 8. Success Metrics

### 8.1 量化指标（每个里程碑可验证）

| Phase | 指标 | 基线 | 目标 | 测量方法 |
|---|---|---|---|---|
| P1 | App Store 评分 | TBD | +0.4 颗星 | App Store Connect |
| P1 | 视觉相关差评频次 | TBD | -50% | 关键词分析（"丑" "未翻译" "占位"） |
| P1 | 地图滚动 FPS | TBD | ≥ 60 | Instruments |
| P1 | 未本地化键值数 | > 0 | 0 | CI 检查脚本 |
| P1 | City Picker 重复项 | > 0 | 0 | 单元测试 |
| P2 | Chat 会话完成率 | TBD | +25% | 后端埋点 |
| P2 | Chat 首字延迟 P95 | TBD | < 800ms | 客户端埋点 |
| P2 | 独行评分维度差异度 | ~0 | ≥ 1.5 | 数据库统计 |
| P3 | D7 留存（Remote Worker 用户） | TBD | +15% | Analytics |
| P3 | 离线模式可用 POI 比例 | 0% | ≥ 80%（已访问城市） | 客户端日志 |

### 8.2 用户体验定性指标
- **Apple HIG 评审**：所有 P0 故事通过 iOS 设计师评审（≥ 4/5 分）
- **数字游民焦点小组**（5 人）：「视觉质感」与「AI 帮助度」NPS ≥ 8

---

## 9. 设计验证方案

### 9.1 验证 Checklist（每里程碑）

#### Phase 1 验收 Checklist
- [ ] FilterBarView 滚动收起动画在 iPhone 12 / 16 Pro 上 ≥ 60 FPS
- [ ] FAB 触觉反馈在静音模式下仍生效
- [ ] Bottom Sheet 选中 POI 时不遮挡 Pin（视觉验证）
- [ ] 雷达图在 3 个差异化 POI 上正确渲染
- [ ] Chat Overlay 在 API Key 缺失时显示引导卡片（不显示裸键值）
- [ ] 全仓 grep `chat\.[a-z]+\.[a-z]+` 返回 0 结果（在 .swift 源码中）
- [ ] 语音波纹动效在低端设备（iPhone 12）保持 60 FPS
- [ ] City Picker 搜索"Vientiane"/"万象" 均只返回 1 条
- [ ] 设置页与 Apple Settings 视觉对比无明显差异

#### Phase 2 验收 Checklist
- [ ] `ContextManager.snapshot()` 单测覆盖率 ≥ 80%
- [ ] `pnpm parity:check` 通过（TS ↔ Swift schema）
- [ ] RAG pipeline 在 100 个种子 POI 上跑通 E2E
- [ ] Chat 首字延迟 P95 < 800ms（100 次采样）
- [ ] 三个 Agent 在典型对话场景中职责不交叉（人工 code review）
- [ ] Anthropic prompt cache 命中率 ≥ 60%

#### Phase 3 验收 Checklist
- [ ] Markdown 导出在 Obsidian / Notion / Flomo 中正确解析
- [ ] Obsidian 主题对比度通过 WCAG AA（≥ 4.5:1）
- [ ] 离线模式在飞行模式下可用，UI 明确提示
- [ ] Edge AI 可行性报告交付（含性能数据 + 推荐路径）

### 9.2 A/B 测试方案

| 实验 | 对照组 | 实验组 | 主指标 | 次指标 | 样本量 | 周期 |
|---|---|---|---|---|---|---|
| **A1 顶部筛选栏** | 原工具栏 | 悬浮胶囊 + 滚动收起 | 地图区域点击率 | 筛选使用率 | 50/50 split, ≥ 2000 用户 | 7 天 |
| **A2 独行评分可视化** | 进度条 7.0 | 雷达图差异化 | POI 详情页停留时长 | 导航按钮点击率 | 50/50, ≥ 1500 用户 | 7 天 |
| **A3 Chat 状态机** | 现状（裸键值） | 状态机 + 引导卡 | Chat 会话发起率 | Chat 完成率 | 50/50, ≥ 1000 用户 | 14 天 |
| **A4 雷达图 vs 进度条**（在 A2 通过后） | 雷达图 | 加粗 top-1 进度条 | 评分理解准确度（用户测试） | - | 用户测试 8 人 | 1 周 |
| **A5 RAG 评分 vs OSM 推断** | OSM 推断 | RAG 真实评论 | POI 收藏率 | 用户反馈"评分准确度" | 50/50, ≥ 1500 用户 | 14 天 |

**Guardrail 指标**（任一恶化 > 5% 自动停止）：崩溃率、地图加载时长、App 内存峰值

### 9.3 用户测试脚本（5-7 人 think-aloud）

**招募画像**：
- 数字游民 / 远程工作者，过去 6 个月有跨城市/跨国移动经历
- 3 人 iPhone 重度用户（每日使用 ≥ 5h）
- 2 人极简审美偏好（使用 Obsidian / Bear / Things 等工具）
- 2 人对 AI 工具有使用经验（ChatGPT / Claude / Perplexity）

**测试任务**（每人 45-60 分钟，远程录屏）：

1. **任务 1 - 地图浏览（10 min）**：
   > "你刚到一个新城市（万象），打开 Solo Compass，告诉我你看到什么、想做什么。"
   - 观察：是否注意到筛选栏胶囊？是否觉得地图视野够大？

2. **任务 2 - 找一个工作的咖啡厅（15 min）**：
   > "你需要找一个适合远程办公 2 小时的咖啡厅。"
   - 观察：是否使用筛选？是否看雷达图？是否信任评分？

3. **任务 3 - 与 AI 对话（15 min）**：
   > "请向 AI 助手语音询问你想做的事，自由发挥。"
   - 观察：触发率、首次成功率、是否遇到错误状态、对状态机的感知

4. **任务 4 - 极限场景（10 min）**：
   > "假设你在山区，网络很差，你会怎么使用？" + "你愿意把这个咖啡厅保存到笔记吗？"
   - 观察：离线模式提示是否清晰、导出功能是否符合预期

5. **任务 5 - 主题切换（5 min）**：
   > "如果让你定制这个 App 的外观，你会怎么选？" （展示 Obsidian 主题）
   - 观察：审美匹配度、对发光点阵 POI 的接受度

**评估输出**：
- 每个里程碑的 SUS（System Usability Scale）评分
- 任务完成率 / 任务时长 / 错误次数
- 关键引用（Top 5 痛点 + Top 5 惊喜点）
- 优先级修复清单（按出现频次 × 严重度排序）

---

## 10. Open Questions

1. **RAG 数据合规**：Google Places API 评论是否允许二次抽取并存储？是否需要切换到自有 UGC？
2. **WeatherKit 配额**：天气上下文调用频率上限？是否需要客户端缓存策略？
3. **Edge AI 路径选择**：Apple `NaturalLanguage` vs `Core ML` 量化模型 vs `MLX` 框架？需要 spike 验证。
4. **A/B 实验平台**：当前是否有 GrowthBook / Optimizely / 自建？影响 Phase 1 实验落地节奏。
5. **后端语言确认**：`apps/api` 使用 Go 是基于性能假设，是否考虑用 TypeScript（Fastify）保持单一语言栈？
6. **多 Agent 编排框架**：自建 `AgentRouter` 还是引入 Apple 官方未来的 Foundation Models 框架？
7. **iOS 最低版本**：Phase 3 的 Edge AI 若需要 iOS 18+ 特性，是否提升最低版本？
8. **地图瓦片授权**：Obsidian 主题如果使用 Carto Dark Matter，商用授权成本？
9. **Phase 重叠度**：Phase 1 的 US-004（雷达图数据源）依赖 Phase 2 的 US-012（RAG pipeline），是否需要调整顺序或允许 P1 先用 mock 数据？
10. **触觉反馈无障碍**：是否需要为关闭触觉反馈的用户提供视觉替代？

---

## 11. 实施建议（给 Eng 团队）

### 11.1 建议的实施顺序

```
Week 1-2:  US-001, US-002, US-005 (地图视觉基础)
Week 3:    US-003, US-004 (Bottom Sheet, 雷达图先 mock 数据)
Week 4:    US-006, US-007, US-008 (Chat 状态机 + 本地化)
           US-009, US-010 (Picker + Preferences)
Week 5-6:  US-011 (ContextManager)
Week 7-8:  US-012 (RAG pipeline) — 并行 backend 与 iOS
Week 9:    US-013, US-014 (多 Agent + 性能优化)
Week 10:   US-015 (PKM 导出)
Week 11:   US-016, US-017 (主题 + 离线)
Week 12:   US-018 (Edge AI spike) + 总验收
```

### 11.2 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| Google Places API 配额超支 | M | H | 提前评估，必要时降级到 OSM Notes only |
| RAG pipeline LLM 调用成本失控 | M | M | 设置 daily budget cap + 缓存层 |
| 雷达图在低端设备掉帧 | L | M | 退化为进度条 fallback |
| 多 Agent 重构引入对话回归 | M | H | 保留旧 Orchestrator 作为 feature flag |
| WeatherKit 调用失败影响 Context | L | L | Context 中 weather 字段设为 optional |

### 11.3 推荐的 Sub-Agent 分工
- **frontend persona** → US-001 至 US-010（UI 重构）
- **backend persona + architect persona** → US-011, US-012（架构）
- **architect persona + analyzer persona** → US-013, US-014（Agent 编排）
- **scribe persona** → 本 PRD 后续更新 + 用户测试报告

---

## 12. Appendix

### A. 关键文件路径速查

| 模块 | 路径 |
|---|---|
| 地图主界面 | `apps/ios/SoloCompass/Views/Map/CompassMapView.swift` |
| 筛选栏 | `apps/ios/SoloCompass/Views/Filter/FilterBarView.swift` |
| POI 详情 | `apps/ios/SoloCompass/Views/Experience/ExperienceDetailView.swift` |
| 城市选择 | `apps/ios/SoloCompass/Views/Map/CityPickerSheet.swift` |
| AI 编排 | `apps/ios/SoloCompass/Services/VoiceAgentOrchestrator.swift` |
| 语音 | `apps/ios/SoloCompass/Services/VoiceService.swift` |
| 本地化 | `apps/ios/SoloCompass/Resources/en.lproj/Localizable.strings` |
| Solo Score 算法 | `packages/core/src/solo-score.ts` |
| Experience Schema | `packages/core/src/experience.ts` |

### B. 相关 PRD 与文档
- `tasks/prd-ios-first-run-experience.md`
- `tasks/prd-paid-app-foundation.md`
- `tasks/prd-followup-experience.md`
- `docs/PRODUCT_BRIEF.md`
- `docs/PHASES.md`

### C. 参考资料
- [Apple HIG - Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [Anthropic - Prompt Caching](https://docs.anthropic.com/claude/docs/prompt-caching)
- [Carto Dark Matter Tiles](https://carto.com/basemaps)
- [System Usability Scale (SUS)](https://www.usability.gov/how-to-and-tools/methods/system-usability-scale.html)
