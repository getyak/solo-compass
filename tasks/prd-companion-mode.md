# PRD: Companion Mode — 附近人约伴与多行程

## Introduction/Overview

Solo Compass 当前是一个**严格隐私、本地优先、无社交图谱**的独行者地图陪伴 app(`User` 模型明确写着 "No real names. No social graph.")。本特性在**不推翻这一灵魂**的前提下,新增"约伴(Companion Mode)"能力,让用户可以**主动、临时、可撤销地**把一部分自己暴露给一次具体的相遇。

约伴有两条路径:

1. **行程约伴(itinerary)** —— 用户先创建一个或多个旅行行程(如"清迈 5 日""曼谷周末"),可把某个行程标记为"开放约伴";其他用户按城市/日期/品类发现这些行程并发起同行请求。
2. **实时附近(nearby)** —— 用户在前台手动开启"附近约伴",app 仅在前台、以 **geohash6(~600m)模糊网格**广播位置;其他人能看到"约 600m 内有人想约伴",但**精确坐标永不出库**,碰头前不暴露。

双方互相 accept 后解锁 **app 内轻量实时聊天(Supabase Realtime + 纯文本)**。

**设计三铁律(贯穿所有 US):**

- **默认全关** —— 不开约伴,体验与今天 100% 一致:零位置上报、零可见性、零跨用户查询。
- **行程是约伴的"理由",不是位置** —— 优先按"去哪/何时去"匹配,把实时 GPS 隐私风险降到最低。
- **位置永远模糊化** —— 实时附近只广播 geohash6,精确坐标绝不离开设备 / 绝不入库。

## Goals

- 让用户能创建、管理**多个**旅行行程,并把现有收藏(`favoritedExperiences`)归入行程(满足"支持多个可约伴行程"诉求)。
- 让用户能把行程标记为"开放约伴",并被同城同期的其他用户发现。
- 提供一个**模糊化、仅前台、手动开关**的实时附近约伴模式,隐私风险最小化。
- 提供双向握手(互相 accept)后的 **app 内轻量实时聊天**。
- 提供完整的**安全与反骚扰**机制:举报、拉黑、自动过期、复用 `reporterWeight` 信任降权。
- **默认关闭、可一键全关**:不启用约伴的用户体验与现状零差异。

## 数据模型总览(三层对齐:TS core → Swift → Supabase)

所有跨进程实体都必须三层对齐并通过 `pnpm parity:check`(见 `scripts/check-swift-parity.ts`)。

### 新增 `packages/core/src/companion.ts`(TS 真源)

```typescript
import type { UserId } from "./user";
import type { ExperienceId, ExperienceCategory } from "./experience";

/** 一段可约伴的行程。用户可有多个。 */
export type ItineraryId = string & { readonly __brand: "ItineraryId" };

export interface Itinerary {
  readonly id: ItineraryId;
  readonly ownerId: UserId;
  readonly title: string;                          // "清迈 5 日"
  readonly cityCode: string;
  readonly startDate: string;                      // ISO date (日粒度,无时区) e.g. "2026-06-01"
  readonly endDate: string;                        // ISO date e.g. "2026-06-05"
  readonly experienceIds: readonly ExperienceId[]; // 有序,复用现有 Experience
  readonly note?: string;
  /** 是否开放约伴。false = 纯个人行程(等价于"收藏分组")。 */
  readonly openToCompanions: boolean;
  readonly createdAt: string;                      // ISO 8601 UTC e.g. "2026-05-27T04:30:00Z"
  readonly updatedAt: string;                      // ISO 8601 UTC
}

/** 约伴意向:把一个 itinerary 或一个实时网格"挂出来"。 */
export type CompanionPostId = string & { readonly __brand: "CompanionPostId" };

export type CompanionMode = "itinerary" | "nearby";

export interface CompanionPost {
  readonly id: CompanionPostId;
  readonly authorId: UserId;
  readonly mode: CompanionMode;
  readonly itineraryId?: ItineraryId;              // mode=itinerary 时必填
  readonly cityCode: string;
  /** 模糊位置:geohash 精度 6(~600m)e.g. "w5q6kx"。mode=nearby 时必填。永不存精确坐标。 */
  readonly geohash6?: string;
  readonly categories: readonly ExperienceCategory[];
  readonly blurb: string;                          // ≤140 字,"想找人一起吃夜市,说中英文"
  readonly languages: readonly string[];           // ISO codes
  readonly expiresAt: string;                      // ISO 8601 UTC。实时贴 ≤2h;行程贴到 endDate
  readonly createdAt: string;
}

/** 约伴请求/握手。双方互相 accept 后才解锁聊天 + 碰头。 */
export type CompanionRequestId = string & { readonly __brand: "CompanionRequestId" };

export type CompanionRequestStatus = "pending" | "accepted" | "declined" | "expired" | "withdrawn";

export interface CompanionRequest {
  readonly id: CompanionRequestId;
  readonly postId: CompanionPostId;
  readonly fromUserId: UserId;
  readonly toUserId: UserId;
  readonly status: CompanionRequestStatus;
  readonly message?: string;                       // 首条破冰留言,≤200 字
  readonly createdAt: string;
  readonly updatedAt: string;
}

/** 一对一会话(双方 accept 后创建)。 */
export type ConversationId = string & { readonly __brand: "ConversationId" };

export interface Conversation {
  readonly id: ConversationId;
  readonly requestId: CompanionRequestId;
  readonly participantIds: readonly [UserId, UserId];
  readonly createdAt: string;
  readonly lastMessageAt?: string;
}

export type MessageId = string & { readonly __brand: "MessageId" };

export interface ChatMessage {
  readonly id: MessageId;
  readonly conversationId: ConversationId;
  readonly senderId: UserId;
  readonly body: string;                           // 纯文本,≤1000 字
  readonly sentAt: string;                         // ISO 8601 UTC
}

/** 举报。 */
export interface CompanionReport {
  readonly id: string;
  readonly reporterId: UserId;
  readonly reportedUserId: UserId;
  readonly contextType: "post" | "request" | "message" | "profile";
  readonly contextId: string;
  readonly reason: "harassment" | "spam" | "unsafe" | "impersonation" | "other";
  readonly detail?: string;
  readonly createdAt: string;
}
```

