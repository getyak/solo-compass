# PRD: Route-Anchored Companion(路线锚定同伴)

> Status: Draft v1 · Owner: cubxxw · Date: 2026-05-28
> Supersedes: `tasks/prd-companion-mode.md`(location-based companion / DiscoverPost / geohash6 / presence)
> Design refs: `claude.ai/design` bundles `k2GuTTxIKmDEKCws4G-PoA`(SoloCompass.html)/ `GTH5R1HBaR6gDvhASkggGA`(CompareCanvas.html)

---

## 1. Introduction / Overview

Solo Compass 的同伴功能正在从"地理邻近匹配"切换为"**路线锚定**"。

同伴不再以"谁此刻在我附近"为匹配基础,而是以"**愿意一起走同一条路线**"为基础。一条路线在数据上是有序的体验序列,在产品上既是**纯内容**(独行者可读、可保存、可走),也是**同伴载体**(可携带招募状态、可申请加入、走完后晋升为已验证路线)。

这次同步还要落地两件耦合很紧的事:

- **A+A+A 信息架构**:独行是默认,同伴功能默认关闭。打开后,同一张路线卡获得"招募模块",不再有"独行/社交"模式切换。
- **Apple Maps 式底部抽屉**:三档高度 170 / 500 / 800 pt,容纳"附近"和"路线"两类信息流,把路线列表从地图上滑出来。

本 PRD 覆盖 **P0 → P4 全范围**,本地优先(`FF_BACKEND_SYNC` 默认关),P2 之后的数据流以本地 fixture + 预留接口的方式存在。废弃上一轮快速做的 `CompanionHubSheet`(右上角人像入口),按 A+A+A 把入口下沉到 Settings。

## 2. Goals

- 在同一个 `Route` 对象上同时支持**纯内容浏览**与**同伴招募**,无模式切换。
- 替换 `DiscoverPost` + `PresenceService` + 地图人物 pin,改以"招募中的路线"作为同伴入口。
- 把"完成 → verified"做成可见的内容飞轮:走完一条招募中的路线 → 路线进入已验证状态,成为下一批旅人的优质种子。
- 不破坏 local-first 不变量:浏览路线、保存为私有 itinerary、Route 详情查看全程离线可用。
- 信息架构纯净:独行用户(同伴关闭)在地图主表面**完全感受不到**任何同伴 UI。
- 用 Apple Maps 式三档抽屉(170 / 500 / 800)统一"附近"和"路线"两个信息流。
- 视觉与设计稿对齐:沿用 Space Grotesk / Inter / JetBrains Mono / Noto Sans Lao 字体栈与暖色棕(`#5D3000`)主调。

## 3. User Stories

> 用户故事按 Phase 分组。**P0+P1 是本 sprint 的可交付范围**,P2-P4 在同份 PRD 内做契约约定但落地放到后续 sprint。

### Phase P0 · Route as Content(本地优先,无招募)

#### US-001:Route 模型与持久化

**描述**:作为开发者,我需要一个 `Route` 数据模型(基于已有 `Itinerary` 演进),把"有序体验序列 + 元数据 + verification + 可选 companion 槽"沉淀为可持久化的核心对象。

**Acceptance Criteria:**

- [ ] 新增 Swift 结构体 `Route`,字段:`id / title / summary / experienceIds: [String](有序) / cityCode / region / estimatedDuration / distanceMeters / pace / tags / source / authorId / bestStartHour / bestNow / verification / companion?`
- [ ] `Route.verification` 字段:`status (proposed | walked_by | verified) / walkedByCount / walkedBy: [UserRef]`
- [ ] `Route.companion` 可空,当且仅当 host 已打开招募才存在(P1 引入)
- [ ] 新增 SwiftData `RouteRecord` @Model,数组字段以 JSON blob 持久化(沿用 `ItineraryRecord` 的 `experienceIdsBlob` 模式)
- [ ] 新增 `RouteStore`,提供 `all() / get(id) / save(Route) / delete(id) / nearby(city, count)` 五个方法
- [ ] `Route` 与 `Itinerary` 共存:`Itinerary` 视作"用户私人路线"特例(`source = user_created`,`companion = nil`),保留现有视图能读取转换后的 Route
- [ ] 单元测试覆盖:CRUD、Route↔Itinerary 互转、有序性、verification 默认值
- [ ] `pnpm parity:check` 通过(TS↔Swift schema 一致)

#### US-002:4 条万象 seed 路线

**描述**:作为产品,我需要 4 条静态 seed 路线让"路线"概念在本地立即可用,而不必等内容运营到位。

**Acceptance Criteria:**

- [ ] `Resources/JSON/seed_routes.json` 含 4 条万象路线(对应设计稿 `data.js` 的 `mekong-sunset / slow-coffee-day / morning-ritual / vientiane-monuments`)
- [ ] 4 条路线分别覆盖 4 种 companion 状态(`open / forming / closed/null / completed`),以便 UI 在本地展示全部状态
- [ ] 路线引用的体验 ID 必须能在现有 `seed_experiences.json` 里解析到;缺失体验在 `RouteStore.load()` 时被静默跳过并打日志
- [ ] `ExperienceService` 启动时把 seed 路线加载到 `RouteStore`(等同于体验 seed 的策略)

#### US-003:Route 详情页 —— 纯内容形态(P0 默认形态)

**描述**:作为独行用户,我打开任一路线时看到的是"内容":有序停靠点列表、节奏、估时、`已与 N 位旅人走过` 的可信度信号,**没有任何招募模块**。

**Acceptance Criteria:**

