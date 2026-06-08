# PRD: 好友系统与社交图谱（Friends & Social Graph）

> 设计参考：`docs/FRIENDS_DESIGN.md`（定稿 v1.1）
> 状态：可执行 PRD · 三期全覆盖 + 后端详设 + APNs 推送
> 日期：2026-06-08
> 关联但不重叠的既有 PRD：`prd-companion-mode.md`、`prd-companion-v2-trustworthy-personal.md`、`prd-route-anchored-companion.md`（这三份做「约伴」；本 PRD 做「持久关系层」，与之打通而非替代）

---

## 1. Introduction / Overview

Solo Compass 当前所有社交关系都是**临时的、围绕一次约伴产生的**：约伴请求被接受 → 自动建一个 `Conversation` → 双方能聊天；路线完成后会话 `isReadOnly` 冻结。**没有「持久人际关系」这一层抽象。**

本 PRD 引入**好友系统**——一个双向确认的持久关系层，把「一次性约伴队友」沉淀为「长期连接」，并由此解锁四个闭环能力：

1. **添加好友**：三条路径（约伴会话里加 / 好友码扫码 / Discover 主页直接加），双向确认。
2. **和好友直接约伴**：跳过陌生人的信任门槛，一键发起约伴或邀入招募路线。
3. **持久私信**：好友间一对一会话，永不随路线冻结。
4. **对方主页 + 自己资料**：统一的个人中心，可看好友的只读主页，可编辑自己的头像/昵称/简介/语言/好友码。

**设计哲学**：地图是家，社交不抢戏。好友功能顺着现有 sheet / NavigationStack 架构生长，不加 Tab，全程 FeatureFlag 门控、默认可关、后端不可达时本地可用。

**隐私姿态**（延续 `packages/core/src/user.ts` 的 strict-by-design）：无真实姓名、无真实头像（仅 emoji）、用可轮换好友码而非手机号/邮箱搜索。

---

## 2. Goals

- **G1**：用户能通过三条路径之一，向另一用户发起好友请求并在对方接受后建立持久 `Friendship`。
- **G2**：好友间能一键发起约伴（自由匹配 + 招募路线两种），跳过为陌生人设计的信任摩擦。
- **G3**：好友间能开启持久一对一私信，复用现有 `ChatView` + Supabase Realtime，会话永不冻结。
- **G4**：用户能查看好友的只读个人主页（含信任信号），能编辑自己的个人资料。
- **G5**：全链路在真 Supabase 后端两台模拟器间联调通过；FeatureFlag 关闭时本地不崩、不报错。
- **G6**：好友请求与新私信触发 APNs 远程推送（从零搭建），并保留 app 内未读红点作为兜底。
- **G7**：TS↔Swift schema parity 守护（`pnpm parity:check` 绿）；SwiftData 迁移为轻量、不重写数据。

**衡量口径见 §8 Success Metrics。**

---

## 3. 系统架构总览（各模块如何配合）

```
┌─────────────────────────────────────────────────────────────────────┐
│                          iOS App (SwiftUI)                            │
│                                                                       │
│  CompassMapView (根)                                                  │
│    └─ 右上角头像气泡 ──► MeSheet (个人中心, NavigationStack)          │
│         ├─ MyProfileEditView ───────► CompanionProfile (复用)        │
│         ├─ FriendsListView ─────────► FriendService                 │
│         │    └─ FriendProfileView (只读他人主页)                     │
│         │         ├─[发消息]──► ChatView (复用) ◄── ChatService      │
│         │         ├─[邀约伴]──► SendRequestSheet (复用,预填免门槛)   │
│         │         └─[加好友]──► FriendService.sendRequest            │
│         ├─ AddFriendSheet (好友码/二维码) ──► FriendService          │
│         └─ Messages 列表 (友聊 + 约伴会话统一时间排序)               │
│                                                                       │
│  ┌──────────────────── 服务层 (@MainActor @Observable) ───────────┐  │
│  │ FriendService(新)   CompanionService(现)  ChatService(现)      │  │
│  │     │                     │                    │               │  │
│  │     └─────────┬───────────┴────────┬───────────┘               │  │
│  │               ▼                    ▼                            │  │
│  │       SyncService(现)        SupabaseClient(现)                 │  │
│  │       outbox+30s flush       REST + SDK v2 Realtime            │  │
│  │       增量 pull(LWW)         匿名 auth / Apple link             │  │
│  │               │                    │                            │  │
│  │       NotificationService(现,仅本地) ──► 扩展为远程推送(新)     │  │
│  └────────────────────────────────────────────────────────────────┘  │
│       │                              │                                 │
│  SwiftData(v1.3 新增 2 表)     Keychain(deviceID/anonUserId)          │
└───────┼──────────────────────────────┼───────────────────────────────┘
        │                              │
        ▼                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Supabase 后端                                 │
│  新增表: friend_requests / friendships / friend_codes /              │
│          device_push_tokens                                          │
│  改造表: conversations.request_id → nullable; +type=friendDirect     │
│  新增 Edge Function: friend-request-notify / message-notify /        │
│                      redeem-friend-code                              │
│  复用: companion-discover / chat-proxy                              │
│  APNs gateway (Edge Function → Apple Push)  ◄── 零基础新建            │
│  RLS: 仅关系双方可读写; friend_codes 单向兑换                        │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.1 模块职责边界（谁管什么）

| 模块                     | 职责                                                                       | 复用/新建                                     |
| ------------------------ | -------------------------------------------------------------------------- | --------------------------------------------- |
| `FriendService`          | 好友关系 CRUD：发/收/接受/拒绝/撤回请求、列好友、拉黑连带解友、好友码兑换  | **新建**（对齐 `CompanionService` 写法）      |
| `FriendshipStateMachine` | 纯函数状态机：`[none]→pending→accepted→blocked` + 双向 pending 折叠        | **新建**（对齐 `RouteCompanionStateMachine`） |
| `CompanionService`       | 约伴请求/发现/招募（现有），好友只是给它喂「预填 + 免门槛」参数            | **复用，零侵入**                              |
| `ChatService`            | 收发消息 + Realtime 订阅，好友私信复用，唯一差别是会话 `friendDirect` 类型 | **复用**                                      |
| `SyncService`            | outbox 入队 + 30s flush + 增量 pull，好友表接入同样管线                    | **复用**                                      |
| `SupabaseClient`         | REST + SDK v2 Realtime + 匿名/Apple auth                                   | **复用**                                      |
| `NotificationService`    | 现仅本地通知（地理围栏），扩展为支持远程推送 payload 落地                  | **扩展**                                      |
| `PushTokenService`       | 注册 APNs、上报 device token、token 轮换                                   | **新建（零基础）**                            |
| `CompanionProfile`       | 资料载体（emoji/bio/languages），好友资料完全复用，不另起表                | **复用**                                      |

### 3.2 关键数据流（端到端时序）

**流 A — 发好友请求 → 对方接受 → 建立 Friendship：**

```
A: FriendService.sendRequest(to:B, source:.friendCode, note:)
   → 本地落 FriendRequestRecord(pending) → SyncService.enqueue("friend_requests", upsert)
   → 30s flush → SupabaseClient.post("friend_requests")
   → Edge Function friend-request-notify → APNs 推 B
