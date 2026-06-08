# 好友系统设计方案（Friends & Social Graph）

> 状态：定稿 v1.1 · 方向已确认，可执行
> 作者：Claude（基于现状代码深度探索）
> 日期：2026-06-08

---

## 0. 一句话

把当前「围绕一次约伴临时产生的关系」升级为「持久的双向好友连接」，让 **加好友 → 直接约伴 → 持久私信 → 看完整主页** 串成闭环；底层最大化复用已落地的 `Conversation`/`CompanionProfile`/`Route` 资产，只补「关系层」这一块缺口。

---

## 1. 为什么这是「补一层」而非「从零造」

探索结论：这个 app **不是纯本地工具，而是已实现得相当完整的社交雏形**。下表是现状盘点 —— 你想要的四件事，地基几乎都在：

| 诉求 | 现状 | 缺口 |
| --- | --- | --- |
| 添加好友 | ❌ 无「好友」概念，关系都是一次性的 | **新建关系层** |
| 和好友约伴 | ✅ 两套约伴系统已完整：自由匹配 `CompanionPost/Request`、路线拼团 `Route/RouteCompanion/JoinRequest` | 缺「从好友一键发起」捷径 |
| 约伴后发消息 | ✅ `Conversation`(oneOnOne/groupRoute) + `ChatMessage` + `ChatView` + Supabase Realtime 全有 | 缺「无约伴前提的主动私信」入口；`Conversation.requestId` 是**必填**，挡住了好友直聊 |
| 对方主页 | ✅ `CompanionProfileView` 有头像 emoji/bio/语言/走过的路线 | 它是「我的档案编辑器」，缺「看别人的只读主页」 |
| 配置个人信息 | ✅ Settings → Companion → Profile 可编辑 | 藏得深，缺「个人主页」的统一聚合感 |

**核心洞察**：当前所有社交关系都是**临时的、围绕一次约伴产生的**（约伴接受 → 自动建 `Conversation`，路线完成后会话 `isReadOnly` 冻结）。「好友」恰是缺的**持久关系层**——它把「一次性约伴」升级成「长期连接」。

### 产品决策（已确认）

- **好友 = 双向确认强关系**：`pending → accepted`，可 `blocked`。成为好友才解锁「直接约伴 / 持久私信 / 完整主页」。
- **三条发现路径全要**：①约伴/对话中加 ②好友码 / 二维码 ③Discover 主页直接加。
- **隐私姿态延续 `user.ts` 的「strict by design」**：无真实姓名、无真实头像（仅 emoji）、好友码而非手机号搜索。

---

## 2. 数据模型

### 2.1 设计原则

1. **TS↔Swift 双写**：`packages/core/src/friend.ts` 定义契约，Swift 侧镜像，`pnpm parity:check` 守护。沿用现有 `companion.ts` 的写法（branded ID、ISO8601 字段、readonly）。
2. **Branded ID**：新增 `FriendshipId`（`fnd_*`）、`FriendRequestId`（`freq_*`）。
3. **规范化存储**：`Friendship` 用「有序对」存——`userLowId < userHighId`（字典序），保证 A↔B 只有一行，查询幂等。方向信息（谁发起）单列。
4. **复用而非复制**：好友的「资料」直接复用 `CompanionProfile`（emoji/bio/languages）+ `User.displayHandle`，**不新建 Profile 表**。好友系统只管「关系」，不管「资料」。

### 2.2 TypeScript 契约（`packages/core/src/friend.ts` 新建）