- [ ] 新增 `RouteDetailView`(SwiftUI,NavigationStack 内容),hero 区:封面渐变 + emoji + 标题 + 罗马名 + 城市标签
- [ ] Hero 下方 mono 基线条:`{estimatedDuration} · {distanceMeters} m · {pace} · 此刻最佳/非最佳`
- [ ] `VerifiedBadge`(默认 `badge` 样式):"已验证路线" / "社群观察中" + 头像堆叠 + "与 N 位旅人走过"
- [ ] `StopsList`:有序卡片,每张含分类色圆盘 + 标题 + 步行距离/时间
- [ ] 底部 dock:`保存到我的行程` / `加入收藏` 两个 CTA(无任何同伴 CTA)
- [ ] 路由入口:从地图标记(`MarkerIconView` 对应的体验是路线起点时)和底部抽屉的"路线"section 都可达
- [ ] 同伴关闭时,招募模块 **完全不渲染**(条件渲染,不仅是隐藏)
- [ ] Verify in Simulator using xcodebuild + simctl screenshot
- [ ] `xcodebuild test` 中 RouteDetailViewModel 单测通过

#### US-004:底部抽屉三档(Apple Maps 式)—— 容器

**描述**:作为用户,从地图主屏向上滑抽屉,把"附近的体验"和"招募中的路线"以列表方式呈现,而不只是地图标记。

**Acceptance Criteria:**

- [ ] 新增 `BottomInfoSheet`(SwiftUI),三档高度 **peek=170 / mid=500 / full=800** pt(与设计稿一致)
- [ ] 顶部 16×4 pt grab handle,长按或拖拽改变高度;松手吸附到最近档
- [ ] 拖拽期间 `dragOffset` 实时驱动 `frame.height`,clamp 在 `[120, 830]`
- [ ] 内容区:`peek` 显示 AI 提示行 + 排序/计数 + 1-2 张卡;`mid` 显示 4-5 张;`full` 显示完整滚动列表
- [ ] **替换** 现有 `BottomInfoBar`(独立窄条),老组件保留兼容,但 `CompassMapView` 不再渲染它
- [ ] 抽屉**与地图共存**:抽屉在 `peek` 时不阻挡地图标记的点击;在 `mid` 以上时背景出现轻微暗化
- [ ] 拖拽手势的优先级要让 `Map` 的 pan 仍然可用(只在 grab handle 区域触发抽屉拖拽)
- [ ] Verify in Simulator:三档切换、吸附、地图拖动不被劫持

#### US-005:抽屉内容 —— 附近 section

**描述**:作为用户,在抽屉中我能看到附近的体验,按"智能混合(AI top + 距离铺开)"排序,每条信息含距离/Solo 分/此刻状态。

**Acceptance Criteria:**

- [ ] 排序模式:默认 `smart`(AI top 3 置顶 + 其余按距离),其他模式 `distance / soloScore / now`
- [ ] 排序入口:抽屉 toolbar 的下拉,展开 sheet 选择
- [ ] 卡片左侧:分类色圆盘(沿用 `CategoryVisual.color`),设计稿规格 36×36,圆盘内为分类 emoji
- [ ] 卡片中部:中文诗化标题 + 罗马名 + 老挝原文(沿用 `Experience.title / titleRomanized / titleLocal`)
- [ ] 卡片元数据 chip:步行 N 分钟、Solo X.X、`此刻最佳`(金 `#C9A677`)、人群密度
- [ ] 卡片右侧:微型罗盘箭头(按方位旋转)+ mono 距离
- [ ] `smart` 模式下 top 3 卡片有金色左边框 + 暖白渐变背景
- [ ] 点击卡片 → 打开 `ExperienceDetailView`(现有视图,无改动)
- [ ] Verify in Simulator

#### US-006:抽屉内容 —— 路线 section

**描述**:作为用户,在抽屉中我能看到附近的路线,以路线卡形式平铺,可点开 `RouteDetailView`。

**Acceptance Criteria:**

- [ ] 抽屉内容顶部新增 `路线` section(高优先级,排在`附近`之前)
- [ ] `RouteCard`:封面渐变 + 路线标题 + 罗马名 + 估时/距离/节奏 mono 基线 + 停靠点数量徽章 + `已验证` 小角标(若 verified)
- [ ] 当同伴关闭(`FF_COMPANION = false` 或 `Settings.companionEnabled = false`):路线卡只显示内容,**无任何招募信息**
- [ ] 点击 → `RouteDetailView`
- [ ] `此刻` 筛选下只显示 `bestNow = true` 的路线,`附近`/`全部` 下显示同城所有路线
- [ ] Verify in Simulator:同伴关 / 同伴开,两种状态下卡片差异符合 A+A+A

#### US-007:废弃 CompanionHubSheet,清理地图右上角人像入口

**描述**:作为开发者,把上一轮快速做的 `CompanionHubSheet`(人像按钮 + Hub Sheet)废弃,按 A+A+A 把所有同伴入口下沉到 Settings,使地图主表面回到纯净的"独行内容"状态。

**Acceptance Criteria:**

- [ ] 删除 `MapOverlayView.companionHubButton` 及 `CompassMapView.isShowingCompanionHub` 状态
- [ ] 删除 `MapOverlayView` 的 `isShowingCompanionHub`/`inboxCount` props 及调用
- [ ] 保留 `CompanionHubSheet.swift` 文件 1 个 sprint(标 `@available(*, deprecated)`),让其内部的 NavigationLink 可被 Settings 复用;但**不在任何地方被实例化**
- [ ] 地图主表面 grep `CompanionHub` 应该 0 命中(除 deprecation 标记)
- [ ] Verify in Simulator:重新启动 app,主表面右上角无人像按钮,仅城市 pill + 定位/筛选小按钮
- [ ] xcodebuild test 全通过

#### US-008:Settings → Companion(experimental)section

**描述**:作为用户,我能在 Settings 里看到"同伴(实验中)"section,作为 A+A+A 模型下唯一的同伴入口。**默认关闭**。