B: 收到推送/红点 → FriendsListView 收件箱 → accept
   → FriendService.accept(requestId)
   → 状态机 transition(pending, accept) = accepted
   → 本地落 FriendshipRecord(有序对) + 改 request 状态
   → enqueue("friendships", upsert) + enqueue("friend_requests", upsert)
   → 后端 upsert friendships(唯一约束 user_low,user_high)
A: 下次 pull friend_requests/friendships → 看到 accepted → UI 出现新好友
```

**流 B — 好友 → 发消息（懒建会话）：**

```
点好友主页[发消息]
  → Friendship.conversationId 已存在? → 直接打开 ChatView(conversationId)
  → 不存在 → FriendService.openDirectConversation(friendship)
              → 建 Conversation(type:.friendDirect, requestId:nil,
                                 participantIds:[A,B], isReadOnly:false)
              → enqueue("conversations", upsert)
              → 回写 Friendship.conversationId
              → 打开 ChatView → ChatService 订阅 Realtime channel
发消息 → ChatService.send(text) → post("chat_messages")
       → Edge Function message-notify → APNs 推对方
```

**流 C — 好友 → 邀约伴（复用约伴，免门槛）：**

```
好友主页[邀他约伴]
  → SendRequestSheet(recipientPrefilled:B, source:.friend, skipTrustGate:true)
  → CompanionService.sendRequest(...)  ← 既有逻辑,仅参数不同
  → 接受后既有逻辑自动建 oneOnOne Conversation (这条仍带 requestId)
```

---

## 4. User Stories

> 颗粒：每个 story 一个聚焦 session 可完成。带 UI 的均要求模拟器实机验证（项目规则：`#Preview` 不足，需 `xcodebuild build` + Simulator 截图/XCTest ImageRenderer）。
> 命名：`FRD` 前缀（Friends），与既有 companion US 区分。

### Phase 1 — 关系地基 + 个人主页

#### FRD-001：core 契约 `friend.ts` + parity 守护

**Description:** As a developer, I need the friend data contract defined in `packages/core` so TS and Swift stay in sync.

**Acceptance Criteria:**

- [ ] 新建 `packages/core/src/friend.ts`：`FriendshipId`(`fnd_*`)、`FriendRequestId`(`freq_*`)、`FriendCode`、`FriendRequestStatus`、`FriendRequestSource`、`FriendRequest`、`Friendship`（字段同 `docs/FRIENDS_DESIGN.md §2.2`）
- [ ] 从 `packages/core/src/index.ts`（或既有 barrel）导出
- [ ] `pnpm typecheck` 通过（strict + noUncheckedIndexedAccess 不放松）
- [ ] `pnpm parity:check` 把新类型纳入守护（若 parity 脚本需登记，登记之）

#### FRD-002：Swift 模型镜像 `FriendRequest` / `Friendship`

**Description:** As an iOS developer, I need Swift structs mirroring the core contract.

**Acceptance Criteria:**

- [ ] 新建 `Models/FriendRequest.swift`、`Models/Friendship.swift`，写法对齐 `Models/Conversation.swift`（`RawRepresentable` ID、`Codable`、自定义 decoder 用 `decodeIfPresent` 容错、`CaseIterable` 枚举）
- [ ] `Friendship` 加 `otherUserId(viewer:)` 便利方法；加 `static let sample` 供预览
- [ ] `pnpm parity:check` 绿（TS↔Swift 字段一致）
- [ ] `xcodebuild build` 通过

#### FRD-003：SwiftData v1.3 迁移（新增两表）

**Description:** As a developer, I need persistent storage for friendships and requests.