```typescript
import type { UserId } from "./user";
import type { ConversationId } from "./companion";

/** Stable handle. Format: `fnd_<random_id>`. */
export type FriendshipId = string & { readonly __brand: "FriendshipId" };

/** Stable handle. Format: `freq_<random_id>`. */
export type FriendRequestId = string & { readonly __brand: "FriendRequestId" };

/** A short, shareable code a user hands out to be added (e.g. "SOLO-7K2F-9XQ").
 *  Rotatable — issuing a new one invalidates the old. Never the raw UserId. */
export type FriendCode = string & { readonly __brand: "FriendCode" };

export type FriendRequestStatus =
  | "pending"
  | "accepted"
  | "declined"
  | "withdrawn"
  | "expired";

/** How the requester reached the recipient — drives anti-abuse weighting. */
export type FriendRequestSource =
  | "companion_chat"   // 已在某个约伴会话里
  | "route_group"      // 同一条路线群聊里
  | "friend_code"      // 扫码 / 输码
  | "discover";        // Discover 匿名主页直接加

export interface FriendRequest {
  readonly id: FriendRequestId;
  readonly requesterId: UserId;
  readonly recipientId: UserId;
  readonly status: FriendRequestStatus;
  readonly source: FriendRequestSource;
  /** Optional one-line hello, max 120 chars. */
  readonly note?: string;
  /** ISO 8601 UTC. Requests auto-expire after 14 days → status "expired". */
  readonly expiresAt: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}

/** A confirmed, bidirectional friendship. Stored once per pair (ordered). */
export interface Friendship {
  readonly id: FriendshipId;
  /** Lexicographically smaller of the two UserIds. */
  readonly userLowId: UserId;
  /** Lexicographically larger of the two UserIds. */
  readonly userHighId: UserId;
  /** Who originally sent the accepted request (provenance, not direction). */
  readonly initiatedBy: UserId;
  /** The persistent 1:1 conversation backing this friendship (lazily created). */
  readonly conversationId?: ConversationId;
  /** ISO 8601 UTC when the friendship became active (request accepted). */
  readonly acceptedAt: string;
  readonly createdAt: string;
  readonly updatedAt: string;
}
```

> 拉黑**复用现有 `CompanionBlock`**（`blockerId`/`blockedId`），不另起炉灶。拉黑时连带把 `Friendship` 软删除。

### 2.3 `Conversation` 的关键改造（最小侵入）

当前 `Conversation.requestId: CompanionRequestId` 是**必填**，好友直聊没有约伴请求。两个方案：

| 方案 | 改动 | 评价 |
| --- | --- | --- |
| **A（推荐）** 把 `requestId` 改为可选 `requestId?` | TS+Swift 各 1 处；Swift 已有 `decodeIfPresent` 容错习惯 | 语义最干净：会话可由「约伴请求」**或**「好友关系」催生 |
| B 给好友造一个假的 sentinel requestId | 0 schema 改动 | 脏，污染数据查询，否决 |

选 **A**。同时新增一个会话来源枚举（可选，向后兼容）：

```typescript
export type ConversationType = "oneOnOne" | "groupRoute" | "friendDirect";
//                                                          ^^^^^^^^^^^^ 新增
```

`friendDirect` 会话**永不 `isReadOnly`**（好友关系不随路线完成而冻结），这正是「持久私信」与「约伴临时会话」的本质区别。

### 2.4 Swift 侧镜像

新建文件，对齐现有 `Models/Conversation.swift` 的写法（`RawRepresentable` ID、`Codable`、自定义 decoder 容错、`#Preview` sample）：

```
apps/ios/SoloCompass/Models/
  FriendRequest.swift      // FriendRequestId/Status/Source + struct
  Friendship.swift         // FriendshipId/FriendCode + struct + 便捷 otherUserId(viewer:)
```

`Friendship` 加一个便利方法（视角化）：

```swift
extension Friendship {
    /// The *other* participant from a given viewer's perspective.
    func otherUserId(viewer: UserId) -> UserId {
        viewer == userLowId ? userHighId : userLowId
    }
}
```

### 2.5 SwiftData 持久化 + 迁移

按现有 `SoloCompassModelContainer.swift` 的**增量轻量迁移**范式（v1.2 加 `ChatSessionRecord`/`ChatMessageRecord` 就是先例：「新增 @Model 表 = 加两张空表，不重写数据」）：