### 扩展 `packages/core/src/user.ts`(新增可选档案,不破坏现有 `User`)

```typescript
/** 轻量化名档案。全部可选 —— 不填则约伴里只显示 displayHandle。 */
export interface CompanionProfile {
  readonly avatarEmoji?: string;       // 不用真人照,emoji 或生成头像
  readonly bio?: string;               // ≤140 字
  readonly languages: readonly string[];
  /** 可见性。off = 完全不出现在任何约伴列表(默认)。 */
  readonly visibility: "off" | "itinerary_only" | "nearby_and_itinerary";
  /** 拉黑名单:这些 user 永不出现在我的发现列表,也无法联系我。 */
  readonly blockedUserIds: readonly UserId[];
}
```

> 复用现有 `User.reporterWeight`(软信任分)作为约伴排序与降权依据 —— 信任系统已现成,无需新建。

### Supabase 迁移 `infra/supabase/migrations/0003_companion.sql`

新表 + **反向 RLS**(现有 RLS 全是 `auth.uid()=user_id` 单用户隔离;约伴必须允许严格限定的跨用户读)。

```sql
begin;

-- ─── itineraries ───────────────────────────────────────────────────────
create table if not exists public.itineraries (
  id                  uuid          primary key default gen_random_uuid(),
  owner_id            uuid          not null references auth.users(id) on delete cascade,
  title               text          not null,
  city_code           text          not null,
  start_date          date          not null,
  end_date            date          not null,
  experience_ids      text[]        not null default '{}',
  note                text,
  open_to_companions  boolean       not null default false,
  created_at          timestamptz   not null default now(),
  updated_at          timestamptz   not null default now()
);
create index if not exists itineraries_owner_idx on public.itineraries(owner_id);
create index if not exists itineraries_open_idx
  on public.itineraries(city_code, start_date) where open_to_companions = true;

-- ─── companion_profiles ────────────────────────────────────────────────
create table if not exists public.companion_profiles (
  user_id        uuid    primary key references auth.users(id) on delete cascade,
  display_handle text    not null,
  avatar_emoji   text,
  bio            text,
  languages      text[]  not null default '{}',
  visibility     text    not null default 'off'
                 check (visibility in ('off','itinerary_only','nearby_and_itinerary')),
  reporter_weight double precision not null default 1.0,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- ─── companion_posts ───────────────────────────────────────────────────
create table if not exists public.companion_posts (
  id            uuid        primary key default gen_random_uuid(),
  author_id     uuid        not null references auth.users(id) on delete cascade,
  mode          text        not null check (mode in ('itinerary','nearby')),
  itinerary_id  uuid        references public.itineraries(id) on delete cascade,
  city_code     text        not null,
  geohash6      text,                             -- nearby 时填,精度 6
  categories    text[]      not null default '{}',
  blurb         text        not null,
  languages     text[]      not null default '{}',
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now()
);
create index if not exists posts_discovery_idx
  on public.companion_posts(city_code, mode, expires_at);
create index if not exists posts_geo_idx
  on public.companion_posts(geohash6) where mode = 'nearby';

-- ─── companion_requests ────────────────────────────────────────────────
create table if not exists public.companion_requests (
  id            uuid        primary key default gen_random_uuid(),
  post_id       uuid        not null references public.companion_posts(id) on delete cascade,
  from_user_id  uuid        not null references auth.users(id) on delete cascade,
  to_user_id    uuid        not null references auth.users(id) on delete cascade,
  status        text        not null default 'pending'
                check (status in ('pending','accepted','declined','expired','withdrawn')),
  message       text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists requests_to_idx   on public.companion_requests(to_user_id, status);
create index if not exists requests_from_idx on public.companion_requests(from_user_id, status);

-- ─── conversations + messages ──────────────────────────────────────────
create table if not exists public.conversations (
  id              uuid        primary key default gen_random_uuid(),
  request_id      uuid        not null unique references public.companion_requests(id) on delete cascade,
  participant_a   uuid        not null references auth.users(id) on delete cascade,
  participant_b   uuid        not null references auth.users(id) on delete cascade,
  created_at      timestamptz not null default now(),
  last_message_at timestamptz
);
create index if not exists conv_a_idx on public.conversations(participant_a);
create index if not exists conv_b_idx on public.conversations(participant_b);

create table if not exists public.chat_messages (
  id               uuid        primary key default gen_random_uuid(),
  conversation_id  uuid        not null references public.conversations(id) on delete cascade,
  sender_id        uuid        not null references auth.users(id) on delete cascade,
  body             text        not null check (char_length(body) <= 1000),
  sent_at          timestamptz not null default now()
);
create index if not exists msg_conv_idx on public.chat_messages(conversation_id, sent_at);

-- ─── reports + blocks ──────────────────────────────────────────────────
create table if not exists public.companion_reports (
  id               uuid        primary key default gen_random_uuid(),
  reporter_id      uuid        not null references auth.users(id) on delete cascade,
  reported_user_id uuid        not null references auth.users(id) on delete cascade,
  context_type     text        not null check (context_type in ('post','request','message','profile')),
  context_id       text        not null,
  reason           text        not null check (reason in ('harassment','spam','unsafe','impersonation','other')),
  detail           text,
  created_at       timestamptz not null default now()
);

create table if not exists public.companion_blocks (
  blocker_id  uuid        not null references auth.users(id) on delete cascade,
  blocked_id  uuid        not null references auth.users(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);

-- ─── RLS ───────────────────────────────────────────────────────────────
alter table public.itineraries         enable row level security;
alter table public.companion_profiles  enable row level security;
alter table public.companion_posts     enable row level security;
alter table public.companion_requests  enable row level security;
alter table public.conversations       enable row level security;
alter table public.chat_messages       enable row level security;
alter table public.companion_reports   enable row level security;
alter table public.companion_blocks    enable row level security;

-- itineraries: 自己全权;跨用户只读 open_to_companions = true
create policy "itin self-all"     on public.itineraries
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
create policy "itin read-open"    on public.itineraries
  for select using (open_to_companions = true);

-- companion_profiles: 自己读写;非 off 的可被他人读(发现展示)
create policy "profile self-all"  on public.companion_profiles
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "profile read-visible" on public.companion_profiles
  for select using (visibility <> 'off');

-- companion_posts: 未过期可读(发现);写只能写自己
create policy "posts read-live"   on public.companion_posts
  for select using (expires_at > now());
create policy "posts self-write"  on public.companion_posts
  for insert with check (auth.uid() = author_id);
create policy "posts self-delete" on public.companion_posts
  for delete using (auth.uid() = author_id);

-- companion_requests: 只有 from/to 双方能看/动
create policy "req participant-read" on public.companion_requests
  for select using (auth.uid() in (from_user_id, to_user_id));
create policy "req self-insert"      on public.companion_requests
  for insert with check (auth.uid() = from_user_id);
create policy "req participant-update" on public.companion_requests
  for update using (auth.uid() in (from_user_id, to_user_id))
  with check (auth.uid() in (from_user_id, to_user_id));

-- conversations: 仅参与者可读
create policy "conv participant-read" on public.conversations
  for select using (auth.uid() in (participant_a, participant_b));

-- chat_messages: 仅会话参与者可读;只能以自己身份发,且必须是该会话参与者
create policy "msg participant-read" on public.chat_messages
  for select using (
    exists (select 1 from public.conversations c
            where c.id = conversation_id
              and auth.uid() in (c.participant_a, c.participant_b)));
create policy "msg self-insert" on public.chat_messages
  for insert with check (
    auth.uid() = sender_id and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and auth.uid() in (c.participant_a, c.participant_b)));

-- reports: 任何人可举报;只能以自己身份;不可读他人举报
create policy "report self-insert" on public.companion_reports
  for insert with check (auth.uid() = reporter_id);

-- blocks: 自己全权
create policy "block self-all" on public.companion_blocks
  using (auth.uid() = blocker_id) with check (auth.uid() = blocker_id);

-- updated_at 触发器(复用现有 sc_touch_updated_at)
create trigger sc_itineraries_touch        before update on public.itineraries        for each row execute function public.sc_touch_updated_at();
create trigger sc_companion_profiles_touch before update on public.companion_profiles for each row execute function public.sc_touch_updated_at();
create trigger sc_companion_requests_touch before update on public.companion_requests for each row execute function public.sc_touch_updated_at();

commit;
```