**Acceptance Criteria:**

- [ ] 新建 `Persistence/Models/FriendshipRecord.swift`、`FriendRequestRecord.swift`（`@Model`，数组用 blob，对齐既有 Record 惯例；提供 `asValue`/`init(from:)` 映射）
- [ ] 新增 `SoloCompassSchemaV1_3`，models 列表追加两表
- [ ] `SoloCompassMigrationPlan.stages` 追加 `.lightweight(v1_2 → v1_3)`
- [ ] `SoloCompassModelContainer.shared` 与 `makeInMemory()` 两处 `ModelContainer(for:)` 追加两表
- [ ] 旧库（v1.2）能无损升级到 v1.3（手动验证：装旧版数据后跑新版不崩、原数据在）
- [ ] **不**显式传 `migrationPlan:`（遵循现有注释规避 `NSLightweightMigrationStage` boot 崩溃）
- [ ] `xcodebuild build` + `xcodebuild test` 通过

#### FRD-004：`FriendshipStateMachine` 纯函数 + 单测

**Description:** As a developer, I need a pure state machine governing relationship transitions so logic is testable and consistent across local & backend.

**Acceptance Criteria:**

- [ ] 新建 `Services/FriendshipStateMachine.swift`：`transition(state, event) -> state`（对齐 `RouteCompanionStateMachine`）
- [ ] 事件覆盖：sendRequest / accept / decline / withdraw / expire / block / unblock
- [ ] 实现「双向 pending 折叠 → 自动 accepted」「已是好友再发 = no-op」「被拉黑发请求 = 静默不入队」三条规则
- [ ] 单测覆盖全部合法/非法转移（`Tests/FriendshipStateMachineTests.swift`），含边界（自己加自己拒绝、重复 accept 幂等）
- [ ] `xcodebuild test` 全绿（注意：跑真实套件名，避免 0 用例假绿）

#### FRD-005：`FriendService` 核心

**Description:** As a developer, I need a service orchestrating friend operations against local store + sync outbox.

**Acceptance Criteria:**

- [ ] 新建 `Services/FriendService.swift`（`@MainActor @Observable final class`，对齐 `CompanionService`）
- [ ] 方法：`sendRequest(to:source:note:)`、`accept(_:)`、`decline(_:)`、`withdraw(_:)`、`listFriends()`、`incomingRequests()`、`outgoingRequests()`、`unfriend(_:)`
- [ ] 每个写操作：先落本地 Record → `SyncService.enqueue(...)`（表名 `friend_requests`/`friendships`）
- [ ] 全方法由 `FeatureFlags.companion`（或新增 `FF_FRIENDS`）门控；flag 关时返回空成功，不报错（本地优先不变）
- [ ] 拉黑连带：`unfriend` + 写 `CompanionBlock`（复用既有 block 表）
- [ ] `xcodebuild build` 通过

#### FRD-006：后端 migration `00XX_friends.sql`（建表 + RLS）

**Description:** As a developer, I need backend tables with RLS so friend data is secure.

**Acceptance Criteria:**

- [ ] 新建 `infra/supabase/migrations/00XX_friends.sql`，建 `friend_requests`、`friendships`、`friend_codes`（列见 §6.1）
- [ ] `friendships` 加唯一约束 `(user_low_id, user_high_id)`
- [ ] RLS：请求仅收发双方可读、recipient 可改 status；friendship 仅两端可读
- [ ] 复用 `sc_touch_updated_at()` 触发器维护 `updated_at`
- [ ] 在本地 Supabase（或 staging）apply migration 成功，RLS policy 用两个测试账号验证隔离

#### FRD-007：`MeSheet` 个人中心骨架 + 地图头像入口

**Description:** As a user, I want a personal hub reachable from the map so I have one place for my profile and social.

**Acceptance Criteria:**

- [ ] 地图右上角新增 emoji 头像气泡按钮，放安全区 overlay（避开状态栏，参考既有 mapcontrols 安全区坑）
- [ ] 点击 present `MeSheet`（NavigationStack），含 ProfileHeader + Friends/Messages/Companion/Settings 入口区块
- [ ] 头像气泡显示当前用户 emoji；有待处理好友请求时显示红点
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**：截图确认气泡位置不撞 chrome、sheet 正常弹出

#### FRD-008：`MyProfileEditView`（升级现有资料编辑）

**Description:** As a user, I want to edit my avatar, handle, bio, and languages in one place.

**Acceptance Criteria:**

- [ ] 基于现有 `CompanionProfileView` 升级/抽取：emoji 选择器、bio（≤280）、语言多选保留
- [ ] 新增 `displayHandle` 编辑（不要求唯一，长度 2–20）
- [ ] 保存写 `CompanionProfile` + `User.displayHandle`，走 sync outbox
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**：改昵称/emoji 后重进 sheet 仍在

#### FRD-009：`FriendProfileView` 只读他人主页

**Description:** As a user, I want to view another user's profile so I can decide to add/invite/message them.

**Acceptance Criteria:**

- [ ] 复用 `CompanionProfileView` 展示布局（大号 emoji 圆形渐变底、handle、bio、languages 带旗帜）
- [ ] 信任信号 stat 行：走过 N 地 / 拼团 N 次 / 好友 N（数据源沿用既有「走过路线」展示 + 新增好友计数）
- [ ] 底部固定行动 dock，让出 `sheetPeekClearance`（参考既有 peek 让位规范）
- [ ] 行动条按关系态切换：非好友=[加为好友]；好友=[发消息][邀他约伴]
- [ ] 颜色用 `CT.*` 固定浅色体系（注意固定白底别盲改语义色）
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**：两种关系态行动条都正确渲染