**Acceptance Criteria:**

- [ ] `SettingsView` 在 `subscriptionSection` 之后插入 `companionSection`,标题"同伴(实验中)"
- [ ] section 内:一个 Toggle `companionEnabled`(读写 `UserPreferences.companionEnabled`,默认 false)
- [ ] Toggle 打开时,首次会拉起 `CompanionSafetyConsentSheet`(已存在),用户接受后才真正写入 `companionEnabled = true`
- [ ] 用户拒绝同意 → Toggle 回滚到 false
- [ ] 启用后,section 多出 3 个 `NavigationLink`:`同伴档案 / 我的招募申请 / 已加入的群聊`(三个目的地复用现有 `CompanionProfileView` / `RequestInboxView` / `ChatView` 列表,见 P2/P3)
- [ ] 用户偏好持久化:`UserPreferences.companionEnabled: Bool`(已有 SwiftData 持久化机制)
- [ ] Verify in Simulator:Toggle 打开 → safety sheet 出现;接受后 section 展开;关闭后 section 收起

#### US-009:Itinerary-detail bridge fix(挽救保存的路线)

**描述**:作为用户,从体验详情把路线保存进我的行程后,成功 toast 上要有一个"查看行程"按钮,直接跳到该行程,否则保存了等于丢失。

**Acceptance Criteria:**

- [ ] `AddToItinerarySheet` 提交成功后的 toast/alert 含"查看行程"按钮
- [ ] 点击 → `push` 到 `ItineraryDetailView`(/ 未来的 `RouteDetailView`)
- [ ] toast 不点击的话 2.5s 自动消失,但路线已保存(保持现有行为)
- [ ] Verify in Simulator

---

### Phase P1 · Recruiting Module(本地展示,无后端)

#### US-101:Route.companion 模型 + 状态机

**描述**:作为开发者,我需要 `RouteCompanion` 子结构和它的状态机,让招募状态在本地可流转、可持久化。

**Acceptance Criteria:**

- [ ] 新增 `RouteCompanion` 结构体:`status (open|forming|closed|completed) / hostId / departureWindow / departureLabel / pacePreference / maxMembers / confirmedMembers: [String] / joinRequests: [JoinRequest] / visibility / groupConversationId? / hostMessage?`
- [ ] 新增 `JoinRequest` 结构体:`id / requesterId / message / status (pending|accepted|declined|withdrawn) / createdAt`
- [ ] 状态机以 `RouteCompanionStateMachine` 类型方法实现(纯函数),输入 (当前状态, 事件) → 新状态:
  - `open + acceptFirst` → `forming`
  - `forming + reachMax | closeEarly` → `closed`
  - `closed + markCompleted` → `completed` 同时 trigger `Route.verification.status = verified`,`walkedBy += confirmedMembers`
- [ ] 单测覆盖 4 个合法转换 + 5 个非法转换(应抛 `IllegalTransition`)
- [ ] `RouteRecord` 增持 `companionBlob: Data?`(JSON 编码)持久化

#### US-102:RecruitingModule —— 路线详情中的招募模块(克制视觉,默认)

**描述**:作为同伴启用用户,我在 `RouteDetailView` 中能看到一个"克制"风格的招募模块,展示主理人、出发窗口、节奏、`{filled}/{max}` 成员、宿主留言。

**Acceptance Criteria:**

- [ ] 新增 `RecruitingModule` 视图,props:`route / status / strength=.restrained / onRequestJoin / onViewRequests / viewerIsHost / hasMyRequest`
- [ ] `restrained` 视觉:边框 1pt `--border-subtle (#EDE8DF)`,圆角 14pt,白底,内边距 16pt;头部胶囊状态标签(根据 `status` 显示不同 tone)
- [ ] 头部:`{statusLabel}`(招募中/即将成团/已成团·出发中/行程已完成)+ `{departureLabel}` mono 字体
- [ ] 主理人行:头像(`USERS[hostId].color` 实心圆) + 昵称 + 简介
- [ ] 4 个 slot 圆形 placeholder,已 confirmed 显示头像,未填空圆 + `+` 微小标识
- [ ] 宿主留言引文(若 `hostMessage` 非空)
- [ ] CTA(底部):根据 `viewerIsHost / hasMyRequest / status` 切换标签(查看申请 / 已申请·等待确认 / 申请加入 / 查看群聊)
- [ ] 同伴关闭时 `RecruitingModule` **完全不渲染**(条件渲染)
- [ ] 同伴启用且 `route.companion = nil` 时也不渲染(纯内容路线)
- [ ] Verify in Simulator:同伴关 / 同伴开两种状态,克制模块出现/消失符合预期

#### US-103:招募模块视觉强度三档(为后续 AB 留接口)

**描述**:作为产品,我希望"招募模块"的视觉强度是参数化的(克制/中性/强烈),默认克制,但代码上为后续 AB 实验或调强留有接口。

**Acceptance Criteria:**

- [ ] `RecruitingModule` 接受 `strength: ModuleStrength` 枚举:`.restrained / .neutral / .strong`
- [ ] 三档差异:边框/底色/状态标签强度(克制无强调色;中性加金色左边线;强烈整张暖色背景 + 强调主 CTA)
- [ ] `UserPreferences.companionModuleStrength`(默认 `.restrained`),Settings 内**不暴露**(只代码可改);为后续 AB 留接口
- [ ] Verify in Simulator:三档至少能跑出来一次截图

#### US-104:VerifiedBadge 三种表达(默认徽章卡)

**描述**:作为用户,我在路线详情中看到 walked-by 信号,有"已验证路线"或"社群观察中"的清晰区分。

**Acceptance Criteria:**