> **发现查询不让客户端全表扫。** "谁在附近 / 同城开放行程"一律走 **Edge Function**(`companion-discover`),函数内用 service role 过滤 `city_code` + `geohash6` 前缀 + `expires_at > now()` + 排除拉黑双方,只回吐脱敏字段(handle / emoji / blurb / 模糊距离桶),**精确坐标永不出库、永不返回客户端**。

---

## User Stories

### Phase 1 — 多行程(纯本地,零社交,零隐私风险,可独立发版)

#### US-001: 定义 Itinerary 数据模型(TS core)
**Description:** As a developer, I want a typed `Itinerary` schema in core so 行程能在三层间一致传递。

**Acceptance Criteria:**
- [ ] 新建 `packages/core/src/companion.ts`,导出 `Itinerary`、`ItineraryId`(branded type)
- [ ] 在 `packages/core/src/index.ts` 导出
- [ ] coords/日期遵循项目约定(date 为 ISO 日粒度,时间戳为 ISO 8601 UTC)
- [ ] `pnpm typecheck` 通过
- [ ] `pnpm test`(core 包)通过

#### US-002: Itinerary Swift 模型 + parity 通过
**Description:** As a developer, I want `Itinerary.swift` 镜像 TS,so parity guard 通过。

**Acceptance Criteria:**
- [ ] 新建 `apps/ios/SoloCompass/Models/Itinerary.swift`,字段与 TS 对齐
- [ ] `ItineraryId` 用 Swift 强类型(struct wrapper 或 typealias + 校验)
- [ ] 提供 `#Preview` 所需的 sample 工厂
- [ ] `pnpm parity:check` 通过
- [ ] `xcodebuild build` 通过