#### FRD-010：`FriendsListView` 好友列表 + 收件箱

**Description:** As a user, I want to see my friends and pending requests in one list.

**Acceptance Criteria:**

- [ ] 结构对齐 `MyRequestsListView`/`RequestInboxView`
- [ ] 顶部「待处理请求」分区（incoming），每条可 [接受]/[拒绝]
- [ ] 下方好友列表（横向头像条 + 列表），点击进 `FriendProfileView`
- [ ] 空态文案（无好友 / 无请求）
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**

#### FRD-011：Phase 1 真后端联调（两模拟器）

**Description:** As a QA, I need to verify the request→accept→friendship loop against real Supabase.

**Acceptance Criteria:**

- [ ] 开启 `FF_BACKEND_SYNC` + `FF_FRIENDS`，两台模拟器分别匿名登录（不同 userId）
- [ ] 模拟器 A 发请求 → B pull 到 incoming → B accept → A pull 到 accepted → 双方 `FriendsListView` 互见
- [ ] 后端 `friendships` 表确有一行（有序对、唯一约束未冲突）
- [ ] flag 关闭时同一流程本地不崩、不报错（local-first 回归）
- [ ] 记录联调步骤到 `docs/qa/`（供回归）

### Phase 2 — 三条发现路径 + 持久私信

#### FRD-012：`Conversation` 改造（requestId 可选 + friendDirect）

**Description:** As a developer, I need conversations that aren't tied to a companion request so friends can DM directly.

**Acceptance Criteria:**

- [ ] `friend.ts`/`companion.ts` 中 `Conversation.requestId` 改为可选；`ConversationType` 加 `friendDirect`
- [ ] Swift `Conversation.swift` 同步（`requestId: CompanionRequestId?`，decoder `decodeIfPresent`）
- [ ] `ConversationRecord` 的 `request_id` 列改可选（轻量迁移，纳入 v1.3 或 v1.4）
- [ ] 后端 `conversations.request_id` 改 nullable（migration）
- [ ] `friendDirect` 会话 `isReadOnly` 恒 false
- [ ] `pnpm parity:check` 绿；`xcodebuild test` 绿；既有约伴会话回归不破

#### FRD-013：好友「发消息」懒建会话 → ChatView

**Description:** As a user, I want to message a friend directly so we keep a persistent thread.

**Acceptance Criteria:**

- [ ] `FriendProfileView` [发消息]：有 `conversationId` 直接开 `ChatView`；无则 `FriendService.openDirectConversation` 懒建 `friendDirect` 会话并回写 `Friendship.conversationId`
- [ ] 复用 `ChatView` + `ChatService`：不显示路线卡片头部；菜单「举报/拉黑」连带解友
- [ ] 发送/接收走既有 Realtime channel（`chat:<convId>`）
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**：两模拟器好友互发消息实时到达

#### FRD-014：`AddFriendSheet` — 我的好友码 + 二维码展示

**Description:** As a user, I want a shareable friend code/QR so others can add me.

**Acceptance Criteria:**

- [ ] `AddFriendSheet` 顶部展示我的好友码 `SOLO-XXXX-XXXX`（去除 0/O/1/I 易混字符）+ `CoreImage` 生成二维码
- [ ] 好友码可长按复制 / 分享（`ShareLink`）
- [ ] 好友码映射存后端 `friend_codes`（code→userId），首次进入懒生成
- [ ] [换一个] 按钮：轮换好友码（旧码 `revoked_at` 置时间，失效）
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**：二维码渲染、复制可用

#### FRD-015：`AddFriendSheet` — 扫码 / 输码加人

**Description:** As a user, I want to add someone by scanning their QR or typing their code.

**Acceptance Criteria:**

- [ ] [扫一扫]：`AVFoundation` 相机扫二维码（含相机权限文案，`NSCameraUsageDescription`）
- [ ] [输入码]：手动输入 `SOLO-XXXX-XXXX`，格式校验 + 自动大写/去空格
- [ ] 解析出 code → Edge Function `redeem-friend-code` → 返回 userId → 拉 `FriendProfileView` 预览 → 确认发 `FriendRequest(source:.friendCode)`
- [ ] 无效/已撤销码：友好错误提示，不暴露后端细节
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**（扫码可用模拟器粘贴码 fallback）

#### FRD-016：约伴会话/路线群聊「+加好友」

**Description:** As a user, I want to add someone I met through a companion activity as a friend.

**Acceptance Criteria:**

- [ ] `ChatView`（约伴 oneOnOne）参与者旁 [加为好友] 按钮 → `sendRequest(source:.companionChat)`
- [ ] 路线群聊参与者列表每人 [加为好友] → `sendRequest(source:.routeGroup)`
- [ ] 已是好友/已发请求时按钮态变（已好友/待确认）
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**

#### FRD-017：Discover 主页「加好友」入口（受信任门槛）

**Description:** As a user, I want to add a stranger from discovery as a friend (with anti-abuse guardrails).

**Acceptance Criteria:**

- [ ] `DiscoverListView` 帖子详情 [加为好友] → `sendRequest(source:.discover)`
- [ ] `discover` 来源受 `reporterWeight ≥ 0.3` 门槛 + 频率限制（前端预检 + 后端兜底）
- [ ] 请求 note 限长 120
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**