- [ ] `VerifiedBadge` 视图,`style: VerifiedStyle = .badge`(默认),另外两档 `.header` `.inline` 作为后续视觉实验
- [ ] `.badge`:hero 下方独立卡(白底 / 浅色边),左侧 24pt 图标(已验证 `check-circle`,观察中 `users`)+ 右侧头像堆叠最多 5 个 + "与 N 位旅人走过"
- [ ] `.header`:顶部全宽状态条(背景色根据 verified 切换)
- [ ] `.inline`:行内小标 pill(最低调,放在 mono 基线条上)
- [ ] 头像堆叠 `AvatarStack`:重叠 6pt,顶部 ring 2pt(颜色 `surface-white #FFFFFF`)
- [ ] Verify in Simulator:三档至少跑出截图

#### US-105:Companion Profile —— 把"走过的路线"作为信任信号

**描述**:作为同伴用户,我在自己/他人的资料里能看到"走过 N 条路线"+ 缩略列表,作为发起或接受请求时的信任信号。

**Acceptance Criteria:**

- [ ] 已有 `CompanionProfileView` 增加"我走过的路线" section
- [ ] 数据来源:遍历 `RouteStore.all()`,筛 `verification.walkedBy.contains(currentUserId)` 或 `companion.confirmedMembers.contains(currentUserId) && status == .completed`
- [ ] 展示前 5 条路线卡缩略(横向滚动),`查看全部` → 跳到完整列表
- [ ] 同伴未启用时,该 section 不渲染
- [ ] Verify in Simulator

---

### Phase P2 · Discover & Request(本地 fixture,UI 可走通,接口预留)

#### US-201:Discover Recruiting Routes 列表

**描述**:作为同伴启用用户,我能进入"发现招募中的路线"列表,看到本城 `companion.status = open / forming` 的路线,按"即将出发 + verified"混合排序。

**Acceptance Criteria:**

- [ ] 复用 `DiscoverListView`,但数据源切换为 `RouteStore.recruitingRoutes(cityCode:)`
- [ ] 排序权重:即将出发(`departureWindow.from` 距今 ≤ 7 天)优先,其次 `verification.status = verified`,再 city match
- [ ] 列表项:复用 `RouteCard`(招募强度展示),底部 chip:`{filled}/{max} · 即将出发 {departureLabel}`
- [ ] 空状态:"目前没有招募中的路线" + 提示"开一个你自己的路线?"按钮(跳到创建,P2.5 引入)
- [ ] 入口:Settings → Companion → 发现招募路线(`NavigationLink`)
- [ ] 也可在抽屉内 `路线` section 头部"发现更多招募中的路线 →" 进入
- [ ] 本地 fixture 模式下,数据是 `seed_routes.json` 中 `companion.status = open / forming` 的子集
- [ ] Verify in Simulator

#### US-202:Send Request to Join

**描述**:作为同伴用户,我能向某条招募路线提交加入请求,包含一句话留言 + 节奏匹配选择,主理人会在审批队列收到。

**Acceptance Criteria:**

- [ ] 复用 `SendRequestSheet`,重命名/调整为 `JoinRouteRequestSheet`,props:`route / onSubmit(message, pacePreference)`
- [ ] 内容:路线缩略卡(顶部置顶不可滚动)+ 节奏匹配 3 选 1(慢于 / 匹配 / 快于宿主节奏)+ 留言 textarea(占位"向主理人介绍自己,或为什么想加入这条路线...")
- [ ] 校验:留言至少 10 字符 + 节奏必选;否则 CTA 置灰
- [ ] 提交 → 本地 `JoinRequest` 写入 `route.companion.joinRequests`,本人 view 立刻看到 `已申请·等待确认`
- [ ] 后端接入位:`CompanionService.sendJoinRequest(routeId:, message:, pace:)`,P2 本地模式下 stub 返回 `.success`
- [ ] Verify in Simulator

#### US-203:Host Approval Queue

**描述**:作为主理人,我能在"审批队列"看到我的路线收到的所有 pending 请求,带申请人的信任信号(走过路数、opt-in 时长)。

**Acceptance Criteria:**

- [ ] 复用 `RequestInboxView`,接收 `route: Route` 参数,数据源为 `route.companion.joinRequests where status == .pending`
- [ ] 列表项:申请人头像 + 昵称 + 简介 + `已走过 N 条 · 拼团 M 次`(从 `USERS[id].walked / trips`)+ 留言 + 节奏匹配 chip
- [ ] 行动:接受 / 拒绝 / 举报-拉黑(沿用 `ReportBlockSheet`)
- [ ] 接受 → 状态机推进:`open → forming` 或 `forming + reachMax → closed`,自动创建群聊 conversation
- [ ] 入口:Settings → Companion → 我主理的路线(列出多条),选其中一条 → 审批队列
- [ ] 本地模式下:`acceptRequest` 直接修改本地状态;后端模式下走 `CompanionService`
- [ ] Verify in Simulator

#### US-204:My Requests(申请人视角追踪)

**描述**:作为申请人,我能在 Settings → Companion → 我的申请 看到所有我发出的 join request 状态(pending / accepted / declined)。

**Acceptance Criteria:**

- [ ] 新增 `MyRequestsListView`,数据源:遍历 `RouteStore.all()`,挑出 `route.companion.joinRequests where requesterId == currentUserId`
- [ ] 列表项:路线缩略卡 + 状态 chip + `查看路线 / 撤回申请` 行动
- [ ] 撤回:`withdrawRequest` → 本地修改 status 为 `.withdrawn` 并从 host 队列消失
- [ ] Verify in Simulator

---

### Phase P3 · Group Chat & Verified Flywheel(本地模拟 + 接口预留)

#### US-301:Group Conversation(群聊)

**描述**:成团后(status 进入 forming 或 closed),自动创建群聊会话,参与者(host + 已接受成员)能在群聊里讨论行程细节。