#### US-003: Itinerary 本地持久化(SwiftData)
**Description:** As a user, I want 我的行程在本地持久保存,so 关 app 不丢。

**Acceptance Criteria:**
- [ ] SwiftData model + `ItineraryStore`(或扩展现有持久层)实现增删改查
- [ ] 默认 `openToCompanions = false`
- [ ] 单元测试覆盖 CRUD(`apps/ios/SoloCompass/Tests/`)
- [ ] `xcodebuild test` 通过

#### US-004: 行程列表与详情 UI
**Description:** As a user, I want 看到我的所有行程并进入某个行程,so 我能管理多个旅行计划。

**Acceptance Criteria:**
- [ ] 新增 `Views/Companion/ItineraryListView.swift`、`ItineraryDetailView.swift`
- [ ] 列表显示 title / 城市 / 日期范围 / 体验数
- [ ] 空状态有引导文案(`NSLocalizedString`)
- [ ] 每个 view 有 `#Preview`
- [ ] 在 Simulator 中验证(iPhone 17 Pro)新建/查看/删除行程视觉与交互正常

#### US-005: 创建/编辑行程
**Description:** As a user, I want 新建一个行程并填标题/城市/日期,so 我能开始规划。

**Acceptance Criteria:**
- [ ] 创建表单:title、cityCode(从已有城市选择)、startDate/endDate
- [ ] endDate 不得早于 startDate(表单校验)
- [ ] 保存后立即出现在列表
- [ ] 所有文案 `NSLocalizedString`
- [ ] 在 Simulator 中验证创建与编辑流程