1. 新建 `Persistence/Models/FriendshipRecord.swift`、`FriendRequestRecord.swift`（`@Model`，blob 存数组同现有惯例）。
2. 新增 `SoloCompassSchemaV1_3`，models 列表追加这两张表。
3. `SoloCompassMigrationPlan.stages` 追加 `.lightweight(v1_2 → v1_3)`。
4. `SoloCompassModelContainer.shared` 与 `makeInMemory()` 两处 `ModelContainer(for:)` 追加新表。
5. 若改了 `Conversation`（2.3），`ConversationRecord` 的 `requestId` 列改为可选——也是轻量迁移。

> ⚠️ 注意现有代码注释：`shared` 故意**不传** `migrationPlan:`，靠 SwiftData 隐式轻量迁移。新增表遵循同样路径即可，别画蛇添足显式声明 stage（注释明确说会触发 `NSLightweightMigrationStage` boot 崩溃）。

---

## 3. 关系状态机

```
                 sendRequest(source)
   [无关系] ───────────────────────────► pending
      ▲                                     │
      │ withdraw / decline / expire(14d)    │ accept
      │                                     ▼
      └──────────────────────────────── accepted (= Friendship 落地)
                                            │
                              block ────────┤
                                            ▼
                                        blocked (Friendship 软删 + CompanionBlock 落地)
                                            │ unblock
                                            ▼
                                        [无关系]
```

**幂等与并发规则**（后端 + 本地都要守）：

- **双向 pending 折叠**：A 已对 B pending，B 又对 A 发请求 → 直接判定为「双方都想加」→ **自动 accept**，皆大欢喜。
- **已是好友**再发请求 → no-op 返回现有 `Friendship`。
- **被对方拉黑**时发请求 → 静默成功（不泄露拉黑信息），但不实际入队。
- **请求过期**：`expiresAt` 到点由清理任务（沿用 `CompanionService.cleanupStaleRequests()` 的模式）置为 `expired`。

状态机做成**纯函数**，对齐现有 `RouteCompanionStateMachine.transition(state, event)` 的写法，便于单测。

---

## 4. 与约伴 / 私信打通（这是重点）

### 4.1 好友 → 直接约伴

现有约伴有两条路，好友给它们各加一条「快捷入口」，**不改约伴核心逻辑**：

| 约伴类型 | 现状入口 | 好友快捷入口 |
| --- | --- | --- |
| 自由匹配 `CompanionRequest` | Discover 列表里看陌生人 → SendRequestSheet | 好友主页/好友列表 →「邀他一起逛」→ 复用 `SendRequestSheet`，但 recipient 预填、`source=friend`、**跳过 reporterWeight 信任门槛**（已是好友即已信任） |
| 路线拼团 `RouteCompanion` | DiscoverRecruitingRoutes → JoinRouteRequestSheet | 我的招募路线 →「邀请好友加入」→ **免审批直接进 `confirmedMembers`** |

关键：**好友关系是「信任快进键」**。Discover 流程为陌生人设计了一堆安全摩擦（匿名 handle、reporterWeight≥0.3、安全同意），好友已越过信任门槛，可合理简化。

> **已确认决议（D-3）：好友邀请加入路线 = 免 host 审批，直接进 `confirmedMembers`。**
> 但「免审批」是**好友邀请**这条路径的属性，不是强制行为——host 在「邀请好友加入」UI 上自行决定**要不要发出邀请**；一旦发出，好友侧无需再过审批队列。host 的控制权落在「邀不邀」，而非「邀了还要再审」。陌生人走 `JoinRouteRequestSheet` 的审批流不变。

### 4.2 约伴成功 → 升级为好友

反向闭环：约伴会话/路线群聊里，每个参与者旁边加「+ 加为好友」按钮（`source=companion_chat`/`route_group`）。这把「一次性队友」沉淀成「长期好友」，是关系增长的主引擎。

### 4.3 好友 → 持久私信