#### FRD-018：`MeSheet` 统一会话列表

**Description:** As a user, I want all my conversations (friend DMs + companion chats) in one time-sorted list.

**Acceptance Criteria:**

- [ ] Messages 区块列出 `friendDirect` + `oneOnOne` + `groupRoute` 会话，按 `lastMessageAt` 降序
- [ ] 每行显示对方 emoji/handle（群聊显示路线名）+ 最后消息预览 + 未读红点
- [ ] 点击进对应 `ChatView`
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**

#### FRD-019：好友请求 Realtime（不刷新即见）

**Description:** As a user, I want to see new friend requests without manual refresh.

**Acceptance Criteria:**

- [ ] `FriendService` 订阅 `friend_requests` Realtime channel（filter `recipient_id=eq.<me>`），新请求实时进收件箱
- [ ] RLS policy 允许 recipient 订阅自己的请求行
- [ ] 收件箱红点实时更新
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**：A 发请求，B 不刷新即见红点

### Phase 3 — 好友约伴打通 + APNs 推送 + 后端硬化

#### FRD-020：好友主页「邀他约伴」（自由匹配，免门槛）

**Description:** As a user, I want to invite a friend to hang out, skipping stranger-friction.

**Acceptance Criteria:**

- [ ] `FriendProfileView` [邀他约伴] → `SendRequestSheet`，recipient 预填、`source=friend`、跳过 reporterWeight 门槛与安全同意
- [ ] 接受后走既有约伴接受逻辑（建 oneOnOne 会话，仍带 requestId）
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**

#### FRD-021：招募路线「邀请好友加入」（免审批）

**Description:** As a route host, I want to invite friends straight into my recruiting route.

**Acceptance Criteria:**

- [ ] `MyHostedRoutesListView`/`RouteDetailView`(host 视角) 新增 [邀请好友] → 选好友 → 直接进 `confirmedMembers`（免审批，决议 D-3）
- [ ] host 仅控制「邀不邀」；好友收到入群通知
- [ ] 陌生人 `JoinRouteRequestSheet` 审批流不变
- [ ] 群聊参与者更新 + Realtime 同步
- [ ] `xcodebuild build` 通过；**Simulator 实机验证**

#### FRD-022：APNs 基础设施（证书 + 注册 + token 上报）

**Description:** As a developer, I need the app registered for remote push so we can notify users.

**Acceptance Criteria:**

- [ ] Apple Developer 配置 APNs key/证书；`project.yml` 加 `aps-environment` entitlement，`xcodegen` 重生工程
- [ ] 新建 `Services/PushTokenService.swift`：`registerForRemoteNotifications()`、`didRegister(deviceToken)` 回调上报后端
- [ ] 新建后端 `device_push_tokens` 表（user_id, token, device_id, platform, updated_at）+ migration + RLS（仅自己可写）
- [ ] token 变更/失效轮换：重复上报 upsert；APNs 反馈失效则删除
- [ ] 推送权限请求文案（首次合适时机请求，非冷启动打扰）
- [ ] `xcodebuild build` 通过；真机或模拟器（iOS 16+ 模拟器支持 APNs）验证 token 上报

#### FRD-023：`friend-request-notify` Edge Function → APNs

**Description:** As a user, I want a push notification when someone sends me a friend request.

**Acceptance Criteria:**

- [ ] 新建 Edge Function `infra/supabase/functions/friend-request-notify`：入参 `{ requestId }` + JWT，查 recipient token，发 APNs
- [ ] payload schema：`{ type:"friend_request", requesterHandle, requesterEmoji, requestId }`
- [ ] 触发：`FriendService.sendRequest` 成功后调用，或 DB trigger + pg_net 异步
- [ ] `NotificationService` 扩展：远程 payload 落地为可点击通知 → 深链到收件箱
- [ ] 部署 `supabase functions deploy friend-request-notify`；两账号验证收到推送

#### FRD-024：`message-notify` Edge Function → APNs

**Description:** As a user, I want a push when a friend messages me while app is backgrounded.

**Acceptance Criteria:**

- [ ] 新建 Edge Function `message-notify`：聊天消息后触发，查会话对端 token，发 APNs
- [ ] payload：`{ type:"message", conversationId, senderHandle, preview }`（preview 截断，隐私）
- [ ] 自己发的不推自己；会话静音（可选，后续）
- [ ] 点击通知深链到对应 `ChatView`
- [ ] 部署；验证后台收到消息推送并能跳转

#### FRD-025：后端硬化 — 频率限制 + 请求过期清理

**Description:** As a platform owner, I need anti-abuse and data hygiene on friend operations.

**Acceptance Criteria:**

- [ ] Edge Function 或 DB 层：每用户每日好友请求上限（如 50），超限 429
- [ ] `discover` 来源额外受 reporterWeight 门槛（后端二次校验，不信前端）
- [ ] 请求过期：`expiresAt`（创建 +14d）到点的 pending 置 `expired`（定时任务，沿用 `cleanupStaleRequests` 模式）
- [ ] 拉黑后双方互不可发请求、互不可见（复用 `CompanionBlock` 过滤，后端 RLS/Edge 强制）
- [ ] 单测/集成测覆盖限流与过期边界

#### FRD-026：好友码轮换 + `redeem-friend-code` 硬化

**Description:** As a user, I want my friend code rotatable so a leaked code can be invalidated.