#### US-006: 把体验加入行程 / 从收藏迁移
**Description:** As a user, I want 把一个 Experience 加进某个行程,并把现有收藏归入行程,so 收藏不再是一个无结构的大集合。

**Acceptance Criteria:**
- [ ] Experience 详情页有"加入行程"入口(选择已有行程或新建)
- [ ] 行程详情页可调整 `experienceIds` 顺序(拖拽)
- [ ] 提供"从收藏导入"动作:把 `favoritedExperiences` 选取项加入指定行程
- [ ] 现有 `favoritedExperiences` 行为不被破坏(行程是叠加,不是替换)
- [ ] 在 Simulator 中验证加入/排序/导入

#### US-007: 行程通过 outbox 同步到 Supabase
**Description:** As a user, I want 行程跨设备同步,so 换设备不丢行程。

**Acceptance Criteria:**
- [ ] `itineraries` 表迁移并入 `0003_companion.sql`(仅本表部分先上)
- [ ] 复用 `SyncService` 的 `enqueue` outbox 模式,新增 itinerary 同步处理
- [ ] last-write-wins 合并(对齐现有 `updated_at` + device_id 决胜逻辑)
- [ ] `FF_COMPANION` flag 关时仅记录 outbox、不 flush(对齐现有 `FF_BACKEND_SYNC` 模式)
- [ ] 单元测试覆盖 enqueue + 合并
- [ ] `xcodebuild test` 通过

### Phase 2 — 行程约伴(异步发现 + 握手 + 档案,需后端)

#### US-008: 约伴数据模型补全(TS + Swift + 迁移)
**Description:** As a developer, I want `CompanionPost / CompanionRequest / CompanionProfile / Conversation / ChatMessage / CompanionReport` 三层落地。

**Acceptance Criteria:**
- [ ] `companion.ts` 补全上述类型 + branded IDs
- [ ] 对应 Swift 模型新建并通过 `parity:check`
- [ ] `0003_companion.sql` 全表 + RLS 应用成功(本地 supabase 或测试库验证)
- [ ] `CompanionProfile` 加入 `user.ts` 与 Swift 侧
- [ ] `pnpm typecheck` + `pnpm parity:check` + `xcodebuild build` 通过

#### US-009: 约伴档案设置 + 可见性开关(默认 off)
**Description:** As a user, I want 设置我的约伴档案(emoji/简介/语言)和可见性,so 我能控制谁能看到我。

**Acceptance Criteria:**
- [ ] 新增 `Views/Companion/CompanionProfileView.swift`
- [ ] visibility 三档:off(默认)/ itinerary_only / nearby_and_itinerary
- [ ] off 时本人不出现在任何发现列表(后端 RLS + Edge Function 双重保证)
- [ ] 不提供真人照上传(仅 emoji / 生成头像)
- [ ] 在 Simulator 中验证档案保存与可见性切换

#### US-010: 把行程标记为"开放约伴"
**Description:** As a user, I want 把某个行程开放约伴,so 同城同期的人能找到我。

**Acceptance Criteria:**
- [ ] 行程详情页有"开放约伴"开关 → 写 `openToCompanions`
- [ ] 开启时引导填写 `blurb` + categories(生成一条 `CompanionPost(mode=itinerary)`)
- [ ] 关闭时该行程的 post 立即下架(删除或置过期)
- [ ] visibility=off 时禁止开启并提示先开可见性
- [ ] 在 Simulator 中验证开/关与提示

#### US-011: 约伴发现列表(Edge Function)
**Description:** As a user, I want 看到同城开放约伴的行程,按日期/品类筛选,so 我能找到合适的旅伴。

**Acceptance Criteria:**
- [ ] 新建 Edge Function `companion-discover`:入参 city_code / mode / 日期 / categories;service role 过滤 + 排除拉黑双方;只回脱敏字段
- [ ] 新建 `CompanionService.swift` 调用该函数
- [ ] 新增 `Views/Companion/DiscoverListView.swift`,卡片显示 handle/emoji/blurb/日期/品类
- [ ] 列表不返回任何精确坐标
- [ ] 空状态文案 + 冷启动提示("这座城市还没有人开放约伴")
- [ ] 在 Simulator 中验证发现列表渲染与筛选

#### US-012: 发起 / 接受 / 拒绝约伴请求(双向握手)
**Description:** As a user, I want 对一条约伴贴发起请求,对方 accept 后我们才连上,so 双向同意才解锁联系。