```
点好友 → 好友主页 →「发消息」
   │
   ├─ Friendship.conversationId 已存在？→ 直接打开现有 ChatView
   └─ 不存在？→ 懒创建 type=.friendDirect 的 Conversation（requestId=nil）
                 → 回写 Friendship.conversationId → 打开 ChatView
```

**完全复用 `ChatView` + `ChatService` + Supabase Realtime**，零新建聊天 UI。唯一区别：`friendDirect` 会话不显示「路线卡片」头部、不会 `isReadOnly` 冻结、菜单里「举报/拉黑」连带解除好友。

### 4.4 一张图看清关系流转

```
                    ┌─────────────┐
   扫好友码 ───────►│             │
   Discover 加 ───►│ FriendRequest│──accept──► Friendship ◄──── 约伴会话里 +好友
   约伴会话里 +好友►│  (pending)  │              │
                    └─────────────┘              │
                                                 ├──「邀他约伴」──► SendRequestSheet(预填,免门槛)
                                                 ├──「发消息」────► Conversation(friendDirect) ──► ChatView
                                                 └──「看主页」────► FriendProfileView(只读)
```

---

## 5. UI 设计：优雅地显示出来

设计哲学对齐项目调性：**地图是家，社交不抢戏**。好友不是新增一个 Tab（项目刻意 no-tabs），而是顺着现有 sheet/NavigationStack 架构生长。

### 5.1 信息架构（入口收敛）

现有社交入口散在 Settings → Companion 下，体验割裂。新增**统一的「Me / 个人中心」**作为社交聚合面，但保持「轻」。**已确认决议（D-1）：入口 = 地图右上角头像气泡**（不沿用 Settings 下沉，要的就是「个人主页」的存在感）：

```
CompassMapView (根，地图)
  └─ 右上角头像气泡（emoji avatar）──tap──► .sheet
        │
        └─ MeSheet (个人中心，NavigationStack)
              ├─ ProfileHeader      我的 emoji 头像 + handle + bio + 走过 N 地 + 好友码入口
              ├─ ┌ Friends ─────────────────────────┐
              │  │ 好友列表(横向头像条) + 待处理请求红点 │
              │  └────────────────────────────────────┘
              ├─ ┌ Messages ────────────────────────┐
              │  │ 会话列表(友聊+约伴会话统一时间排序)  │
              │  └────────────────────────────────────┘
              ├─ Companion（沿用现有 Discover/招募等）
              └─ Settings（现有设置下沉到这）
```

> 头像气泡放地图右上角，与现有 mapControls 共存（注意 memory 记录的 `mapcontrols_safearea_collision` 坑：放安全区 overlay，别撞状态栏）。

### 5.2 五个新界面

| 界面 | 作用 | 复用 |
| --- | --- | --- |
| `MeSheet` | 个人中心聚合面 | 新建，但内容多为现有视图的 NavigationLink |
| `MyProfileEditView` | 编辑我的头像/handle/bio/语言/好友码 | **升级现有 `CompanionProfileView`** —— 它已有 emoji 选择器/bio/语言，只补 handle 编辑 + 好友码展示 |
| `FriendProfileView` | 看**别人**的只读主页 | 复用 `CompanionProfileView` 的展示布局，去掉编辑、加「邀约伴/发消息/加好友」行动条 |
| `FriendsListView` | 好友列表 + 请求收件箱 | 结构对齐现有 `MyRequestsListView`/`RequestInboxView` |
| `AddFriendSheet` | 好友码输入 + 二维码扫描 + 我的码展示 | 新建（含 `AVFoundation` 扫码 + `CoreImage` 生码） |

### 5.3 个人主页（FriendProfileView）的优雅呈现

这是「看对方主页」的核心界面。布局草案：