**Acceptance Criteria:**

- [ ] `Conversation` 模型扩展:`type: ConversationType (one_on_one | group_route)`,新增 `routeId: String?`
- [ ] 当 status 从 `open → forming` 切换时,自动创建 `groupConversationId` 并写入 `route.companion`
- [ ] `ChatView` 接收 `Conversation`(已有逻辑),群聊形态多展示:顶部置顶路线卡(可点开 `RouteDetailView`),消息气泡左侧显示头像 + 昵称
- [ ] 入口:Settings → Companion → 已加入的群聊(列出所有我所在的群聊会话)
- [ ] 本地模式:聊天消息持久化到 SwiftData,`ChatService.send` 直接写本地;后端模式由 Supabase realtime 接管
- [ ] Verify in Simulator

#### US-302:Mark Completed → Verified 升级瞬间

**描述**:主理人在行程结束后点击"标记完成",触发 `closed → completed`,路线 verification 升级,所有成员获得"走过该路线"信用。

**Acceptance Criteria:**

- [ ] `RouteDetailView`(主理人视角,status = closed)出现"标记完成"主 CTA
- [ ] 点击 → 进入 `CompletionMoment` 全屏过渡视图:背景光线扩散动效、verified 徽章脉动、统计阵列(成员数 × 走过路数 += 1)、底部 flywheel 标语"这条路线现在为下一批旅人发光"
- [ ] 状态变化:`status = completed`,`verification.status = verified`,`walkedBy += confirmedMembers`,`walkedByCount += confirmedMembers.count`
- [ ] 群聊变为"只读纪念"模式(顶部 banner"行程已完成",输入框禁用)
- [ ] Verify in Simulator:`CompletionMoment` 至少 1.2s 动效完成后用户可点关闭

#### US-303:Host 创建一条招募路线(从已有 itinerary)

**描述**:作为主理人,我能把自己创建的私人 itinerary 转为"招募中的路线",设定出发窗口、最大成员数、节奏偏好。

**Acceptance Criteria:**

- [ ] `ItineraryDetailView` 已有 `openToCompanions` Toggle,需扩展为完整"开为招募路线"流程:点击 → `OpenForCompanionsSheet`
- [ ] sheet 表单:出发窗口(date range)+ 出发时间 + 节奏(slower/standard/faster)+ 最大成员数(2-8,默认 4)+ 宿主留言(textarea)+ 可见性(public / link_only)
- [ ] 提交 → 本地 itinerary 升级为 `Route` 并设 `companion`,status = `open`
- [ ] 升级后该 Route 在"发现招募中的路线"中可见
- [ ] Verify in Simulator

#### US-304:Backend Schema 接口预留(无 SQL 改动)

**描述**:作为开发者,我在 service 层抽象出 `RouteCompanionRemote` 协议,所有"招募/申请/聊天"调用都走该协议,本地模式实现是 in-memory stub,后端模式实现走 Supabase。**本 sprint 不部署后端**。

**Acceptance Criteria:**

- [ ] 新增 `protocol RouteCompanionRemote`(包含 `fetchRecruitingRoutes / sendJoinRequest / fetchInbox / accept / decline / withdraw / markCompleted` 等方法)
- [ ] 实现 `LocalRouteCompanionRemote`(基于 `RouteStore`)+ `SupabaseRouteCompanionRemote`(stub,实际方法 `throw NotImplemented`)
- [ ] `FF_BACKEND_SYNC` 选择具体实现
- [ ] 文档化未来 SQL 表 schema 草案到 `infra/supabase/migrations/0005_route_companion.sql.draft`(不执行,只作记录)

---

### Phase P4 · Co-create & Reputation(v1.x 涌现,不强排期)

#### US-401:Co-create(Shape B,emergent)

**描述**:作为产品观察者,我观察 P3 上线后是否自然涌现"先成团再共同把路线写出来"的用法。若涌现,补一个"群聊里共同编辑路线"的轻量入口。

**Acceptance Criteria:**

- [ ] 群聊顶部置顶路线卡可点"补充停靠点"(若 host 授权)
- [ ] 补充的停靠点经 host 接受后写入 `route.experienceIds`(保持顺序)
- [ ] 完成时该路线 `source = co_created`,`authorId` 指向 host,`contributors` 列出全部 confirmed members
- [ ] 优先级低,等 P3 用户行为数据回来再决定是否动工

#### US-402:Walked-by 信誉曲线展示

**描述**:作为用户,我在他人 Companion Profile 看到一条"近一年走过路线"的横向时间线,作为信誉曲线。

**Acceptance Criteria:**

- [ ] `CompanionProfileView` 顶部增加 sparkline:近 12 个月每月走过路线数
- [ ] 总数 + verified 比例 + 取消率(若有数据)
- [ ] Verify in Simulator

---

## 4. Functional Requirements

> 编号便于实现/测试索引。

### Route 模型与持久化

- **FR-1**:`Route` 必须以**有序数组** `experienceIds: [String]` 持久化(沿用 `ItineraryRecord.experienceIdsBlob` 模式)。
- **FR-2**:`Route.verification` 默认值 `(status: .proposed, walkedByCount: 0, walkedBy: [])`,seed 路线在 JSON 中显式设定。
- **FR-3**:`Route.companion` 可空。当且仅当 host 在 P3/US-303 中显式"开为招募"才被赋值。
- **FR-4**:`Itinerary` 与 `Route` 共存。`Itinerary` 视作 `source = .userCreated, companion = nil` 的 Route。两个模型有双向转换函数。
- **FR-5**:`RouteStore` 是同伴域的唯一数据源,所有读写穿过它,不允许 UI 直接 mutate `Route` 实例。

### A+A+A 信息架构