**Acceptance Criteria:**
- [ ] 发现卡片可"发起约伴"(带破冰留言 ≤200 字)→ 写 `CompanionRequest(pending)`
- [ ] 收件箱 `RequestInboxView.swift` 显示收到的 pending 请求,可 accept/decline
- [ ] 双方都为 accepted 时,后端创建 `Conversation`(通过 Edge Function 或 DB 触发器保证一致性)
- [ ] decline / withdraw 后不创建会话,且不再互相打扰
- [ ] 在 Simulator 中用两个匿名账号验证完整握手(可借测试库 + 两个 device)

#### US-013: App 内轻量实时聊天(Supabase Realtime)
**Description:** As a user, I want 和已 accept 的旅伴在 app 内文字聊天,so 我们能商量碰头。

**Acceptance Criteria:**
- [ ] `ChatService.swift` 订阅 `chat_messages` 的 Realtime channel(按 conversation_id)
- [ ] `Views/Companion/ChatView.swift`:文本输入、消息气泡、按 `sent_at` 排序
- [ ] 仅会话参与者可读写(RLS 已保证;客户端再校验一层)
- [ ] 消息 ≤1000 字;纯文本(不支持图片/附件)
- [ ] 断线重连后能拉取离线期间消息(按 `sent_at > lastSeen`)
- [ ] 在 Simulator 中验证双向实时收发

#### US-014: 举报与拉黑
**Description:** As a user, I want 举报或拉黑某人,so 我能保护自己免受骚扰。

**Acceptance Criteria:**
- [ ] post / request / message / profile 任意位置可发起举报(选 reason + 可选 detail)
- [ ] 拉黑后:对方从我的所有发现列表消失,无法对我发起请求,已有会话冻结
- [ ] 举报写入 `companion_reports`(用户不可读他人举报)
- [ ] 拉黑写入 `companion_blocks`,Edge Function 发现查询双向排除
- [ ] 在 Simulator 中验证举报提交与拉黑生效

### Phase 3 — 实时附近(最高隐私门槛,最后做)

#### US-015: PresenceService — 仅前台、手动开关、geohash6 广播
**Description:** As a user, I want 手动开启"附近约伴",仅在前台模糊广播位置,so 我能即时找到附近的人且隐私可控。

**Acceptance Criteria:**
- [ ] 新建 `PresenceService.swift`:仅当用户在 UI 主动开启时启动
- [ ] 订阅 `LocationService.currentLocation`,转换为 geohash6(~600m),每 N 分钟上报一次 `CompanionPost(mode=nearby, geohash6)`
- [ ] app 进入后台 / 用户关闭开关 → **立即停止上报**并下架 nearby post
- [ ] 精确坐标永不离开设备(仅本地计算 geohash6 后丢弃精确值)
- [ ] 不请求 Always 授权;WhenInUse 即可
- [ ] 单元测试:开关切换、后台停发、坐标→geohash6 转换正确
- [ ] `xcodebuild test` 通过

#### US-016: LocationService 加 coarse geohash 接缝
**Description:** As a developer, I want 在 LocationService 暴露一个 coarse(geohash6)读取口,so PresenceService 不需碰精确 GPS 管理逻辑。

**Acceptance Criteria:**
- [ ] LocationService 新增 `coarseGeohash6` 计算属性 / publisher,基于现有 `currentLocation`
- [ ] 不修改现有精确定位、地理围栏逻辑(回归测试现有 region 行为)
- [ ] geohash6 编码有单元测试(已知坐标 → 已知 hash)
- [ ] `xcodebuild test` 通过

#### US-017: 地图约伴图层(默认关)
**Description:** As a user, I want 在地图上看到附近的约伴网格,so 我能直观发现身边的人。

**Acceptance Criteria:**
- [ ] `CompassMapView` 加一个可选"约伴图层"开关(默认关)
- [ ] 开启时调用 `companion-discover(mode=nearby)`,以 geohash6 网格中心 + "约 600m 内"模糊呈现,**不画精确点**
- [ ] 关闭图层后地图回到现状,无任何约伴元素
- [ ] visibility=off 或未开启 Presence 时,图层入口禁用并解释
- [ ] 在 Simulator 中验证图层开关与模糊网格渲染

#### US-018: 自动过期与清理
**Description:** As a system, I want 自动清理过期的 nearby post 和 stale 数据,so 列表不显示幽灵用户。

**Acceptance Criteria:**
- [ ] nearby post `expires_at ≤ 2h`;发现查询 `expires_at > now()` 过滤(RLS 已含)
- [ ] 定时清理(Supabase scheduled function 或查询时过滤)删除过期 post
- [ ] pending 超时(如 7 天)的 request 自动置 `expired`
- [ ] 单元/集成测试验证过期不出现在发现结果