**Acceptance Criteria:**

- [ ] `redeem-friend-code` Edge Function：code → userId，拒绝已 `revoked_at` 的码
- [ ] 轮换时旧码立即失效，新码生效；并发兑换幂等
- [ ] code 不可反查（给 userId 查不到 code），防枚举
- [ ] 部署 + 验证撤销码兑换失败

#### FRD-027：端到端闭环回归

**Description:** As QA, I need the full friend→companion→chat→upgrade loop verified end-to-end.

**Acceptance Criteria:**

- [ ] 两模拟器走完整闭环：扫码加好友 → 好友邀约伴 → 约伴成功建群聊 → 群里另一人「+加好友」→ 互升级好友 → 私信 + 推送到达
- [ ] flag 全开真后端通过；flag 全关本地不崩
- [ ] 回归脚本/清单落 `docs/qa/`
- [ ] 关键路径无 P0/P1 缺陷

---

## 5. Functional Requirements（编号、无歧义）

### 关系与状态

- **FR-1**：系统必须支持向另一用户发起好友请求，携带 `source`（companion_chat / route_group / friend_code / discover）与可选 `note`（≤120 字符）。
- **FR-2**：好友请求状态机为 `pending → accepted | declined | withdrawn | expired`；`Friendship` 在 accept 时落地。
- **FR-3**：当 A 对 B 已 pending、B 又对 A 发请求时，系统必须自动判定为双向同意并直接置 `accepted`（双向 pending 折叠）。
- **FR-4**：对已是好友的对象再次发请求必须是 no-op，返回现有 `Friendship`，不产生重复行。
- **FR-5**：`Friendship` 必须以有序对 `(userLowId, userHighId)` 唯一存储，后端唯一约束保证一对仅一行。
- **FR-6**：pending 请求在创建 14 天后必须自动过期为 `expired`。
- **FR-7**：拉黑必须连带软删 `Friendship` 并写入 `CompanionBlock`；被拉黑方对拉黑方不可见、不可发请求；发请求时静默成功不泄露拉黑状态。

### 约伴打通

- **FR-8**：好友主页「邀他约伴」必须复用 `SendRequestSheet`，预填 recipient、`source=friend`，并跳过 reporterWeight 门槛与安全同意。
- **FR-9**：招募路线 host「邀请好友加入」必须把好友直接置入 `confirmedMembers`（免审批）；陌生人审批流不变。
- **FR-10**：好友约伴接受后必须沿用既有约伴会话创建逻辑（oneOnOne，带 requestId）。

### 私信

- **FR-11**：`Conversation.requestId` 必须改为可选，`ConversationType` 必须新增 `friendDirect`。
- **FR-12**：好友「发消息」必须懒创建 `friendDirect` 会话（`requestId=nil`、`isReadOnly=false`）并回写 `Friendship.conversationId`；已存在则直接打开。
- **FR-13**：`friendDirect` 会话必须永不进入 `isReadOnly` 冻结态。
- **FR-14**：私信必须复用 `ChatView` + `ChatService` + Supabase Realtime，不新建聊天 UI/传输栈。

### 资料与主页

- **FR-15**：用户必须能在 `MyProfileEditView` 编辑 emoji 头像、`displayHandle`（2–20）、bio（≤280）、languages。
- **FR-16**：`FriendProfileView` 必须以只读方式展示对方资料 + 信任信号（走过 N 地 / 拼团 N 次 / 好友 N），并按关系态切换行动条。
- **FR-17**：个人中心入口必须是地图右上角 emoji 头像气泡，放安全区 overlay，待处理请求时显示红点。

### 好友码

- **FR-18**：每用户必须有可展示的好友码 `SOLO-XXXX-XXXX`（排除 0/O/1/I）及对应二维码。
- **FR-19**：好友码必须可轮换；轮换后旧码立即失效（`revoked_at`）。
- **FR-20**：兑换好友码必须经 `redeem-friend-code` Edge Function，拒绝已撤销码，且 code 不可被 userId 反查。

### 推送

- **FR-21**：app 必须注册 APNs 并上报 device token 到 `device_push_tokens`，支持 token 轮换与失效清理。
- **FR-22**：新好友请求必须触发 `friend-request-notify` 推送；新私信（对端后台）必须触发 `message-notify` 推送。
- **FR-23**：所有推送必须有 app 内未读红点/列表提醒作为兜底（推送失败或权限关闭时仍可感知）。
- **FR-24**：点击推送必须深链到对应界面（收件箱 / ChatView）。

### 跨切面

- **FR-25**：好友所有功能必须由 FeatureFlag 门控；flag 关闭时本地不崩、不报错、不阻塞 UI（local-first 不变）。
- **FR-26**：所有写操作必须经 `SyncService` outbox 入队，30s flush + 前台唤醒 flush；读经增量 pull（LWW 合并）。
- **FR-27**：所有新表必须开 RLS，仅关系参与方可读写；`friend_codes` 仅单向兑换。
- **FR-28**：TS↔Swift schema 必须通过 `pnpm parity:check`；SwiftData 迁移必须为轻量、不重写既有数据。

---

## 6. 后端详细设计（技术附录）

> 摸底结论（来自现有代码）：`infra/supabase/` 真实存在，含 migrations（`0001_init.sql`/`0003_companion.sql`/`0004`/`0005`）与 4 个 Edge Functions（`companion-discover`/`chat-proxy`/`synthesize-experiences`/`enrich-user-experience`）。表结构 + RLS + `sc_touch_updated_at()` 触发器范式已立。本节新增内容**严格对齐既有范式**。