- **FR-6**:`UserPreferences.companionEnabled` 默认 `false`,首次打开必须经 `CompanionSafetyConsentSheet` 接受才真正设为 true。
- **FR-7**:`companionEnabled = false` 时,**主表面绝对无任何同伴 UI** —— 包含但不限于:招募模块、地图人物 pin、抽屉里"发现招募"提示、`RouteCard` 上的同伴角标。
- **FR-8**:`companionEnabled = true` 时,**地图主表面仍然无同伴 UI** —— 同伴入口仅在 Settings 与"路线详情的招募模块"中出现。
- **FR-9**:废弃 `CompanionHubSheet`(右上角人像入口);保留文件但全应用 grep `CompanionHub` 仅命中 deprecated 注释。

### 底部抽屉

- **FR-10**:抽屉三档高度精确为 **170 / 500 / 800 pt**。
- **FR-11**:拖拽期间 `dragOffset` 实时驱动高度,clamp 在 `[120, 830]`(允许越过 full 一点点产生橡皮筋感)。
- **FR-12**:松手时取与最近档的距离最小者作为新档。
- **FR-13**:抽屉 grab handle 区域大小 24×16 pt,其外的内容区不响应拖拽手势(避免劫持 Map pan)。
- **FR-14**:抽屉在 `peek` 状态背景透明,在 `mid` 以上对地图施加 `0.0 → 0.18` 的渐进暗化遮罩。

### 招募模块

- **FR-15**:`RecruitingModule` 视觉强度 3 档(`restrained / neutral / strong`),默认 `restrained`。
- **FR-16**:CTA 标签根据 `(viewerIsHost, hasMyRequest, status)` 三元组切换,严格对应设计稿表(见 `route.jsx:RecruitingModule:ctaLabel`)。
- **FR-17**:招募模块只在 `Route.companion != nil` 且 `UserPreferences.companionEnabled = true` 时渲染。

### Verified

- **FR-18**:`Route.verification.status` 转换规则:`walkedByCount >= 1` 任意时刻可标 `verified`(默认阈值 ≥1,符合产品决策第 5 问的提案)。
- **FR-19**:`VerifiedBadge` 默认 `.badge` 样式;`.header`/`.inline` 保留代码路径但 UI 中不默认使用。

### Join Request 状态机

- **FR-20**:合法转换:`pending → accepted/declined/withdrawn`。其余转换抛 `IllegalTransition`。
- **FR-21**:`accepted` 触发副作用:推进 companion 状态机 + 创建群聊 conversation(若 forming 首次发生)+ 给申请人 push 通知(本地通知,本 sprint 内不接 APNs)。

### 本地优先 / 后端预留

- **FR-22**:`FF_BACKEND_SYNC = false` 时,全部"招募/申请/聊天/完成"操作仅修改本地数据,不发任何网络请求。
- **FR-23**:`RouteCompanionRemote` 协议必须由本地实现和 Supabase stub 两个 conform,且都可通过编译。
- **FR-24**:本地模式下 `JoinRequest` 的 `requesterId` 用 `DeviceIdentityService.deviceId` 派生的本地 fake user 占位。

### 安全 / 举报

- **FR-25**:沿用 `reportUser` / `blockUser` / `reporter_weight` / `CompanionSafetyConsentSheet` 不变。
- **FR-26**:主理人对申请人的"举报-拉黑"动作同时移除该 pending 请求。

### 本地化

- **FR-27**:全部新增 UI 字符串走 `NSLocalizedString`,新增 key 同步落 `en.lproj/Localizable.strings` 和 `zh-Hans.lproj/Localizable.strings`。
- **FR-28**:无 raw key 漏到 UI(参考 P0 上一轮发现的 `companion.layer.off` 漏出问题)。

---

## 5. Non-Goals(本 PRD 不做)

- **不部署后端**:`infra/supabase/migrations/0005_route_companion.sql` 仅以 `.draft` 形式记录,本 sprint 不应用迁移、不重写 `companion-discover` edge function。
- **不做地图层路径线绘制**:路线不在地图上以 `MapPolyline` 形式呈现(P0 决策范围外,可能进 P5)。
- **不删除 `DiscoverPost`/`PresenceService`**:它们标 `@available(*, deprecated)` 即可,删除等 P3 完整切换确认后再做。
- **不做实时匹配/在线状态/距离匹配** —— 整套路线锚定**就是**为了消灭这些。
- **不重做现有 Itinerary 表单/详情**:Itinerary 仍走原视图;P3 才把"开为招募"流程接进去。
- **不做身份验证升级**(实名/手机验证)—— Open Question #2 暂不解,默认"完成 profile + 同意 safety"即可主理。
- **不接 APNs 远端推送** —— 仅本地 `NotificationService` 触发。
- **不实现 ExperienceCardView 上的"加入同伴 CTA"**:同伴入口只在路线层,不在体验层。
- **不做 Shape B 的专属创建流(US-401)**:让其从 P3 群聊行为中涌现。

---

## 6. Design Considerations

### 视觉 token(来自设计稿 `styles.css`,本 PRD 对齐)