### 横切 — 安全 / 信任 / 合规

#### US-019: reporterWeight 降权 + 发现排序
**Description:** As a system, I want 用现有信任分给约伴发现排序并对低分用户降权,so 滥用者更难被看到。

**Acceptance Criteria:**
- [ ] Edge Function 发现结果按 `reporter_weight` 降序加权排序
- [ ] 多次被举报触发 `reporter_weight` 下降(规则文档化)
- [ ] 低于阈值的用户不出现在发现列表
- [ ] 单元测试覆盖排序与阈值

#### US-020: 安全文案、未成年人保护与应急条款
**Description:** As a product, I want 在约伴入口与碰头前展示安全提示与免责/举报通道,so 满足合规与用户安全底线。

**Acceptance Criteria:**
- [ ] 首次开启约伴展示安全须知 + 同意条款(碰头前不暴露精确位置、公共场所见面、举报入口)
- [ ] 未成年人保护声明 / 年龄确认
- [ ] App Store 隐私清单(PrivacyInfo)更新:位置、用户内容、联系信息用途
- [ ] UGC(blurb/bio/消息)有最小长度/敏感词基础过滤
- [ ] 法务条款 reviewed(标记为需人工确认的开放项)

#### US-021: 一键全关 / 数据删除
**Description:** As a user, I want 一键关闭所有约伴功能并删除我的约伴数据,so 我能彻底退出社交。

**Acceptance Criteria:**
- [ ] 设置项"关闭约伴并删除我的约伴数据":置 visibility=off、下架所有 post、删除 profile/itinerary 开放标记
- [ ] 关闭后 app 体验与从未启用约伴完全一致
- [ ] 删除走 cascade(profile/posts/requests/conversations 关联清理)
- [ ] 在 Simulator 中验证关闭后无任何约伴痕迹

---

## Functional Requirements

- **FR-1:** 系统必须允许用户创建、编辑、删除**多个** `Itinerary`,每个含 title / cityCode / startDate / endDate / 有序 experienceIds。
- **FR-2:** 系统必须允许把现有 `favoritedExperiences` 导入到指定行程,且不破坏现有收藏行为。
- **FR-3:** 行程默认 `openToCompanions = false`;`CompanionProfile.visibility` 默认 `off`。未启用时,跨用户查询、位置上报、可见性全部为零。
- **FR-4:** 系统必须允许用户设置轻量化名档案(emoji / bio / languages / visibility),**不得**要求或支持真人照上传。
- **FR-5:** 用户必须能把行程标记为开放约伴,生成 `CompanionPost(mode=itinerary)`;关闭时 post 立即下架。
- **FR-6:** 约伴发现必须经由 Edge Function `companion-discover`,按 city_code / geohash6 前缀 / expires_at / 拉黑关系过滤,**仅返回脱敏字段,精确坐标永不返回客户端**。
- **FR-7:** 联系必须经过双向握手:`CompanionRequest` 双方 accept 后才创建 `Conversation`。
- **FR-8:** 聊天必须为 app 内 Supabase Realtime 纯文本,消息 ≤1000 字,仅会话参与者可读写(RLS 强制)。
- **FR-9:** 实时附近(`mode=nearby`)必须仅在前台、用户手动开启时上报 geohash6(~600m);进入后台或关闭开关立即停止并下架;**精确 GPS 不入库、不离开设备**。
- **FR-10:** 系统必须提供举报(`companion_reports`)与拉黑(`companion_blocks`);拉黑双向排除发现与联系。
- **FR-11:** 系统必须复用 `reporterWeight` 对发现结果加权排序,并对低分用户降权 / 隐藏。
- **FR-12:** nearby post `expires_at ≤ 2h`,pending request 超时自动 `expired`,过期数据不出现在发现结果。
- **FR-13:** 系统必须提供"一键全关并删除约伴数据",关闭后体验与未启用完全一致。
- **FR-14:** 所有跨进程实体必须三层对齐(TS core / Swift / SQL)并通过 `pnpm parity:check`。
- **FR-15:** 所有用户可见文案必须经 `NSLocalizedString`(iOS)。
- **FR-16:** 所有约伴后端能力受 `FF_COMPANION` feature flag 控制,默认关闭,可灰度。

## Non-Goals (Out of Scope)