### 6.1 新增表 DDL（示意，最终以 migration 为准）

```sql
-- friend_requests：好友请求
create table public.friend_requests (
  id            text primary key,                 -- freq_*
  requester_id  uuid not null references auth.users(id),
  recipient_id  uuid not null references auth.users(id),
  status        text not null default 'pending'   -- pending|accepted|declined|withdrawn|expired
                check (status in ('pending','accepted','declined','withdrawn','expired')),
  source        text not null                     -- companion_chat|route_group|friend_code|discover
                check (source in ('companion_chat','route_group','friend_code','discover')),
  note          text check (char_length(note) <= 120),
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (requester_id <> recipient_id)
);
create index on public.friend_requests (recipient_id, status);
create index on public.friend_requests (requester_id, status);

-- friendships：好友关系（有序对，唯一）
create table public.friendships (
  id              text primary key,               -- fnd_*
  user_low_id     uuid not null references auth.users(id),
  user_high_id    uuid not null references auth.users(id),
  initiated_by    uuid not null references auth.users(id),
  conversation_id text references public.conversations(id),
  accepted_at     timestamptz not null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  check (user_low_id < user_high_id),
  unique (user_low_id, user_high_id)
);

-- friend_codes：可轮换好友码
create table public.friend_codes (
  code        text primary key,                   -- SOLO-XXXX-XXXX
  user_id     uuid not null references auth.users(id),
  revoked_at  timestamptz,
  created_at  timestamptz not null default now()
);
create index on public.friend_codes (user_id) where revoked_at is null;

-- device_push_tokens：APNs token
create table public.device_push_tokens (
  user_id    uuid not null references auth.users(id),
  device_id  text not null,
  token      text not null,
  platform   text not null default 'ios',
  updated_at timestamptz not null default now(),
  primary key (user_id, device_id)
);

-- conversations 改造：request_id 可选 + 允许 friendDirect
alter table public.conversations alter column request_id drop not null;
-- (type 列若已存在则放宽 check 含 'friendDirect'，否则在应用层处理)
```

### 6.2 RLS 策略要点

| 表                   | SELECT                                                              | INSERT                      | UPDATE/DELETE                                |
| -------------------- | ------------------------------------------------------------------- | --------------------------- | -------------------------------------------- |
| `friend_requests`    | `auth.uid() in (requester_id, recipient_id)`                        | `auth.uid() = requester_id` | recipient 可改 status；requester 可 withdraw |
| `friendships`        | `auth.uid() in (user_low_id, user_high_id)`                         | service / 经校验的 Edge     | 两端可软删                                   |
| `friend_codes`       | 仅 `auth.uid() = user_id` 可查自己的码；兑换走 Edge（service role） | `auth.uid() = user_id`      | 自己可 revoke                                |
| `device_push_tokens` | `auth.uid() = user_id`                                              | `auth.uid() = user_id`      | 自己 upsert/delete                           |

> 兑换好友码**不暴露 friend_codes 给任意用户直查**（防枚举），统一经 `redeem-friend-code` Edge Function 用 service role 查。

### 6.3 Edge Functions（新增 3 个）

| Function                | 入参                                  | 出参                                     | 触发                            | 复用既有                             |
| ----------------------- | ------------------------------------- | ---------------------------------------- | ------------------------------- | ------------------------------------ |
| `redeem-friend-code`    | `{ code }` + JWT                      | `{ userId, handle, avatarEmoji }` 或 404 | 输码/扫码加人                   | auth 校验范式同 `companion-discover` |
| `friend-request-notify` | `{ requestId }` + JWT                 | `{ sent, recipientId }`                  | sendRequest 成功后 / DB trigger | 部署范式同既有 functions             |
| `message-notify`        | `{ messageId }` 或 DB trigger payload | `{ sent }`                               | chat_messages insert            | 可挂 DB trigger + pg_net             |

**APNs 发送**（零基础新建）：Edge Function 内用 APNs token-based auth（.p8 key），查 `device_push_tokens` → 调 Apple `api.push.apple.com`。key/teamId/keyId 存 Supabase secrets。

### 6.4 同步管线接入（复用 `SyncService`）

| 表                            | enqueue（写）             | pull（读，增量 LWW）           | Realtime                         |
| ----------------------------- | ------------------------- | ------------------------------ | -------------------------------- |
| `friend_requests`             | ✅ upsert                 | ✅ `updated_at > lastPulledAt` | ✅ filter `recipient_id=eq.<me>` |
| `friendships`                 | ✅ upsert                 | ✅                             | （可选）                         |
| `friend_codes`                | 经 Edge，不走 outbox      | 自己的码可 pull                | —                                |
| `conversations`(friendDirect) | ✅ upsert                 | ✅（已接入）                   | —                                |
| `chat_messages`               | ✅（已接入 ChatService）  | ✅（已接入）                   | ✅（已接入 `chat:<convId>`）     |
| `device_push_tokens`          | ✅ upsert（token 变更时） | —                              | —                                |

`lastPulledAt` 游标键沿用 `sc.sync.lastPulledAt.<table>`（UserDefaults）。

---

## 7. Design Considerations（UI/UX 与复用）