```
┌──────────────────────────────────┐
│            🧗                     │  ← 大号 emoji 头像（圆形渐变底）
│         山野之客                   │  ← displayHandle
│   「喜欢清晨爬山，讨厌人多」        │  ← bio
│   🇨🇳 中文 · 🇬🇧 English          │  ← languages（旗帜+语言）
│                                  │
│   ┌──────┬──────┬──────┐         │
│   │走过 23│拼团 7 │好友 12│         │  ← 信任信号（沿用 ApprovalQueue 的"已走过X条"信号）
│   └──────┴──────┴──────┘         │
│                                  │
│   最近走过的路线                  │
│   [缩略卡] [缩略卡] [缩略卡]       │  ← 复用 CompanionProfileView 已有的"走过路线"展示
│                                  │
├──────────────────────────────────┤
│  [💬 发消息]  [🧭 邀他约伴]        │  ← 已是好友时的行动条（底部固定 dock）
└──────────────────────────────────┘
        — 或非好友时 —
│  [➕ 加为好友]                    │  ← 单一主行动
```

呈现要点（对齐项目视觉规范，参考 memory）：
- 头像用**圆形渐变底 + 大号 emoji**，避免「空头像」尴尬（项目无真实照片）。
- 信任信号是这个 app 的灵魂——「身份由你体验过什么定义」。把「走过 N 地 / 拼团 N 次 / 好友 N」做成一眼可见的 stat 行，比任何自我介绍都有说服力。
- 底部行动条用固定 dock，遵循 memory 里 `bottomsheet_peek_clearance`——让出 peek 高度别被遮。
- 颜色用 `CT.*` 固定浅色卡片体系，注意 memory 记录的「固定白底别盲改语义色」坑。

### 5.4 添加好友（AddFriendSheet）的优雅呈现