- **不做**真人照片墙、人脸认证、实名认证(本期坚持轻量化名)。
- **不做**第三方 IM 集成 / 跳转外部联系方式作为主路径(app 内 Realtime 文本为唯一沟通通道)。
- **不做**后台持续位置广播(仅前台 + 手动开关)。
- **不做**图片 / 语音 / 文件消息(纯文本)。
- **不做**群组约伴 / 多人行程协作(本期仅一对一握手与会话)。
- **不做**支付 / 拼单 / 费用分摊。
- **不做**全球无差别铺开;**冷启动绑定现有热门 seed 城市**先跑通。
- **不做**精确位置共享(任何阶段);碰头位置由双方在聊天中自行约定。
- **不做**约伴推荐算法的复杂 ML 排序(本期仅基于 city/date/category/reporterWeight 的规则排序)。

## Design Considerations

- **复用现有组件:** Experience 卡片、城市选择器、Map 视图、`SyncService` outbox、`reporterWeight` 信任分、`sc_touch_updated_at` 触发器、`FeatureFlags` 模式。
- **新增视图目录:** `apps/ios/SoloCompass/Views/Companion/`(ItineraryList / ItineraryDetail / CompanionProfile / Discover / RequestInbox / Chat)。
- **地图集成:** 约伴图层是 `CompassMapView` 的**可选叠加**,默认关,不改变现有地图主路径。
- **空状态 / 冷启动:** 发现列表与地图图层都需明确的"本城暂无人约伴"引导,避免空屏挫败。
- **隐私 UI:** 可见性、位置开关、安全须知必须在显眼处,语言中立、无诱导开启。

## Technical Considerations

- **Supabase 已实际接入**(`Config/GeneratedSecrets.swift` + `SupabaseClient.swift`,匿名登录 + Apple ID 升级)。约伴复用此连接与认证。
- **反向 RLS 是最大风险点:** 现有所有表是 `auth.uid()=user_id` 单用户隔离;约伴首次引入跨用户读。必须逐条 review RLS,并把发现查询收敛到 Edge Function(service role)而非客户端全表扫。
- **geohash6 编码** 需在 Swift 与(如有)TS 侧实现一致,并有单测(已知坐标→已知 hash)。
- **Realtime:** 使用 `supabase-swift` 的 Realtime channel;注意连接生命周期与电量(仅在 ChatView 活跃时订阅)。
- **同步:** itinerary 走现有 outbox(`SyncService.enqueue`);约伴动态数据(post/request/message)走直接 API + Realtime,不进 outbox(它们是实时性数据,非离线优先)。
- **Feature flag:** `FF_COMPANION` 控制全部后端能力,默认关,支持分期灰度。
- **App Store:** 位置共享 + 陌生人社交触发更严审查(隐私清单、UGC 政策)。Phase 1 纯本地不受影响;Phase 2/3 需提前准备隐私清单与审核材料。
- **性能:** 发现查询走索引(`posts_discovery_idx` / `posts_geo_idx` / `itineraries_open_idx`);Edge Function 加分页与结果上限。

## Success Metrics

- 启用约伴的用户中,≥30% 创建至少一个开放行程或发起一次请求。
- 发起的约伴请求中,≥40% 在 24h 内得到 accept/decline 响应(非石沉大海)。
- 因隐私顾虑流失为零:**未启用约伴的用户**留存与互动指标相对基线无下降(验证"默认全关"无副作用)。
- 安全事件(举报)处置闭环率 100%(每条举报有结果)。
- geohash6 精确坐标泄漏事件:**0**(以审计与渗透测试验证)。

## Open Questions

1. **法务/合规:** 陌生人线下见面的免责条款、未成年人保护、各司法辖区(尤其首发城市所在国)对位置社交的监管要求 —— 需法务人工确认(标记为人工开放项,不由开发决定)。
2. **冷启动策略:** 首发哪几个 seed 城市?是否需要"种子用户 / 运营预热"机制避免空列表?
3. **reporterWeight 降权具体规则:** 几次举报降多少分?阈值多少隐藏?需产品定校准值。
4. **会话保留期:** 约伴会话是否需自动过期 / 归档(如 30 天无消息)?
5. **多设备 Presence 冲突:** 同一用户多设备同时开 nearby 时如何去重广播?
6. **滥用规模化防御:** 是否需要图形验证 / 速率限制(发帖、发请求)防机器人?(可挂 `sc_function_calls` 现有限流机制)
7. **Apple Sign-In 关联前的约伴:** 匿名用户能否约伴,还是必须先升级为永久账号(降低甩号滥用)?建议约伴强制要求 Apple ID 关联 —— 待确认。