| token              | 值                                                                              | 用途                                                      |
| ------------------ | ------------------------------------------------------------------------------- | --------------------------------------------------------- |
| `--bg-warm`        | `#FAF8F6`                                                                       | 主背景(暖纸色)                                            |
| `--surface-white`  | `#FFFFFF`                                                                       | 卡片底                                                    |
| `--surface-sunken` | `#F3EEE6`                                                                       | 凹陷区底(抽屉)                                            |
| `--fg-primary`     | `#1F1A14`                                                                       | 主文                                                      |
| `--fg-muted`       | `#6D6358`                                                                       | 次文                                                      |
| `--fg-subtle`      | `#A39A8C`                                                                       | 三级文                                                    |
| `--border-subtle`  | `#EDE8DF`                                                                       | 细边                                                      |
| `--accent`         | `#5D3000`                                                                       | 主强调(深棕,替代之前的蓝)                                 |
| `--sun-gold`       | `#C9A677`                                                                       | 此刻金                                                    |
| 分类色 8 色        | `#E89530 / #2FA46A / #E84B3F / #9B6A3A / #2F7DD1 / #2FA8B5 / #7A5BCC / #8E8676` | culture/nature/food/coffee/work/wellness/nightlife/hidden |
| `--radius-card`    | `14px`                                                                          | 卡片圆角                                                  |
| `--radius-pill`    | `999px`                                                                         | 胶囊                                                      |
| `--shadow-lift`    | `0 8px 28px -8px rgba(36,22,0,0.18), 0 2px 6px rgba(36,22,0,0.06)`              | 浮层阴影                                                  |

### 字体栈

| family           | 用途           |
| ---------------- | -------------- |
| `Space Grotesk`  | 标题(display)  |
| `Inter`          | 正文(body)     |
| `JetBrains Mono` | 数据/距离/时间 |
| `Noto Sans Lao`  | 老挝原文       |
| `PingFang SC`    | 中文 fallback  |

### 关键尺寸

- 抽屉档位:**170 / 500 / 800 pt**(精确,不可漂移)
- 卡片高度:peek 摘要卡 64pt / 标准卡 92pt / 详细卡 120pt
- 头像堆叠:重叠 6pt,ring 2pt(色 `surface-white`)
- 分类色圆盘:36×36pt
- Top picks 金色左边框:3pt(`--sun-gold`)

### 复用现有组件

| 现有                          | 复用方式                          |
| ----------------------------- | --------------------------------- |
| `ExperienceCardView`          | 在抽屉"附近"section 中渲染,无改动 |
| `CategoryVisual`              | 分类色映射不变                    |
| `GlassmorphismCapsule`        | 顶部城市 pill / 筛选 / 排序胶囊   |
| `MarkerIconView`              | 地图标记不变                      |
| `CompanionProfileView`        | P3 增加"走过的路线" section       |
| `CompanionSafetyConsentSheet` | A+A+A opt-in 时拉起,内容不改      |
| `ChatView` / `ChatService`    | P3 群聊形态适配,顶部增置顶路线卡  |

### 7 屏旅程对齐(对应 CompareCanvas)

设计稿"完整旅程 · 7 屏"映射到本 PRD 的 user stories:

1. **设定 → 同伴入口** → US-008
2. **Opt-in · 第一步** → US-008(Toggle + Safety sheet) + 现有 `CompanionProfileView`
3. **发现招募中的路线** → US-201
4. **申请加入(申请人视角)** → US-202
5. **宿主审批(主理人视角)** → US-203
6. **群聊(成团后)** → US-301
7. **完成 → Verified 升级** → US-302

---

## 7. Technical Considerations

### Route 在 Itinerary 上的演进策略

- 现有 `Itinerary` 已经是 ordered list(`experienceIds: [String]`)— **不需要数据迁移**。
- `Route` 是 `Itinerary` 的超集:多了 `summary / pace / verification / companion / source / authorId / region / bestStartHour / bestNow`。
- 实现策略:**Route 与 Itinerary 并存** —— 新建 `Route`/`RouteRecord` 类型,保留 `Itinerary`/`ItineraryRecord`,提供双向转换。P0 内 `MyItineraries` 列表展示 Itinerary,P3 把它升级为 Route。

### CompanionHub 废弃路径

- 上一轮做的:`CompanionHubSheet.swift` + `CompassMapView` 的人像按钮 + sheet binding。
- 本 PRD 处理:
  1. `CompassMapView`:删除 `isShowingCompanionHub` 状态、`companionHubButton` 私有 view、`MapOverlayView` 的 `isShowingCompanionHub`/`inboxCount` props。
  2. `CompanionHubSheet.swift`:保留文件 1 个 sprint,struct 标 `@available(*, deprecated, message: "Replaced by Settings → Companion section per A+A+A.")`。
  3. Settings → Companion section 内的 `NavigationLink` 直接复用 `DiscoverListView / RequestInboxView / CompanionProfileView / ItineraryListView` 视图本身,不再经 Hub。
- 1 个 sprint 之后(P2 上线时)彻底删除 `CompanionHubSheet.swift`。

### 本地优先策略

- `FF_BACKEND_SYNC = false`(默认):
  - 所有 Route / JoinRequest / Conversation 写入 SwiftData
  - `CompanionService` 的 `fetchDiscovery / sendRequest / acceptRequest / declineRequest` 直接读写 `RouteStore`,不出网
  - `ChatService.send` 把消息写本地 SwiftData,实现 `Conversation` 内的本地多消息回看
- `FF_BACKEND_SYNC = true`(未来):
  - 走 `SupabaseRouteCompanionRemote`,P2 stub `throw NotImplemented`
  - SQL schema 草案已在 `0005_route_companion.sql.draft` 中记录但未应用

### 抽屉手势冲突

- 已知问题:`Map` 的 pan 手势与抽屉的 drag 手势会冲突。
- 解决方案:抽屉的 `DragGesture` 只附在 grab handle 区域(24×16 pt)。内容区滚动用 `ScrollView`,与抽屉拖动天然分离。
- 抽屉到 `full` 档时,顶部 navbar 高度让出地图剩余可视区不超过 60pt,避免用户误以为可继续上滑。

### 测试策略

- 单元测试:Route 模型、`RouteStore` CRUD、`RouteCompanionStateMachine` 全部转换、`AvatarStack` 头像排序
- 视图测试:`#Preview` 覆盖每个新视图(招募模块 4 状态 × 3 强度,Verified 3 样式,7 屏旅程)
- 集成测试:P0 全流程(打开 app → 抽屉上滑 → 选路线 → 看详情 → 保存)在 Simulator 截图比对
- xcodebuild test 在 iPhone 17 Pro / iOS latest 上必须全通过