- **入口**：地图右上角 emoji 头像气泡（决议 D-1），安全区 overlay，避开 mapControls 与状态栏碰撞。
- **个人主页（FriendProfileView）**：大号 emoji 圆形渐变底；信任信号 stat 行是灵魂（「身份由你体验过什么定义」）；底部固定行动 dock 让出 `sheetPeekClearance`；`CT.*` 固定浅色卡片（勿盲改语义色）。ASCII 草图见 `docs/FRIENDS_DESIGN.md §5.3`。
- **添加好友（AddFriendSheet）**：二维码 + 文字码并列，扫一扫/输入码双入口。草图见 `docs/FRIENDS_DESIGN.md §5.4`。
- **复用清单**：`CompanionProfileView`（资料展示）、`SendRequestSheet`（约伴发起）、`ChatView`/`ChatService`（私信）、`MyRequestsListView`/`RequestInboxView`（列表结构）、`CompanionBlock`（拉黑）。
- **本地化**：所有用户串经 `NSLocalizedString`，中英双写 `en.lproj`/`zh-Hans.lproj`，key 前缀 `friend.*`。
- **视觉验证**：所有 UI story 必须 `xcodebuild build` + Simulator 实机截图/XCTest ImageRenderer 验证（`#Preview` 不足）。

---

## 8. Success Metrics

- **M1（功能完整）**：三期 27 个 story 全部验收通过；端到端闭环（FRD-027）无 P0/P1。
- **M2（联调）**：真 Supabase 两模拟器跑通「请求→接受→好友→约伴→群聊→升级→私信→推送」全链路。
- **M3（本地优先回归）**：flag 全关时，好友相关界面与既有约伴/地图功能零崩溃、零报错。
- **M4（parity & 迁移）**：`pnpm parity:check` 绿；v1.2→v1.3 迁移无数据丢失。
- **M5（推送达成率）**：好友请求/新私信推送在权限开启时到达率 ≥ 95%（联调样本）。
- **M6（克制感）**：社交功能不改变「地图是家」的默认体验——未启用好友 flag 的用户主流程无任何变化。

---

## 9. Non-Goals（明确不做）

- ❌ **不做单向关注/粉丝**：好友是双向确认（决议已定），不引入 follow 语义。
- ❌ **不做手机号/邮箱搜人**：仅好友码 + 既有约伴交集 + Discover，保护隐私姿态。
- ❌ **不做真实头像/照片上传**：仍只 emoji 头像。
- ❌ **不做好友数上限**（决议 D-4）；克制感靠双向确认 + flag 默认可关实现。
- ❌ **不做群聊邀请陌生人**：群聊仍锚定路线，本 PRD 只在群里加「升级为好友」。
- ❌ **不做消息撤回/编辑/已读回执升级**：复用现有 `ChatMessage` 能力，不扩展。
- ❌ **不做好友分组/标签/备注名**：MVP 不含，留后续。
- ❌ **不做 Android/Web 端**：本 PRD 仅 iOS + 后端；core 契约为未来端预留但不实现 UI。
- ❌ **不替换约伴系统**：约伴（companion）独立存在，好友只与之打通。

---

## 10. Technical Considerations（约束与依赖）

- **依赖既有基础设施**：`SupabaseClient`（REST + SDK v2 Realtime）、`SyncService`（outbox + 增量 pull）、`ChatService`（Realtime chat）、`DeviceIdentityService`（匿名 auth + Keychain）、`FeatureFlags`（plist + env）。均复用，不重写。
- **APNs 是唯一从零栈**：证书/entitlement/token 注册/Edge→Apple gateway 全新建；务必先打通 FRD-022 再做 FRD-023/024。
- **`Conversation.requestId` 改可选是阻塞性前置**：FRD-012 必须先于 FRD-013（私信）。
- **迁移纪律**：遵循 `SoloCompassModelContainer.swift` 既有注释——`shared` 不显式传 `migrationPlan:`，靠 SwiftData 隐式轻量迁移，避免 boot 崩溃。
- **测试纪律**：iOS 测试用真实套件名跑（避免 `-only-testing` 跑 0 用例假绿）；新测试 `.swift` 文件必须 `xcodegen` 后才纳入；main 测试基线本就有若干已知红，判断回归须切 main 对比。
- **Simulator 纪律**：后台启动模拟器，勿占前台终端；自动点击在当前 Xcode/iOS 版本不可靠，验证以 `simctl screenshot` + XCTest 为主。
- **parity**：改 `packages/core` schema 后建议跑 `pnpm parity:check`，确保 Swift 镜像不漂移。

---

## 11. Open Questions（实施期需确认）

1. **FeatureFlag 复用 vs 新增**：好友是复用 `FF_COMPANION` 还是新增 `FF_FRIENDS`？建议新增，便于独立灰度（但要在 plist + env 两处登记）。
2. **APNs 环境**：beta 用 development APNs，正式用 production；CI/TestFlight 的 entitlement 切换怎么管？
3. **消息推送触发位置**：`ChatService.send()` 成功后 app 端调 Edge，还是 DB trigger + pg_net 异步？后者更可靠但需 `pg_net` 扩展可用性确认。
4. **信任信号「好友 N」是否公开**：对方主页是否展示好友数？可能引发攀比，需产品权衡（默认展示，可后续关）。
5. **Discover 加好友的频率上限具体值**：每日 50 是占位，需结合反骚扰数据定。
6. **好友码格式长度**：`SOLO-XXXX-XXXX`（8 位有效字符，去混淆字符后约 32^8 空间）是否够防枚举？或加校验位。

```

```