```
┌──────────────────────────────────┐
│         添加好友                  │
│  ┌────────────────────────────┐  │
│  │   我的好友码                 │  │
│  │   ┌──────────┐              │  │
│  │   │ ▓▓ QR ▓▓ │ SOLO-7K2F-9X │  │  ← 二维码 + 文字码，可长按复制/分享
│  │   └──────────┘              │  │
│  └────────────────────────────┘  │
│                                  │
│  ┌────────────────────────────┐  │
│  │  [📷 扫一扫]  [⌨️ 输入码]    │  │  ← 两种加人方式
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

- 好友码格式 `SOLO-XXXX-XXXX`（去掉易混字符 0/O/1/I），既可读又可扫。
- 好友码**可轮换**（隐私：泄露了能换一个），映射存后端 `friend_codes` 表（code → userId，可失效）。
- 扫码即拉起 `FriendProfileView` 预览 → 确认后发 `FriendRequest(source=friend_code)`。

---

## 6. 后端（Supabase）

延续现有 outbox + poll 模式（`SyncService` 30s flush + 增量 pull，`FF_BACKEND_SYNC` 门控，关闭时本地完全可用）。

新增表（RLS 必须开，参照现有 companion 表策略）：

| 表 | 关键列 | RLS 要点 |
| --- | --- | --- |
| `friend_requests` | requester_id, recipient_id, status, source, note, expires_at | 仅收发双方可读；recipient 可改 status |
| `friendships` | user_low_id, user_high_id, initiated_by, conversation_id, accepted_at | 仅两端可读；唯一约束 `(user_low_id, user_high_id)` |
| `friend_codes` | code (PK), user_id, revoked_at | code 可被任何登录用户「兑换」查 user_id（用于加人），但不暴露反查 |

**反骚扰**（对齐项目 safety 基因）：
- `friend_requests` 加频率限制（每用户每日上限，Edge Function 侧）。
- `discover` 来源的请求受 `reporterWeight ≥ 0.3` 门槛（复用现有阈值），`friend_code` 来源不受限（线下信任）。
- 拉黑后双方互不可发请求、互不可见（复用 `CompanionBlock` 过滤）。

---

## 7. 分期实施路线图

### Phase 1 — 关系地基 + 个人主页（可独立交付、可见成果）
- [ ] `packages/core/src/friend.ts` 契约 + `pnpm parity:check` 守护
- [ ] Swift `FriendRequest`/`Friendship` 模型 + SwiftData v1.3 迁移
- [ ] `FriendService`（@MainActor @Observable，对齐 `CompanionService` 写法）：send/accept/decline/withdraw/list，纯函数状态机 + 单测
- [ ] **个人主页**：升级 `CompanionProfileView` → `MyProfileEditView`（补 handle 编辑）+ 新建只读 `FriendProfileView`
- [ ] `MeSheet` 骨架 + 地图右上角头像入口
- [ ] 验收：能在两个模拟器实例间发/收好友请求并落地 `Friendship`；能看对方只读主页

### Phase 2 — 三条发现路径 + 持久私信
- [ ] `AddFriendSheet`：好友码生成/展示/输入 + 二维码扫码（`friend_codes` 表）
- [ ] 约伴会话/路线群聊里「+加好友」按钮（source=companion_chat/route_group）
- [ ] Discover 主页「加好友」入口（受 reporterWeight 门槛）
- [ ] `Conversation` 改造（requestId 可选 + friendDirect 类型）+ 好友「发消息」懒创建会话，接 `ChatView`
- [ ] `FriendsListView`（好友列表 + 请求收件箱红点）+ `MeSheet` Messages 统一会话列表
- [ ] 验收：扫码加好友 → 直接私信全链路通

### Phase 3 — 好友约伴打通 + 后端硬化
- [ ] 好友主页「邀他约伴」→ 预填 `SendRequestSheet`（免信任门槛）
- [ ] 招募路线「邀请好友加入」
- [ ] Supabase RLS 策略 + 频率限制 Edge Function + 请求过期清理任务
- [ ] 反骚扰打磨（拉黑连带、好友码轮换）
- [ ] 验收：好友间「邀约伴 → 约伴成功 → 群聊 → 互升级好友」完整闭环

---

## 8. 风险与取舍

| 风险 | 缓解 |
| --- | --- |
| `Conversation.requestId` 必填阻塞好友直聊 | 方案 A 改可选（§2.3），轻量迁移，已验证 Swift 侧有 decodeIfPresent 容错习惯 |
| Discover 加陌生人 → 骚扰 | reporterWeight≥0.3 门槛 + 频率限制 + 好友请求 note 限长 120 |
| 社交功能稀释「solo 工具」定位 | 全部 FeatureFlag 门控（沿用 `FeatureFlags.companion`），默认可关；地图仍是家，社交在 sheet 里不抢戏 |
| 后端没上线时功能假死 | 延续 `FF_BACKEND_SYNC` 本地优先：关闭时好友功能本地可演示、不报错 |
| 双向 pending / 重复请求竞态 | 状态机纯函数 + 后端唯一约束 + 自动 accept 折叠（§3） |

---

## 9. 已确认决议（原开放问题 → 定稿）

| # | 问题 | 决议 | 对设计的影响 |
| --- | --- | --- | --- |
| **D-1** | 个人中心入口 | **地图右上角头像气泡**（不沿用 Settings 下沉） | §5.1 已定；要做地图 chrome，注意 `mapcontrols_safearea_collision` 安全区坑 |
| **D-2** | Discover 加陌生好友何时上 | **Phase 2 就上** | §7 Phase 2 排期不变；骚扰风险靠 reporterWeight≥0.3 门槛 + 频率限制兜底（§6） |
| **D-3** | 好友邀约伴是否免审批 | **免审批**，但 host 自行权衡「邀不邀」 | §4.1 已定；控制权在「邀请动作」本身，不在二次审批 |
| **D-4** | 好友数上限 | **无上限** | 克制感靠「双向确认 + FeatureFlag 默认可关」实现，不靠硬上限；后端频率限制仍防滥用 |

> 方向已全部锁定，本设计即为可执行定稿。下一步：实施 Phase 1（关系地基 + 个人主页）。