### 性能考量

- `RouteStore.recruitingRoutes(cityCode:)` 应 O(n) 单次扫描;n ≤ 50 时无需缓存
- 抽屉拖拽期间 60fps,避免在 `dragOffset` 改动时触发任何重计算(`smartPicks` / `restList` 应在拖拽前固定)
- 地图与抽屉同时渲染时,内存占用 < 220 MB(参照现有水位)

---

## 8. Success Metrics

### P0 + P1 验收(本 sprint)

- 同伴关闭时,主表面 grep 命中"companion"相关 UI 元素 = **0**
- 4 条 seed 路线全部可在抽屉"路线"section 显示
- `RouteDetailView` 在 simulator 启动到首帧渲染 < 400ms
- 抽屉三档切换吸附时间 < 200ms,无掉帧
- `xcodebuild test` 全通过(目标 ≥ 95% 通过率,新加测试 100% 通过)
- 视觉 token 与设计稿一致(主色 `#5D3000` / 金 `#C9A677` 不漂移)

### P2 + P3 验收(下一 sprint)

- 同伴启用后,Settings → Companion 内 4 个 NavigationLink 全部可达且无空状态崩溃
- 7 屏旅程在本地 fixture 模式下完整可走通
- Verified 升级动效完整跑通,完成后 `Route.verification.walkedByCount` 正确增长

### 长期(产品维度)

- A+A+A 没失败:同伴关闭用户的 NPS / D7 留存不被同伴功能干扰(对照组对比)
- Verified 飞轮启动:在同伴启用用户中,完成 → verified 转换率 ≥ 30%
- 首次进入"发现招募路线"到首次提交申请的转化率 ≥ 20%

---

## 9. Open Questions

> 不阻塞本 PRD 进入实现,但需要在 P2 前回答。

1. **主理人门槛**:目前规则是"完成 profile + 同意 safety"即可。需要引入身份验证(手机/邮箱/实名)吗?何时?
2. **发现排序权重**:当前提案"即将出发 + verified + city match"按固定权重混合。后续是否需要根据用户偏好动态调权?
3. **群聊上限**:默认 max 4 / 上限 8。是否需要根据路线类型(咖啡半日 vs 多日)动态调整?
4. **Verified 阈值**:当前 `walkedByCount ≥ 1` 即 verified。如果想做"高质量验证"是否需要 ≥ 3 或人均评分?
5. **失败的成团回滚**:`forming` 状态超过 N 天无 max 触达,是否自动 fallback 到 `open`?是否通知 host?
6. **重复申请保护**:同一用户对同一路线 24h 内只能申请一次?跨路线无限制?
7. **跨城路线**:`cityCode` 是单值;多城路线(如"曼谷 → 万象 5 日")如何表达?(P5)
8. **本地 fake user**:P2 本地模式下 `JoinRequest.requesterId` 用本地 deviceId 派生 —— 若用户清 app,这些路线归属如何处理?

---

## 10. Implementation Notes(供 PR 拆分参考)

> 不是 PRD 的一部分,但便于将本 PRD 拆成可独立 ship 的 PR 序列。

| PR 序号 | 范围                                                                          | 阻塞        |
| ------- | ----------------------------------------------------------------------------- | ----------- |
| #1      | US-001 Route 模型 + US-002 seed                                               | 无          |
| #2      | US-004 BottomInfoSheet 三档容器                                               | 无(并行 #1) |
| #3      | US-007 废弃 CompanionHubSheet 入口                                            | 无(并行)    |
| #4      | US-003 RouteDetailView 纯内容 + US-005 抽屉附近 section + US-006 路线 section | #1, #2      |
| #5      | US-008 Settings Companion section + US-009 Bridge                             | #3          |
| #6      | US-101 状态机 + US-102/103/104 招募模块 + Verified                            | #1, #4      |
| #7      | US-105 Companion Profile 走过路线                                             | #1, #6      |
| #8      | US-201 发现 + US-202 申请 + US-203 审批 + US-204 我的申请                     | #6          |
| #9      | US-301 群聊 + US-302 完成升级 + US-303 host 开招募                            | #8          |
| #10     | US-304 后端 schema 草案                                                       | #9          |

> P4(co-create / 信誉曲线)走独立 PR,不在本批次内。

---

## 11. Appendix · 设计稿与代码事实索引

- 设计稿主屏: `/tmp/sc-design/solocompassapp/project/SoloCompass.html` + 同目录 `route.jsx` `companion.jsx` `sheet.jsx` `styles.css` `data.js`
- 对比画板: `/tmp/sc-design2/solocompassapp/project/CompareCanvas.html`(用 iframe 把 SoloCompass.html 多状态并排,**不需要在 iOS 实现**)
- chat 决策记录: `/tmp/sc-design/solocompassapp/chats/chat1.md`(抽屉决策)+ `chat2.md`(路线决策)
- 代码事实:
  - `Itinerary.experienceIds` 已是 `[String]` 有序数组(`apps/ios/SoloCompass/Models/Itinerary.swift:26`)
  - `ItineraryRecord.experienceIdsBlob` 已用 JSON 编码持久化(`apps/ios/SoloCompass/Persistence/Models/ItineraryRecord.swift:21`)
  - `FeatureFlags.companion` 默认 `false`(`apps/ios/SoloCompass/Services/FeatureFlags.swift`)
  - `FeatureFlags.backendSync` 默认 `false`
  - 当前 `CompanionHubSheet.swift` 存在但应废弃(US-007)
  - A+A+A 在代码中**尚未实现**(grep "opt-in" 无命中,需新建)
