# 聊天体验升级 — 实现计划与接口契约

> Markdown 渲染 + Instagram 风输入栏 + 全链路附件 + 两套气泡视觉统一。
> 本文是所有实现 agent 的**单一事实源**:接口契约一旦写定,各层按此并行实现,保证对齐。

- **作者**: Claude (Agent Team 交付)
- **日期**: 2026-06-06
- **分支**: `feat/chat-experience-upgrade`
- **状态**: 实现中
- **关联**: 兼容 `docs/PRD/prd-post-pro-chat-rebuild-v1.md`(本文是其未覆盖部分的补充,不冲突)

---

## 0. 决策汇总(已与用户确认)

| 维度 | 决策 |
| --- | --- |
| 范围 | 两套聊天都升级:LLM 对话(ChatSheet/MessageBubble/ChatInputBar)+ Companion DM(ChatView) |
| Markdown | 引入 **swift-markdown-ui 2.4.1**(`from: "2.4.1"`,iOS 15+,项目 17.0 兼容) |
| 附件 | **全链路含上传**;后端 SQL 迁移由 Claude 写,**用户负责部署到 Supabase** |
| 输入栏 | 参考 Instagram DM:加号附件入口 + 相机 + 相册 + 文件,附件预览气泡 |

## 0.1 现实约束(必须遵守)

- Supabase **Storage bucket / RLS 当前不存在**。Claude 交付迁移 SQL,但**无法替用户部署到生产**(权限边界)。未部署前 iOS 上传会 403/404 → UI 必须优雅降级,不能假装发送成功。
- 改 `ChatMessage` 字段触发 `pnpm parity:check`(CI 阻断)。**TS core 与 Swift 模型必须同步改**,字段名/类型/可选性一致。
- 现有 `SupabaseClient.swift` REST 层**未封装 Storage**,需新增 storage upload/signed-url 方法(URLSession 手写,与现有 REST 风格一致)。
- **PRD 既有约束**:所有 AI 调用走 `chat-proxy` Edge function(不引第二条路);复用 `MessageBubble` 玻璃态风格。本次升级不违背。

---

## 1. 技术事实基线

### 1.1 MarkdownUI
- 包:`https://github.com/gonzalezreal/swift-markdown-ui` `from: "2.4.1"`
- 用法:`Markdown(text).markdownTheme(...)`;可 `.markdownTextStyle(.code){...}` 定制代码块字体/底色/前景。
- 流式:逐字追加有渲染压力 → **批量节流(~每 50–80 字或每 80ms 刷新一次)**,避免每 token 重渲。
- ImageRenderer 光栅化未官方保证 → 分享卡**不依赖 MarkdownUI**(沿用既有纯文本路径)。

### 1.2 设计 token(`Views/Shared/CompareTokens.swift` 的 `enum CT`)
聊天相关 token(直接复用,不要硬编码颜色):
- `CT.accent` #5D3000(用户气泡填充/发送按钮/流式光标)
- `CT.surfaceWhite` #FFFFFF · `CT.chatAIBubbleBgDark` #28241E(AI 气泡亮/暗填充,见 `MessageBubble.assistantFill`)
- `CT.borderSubtle` #EDE8DF · `CT.accentBorder` #E8DCCA(气泡边框)
- `CT.chatInputBg` #F5F0EB(输入框亮色填充)· `CT.borderDefault` #D6CEC0(输入栏顶分隔)
- `CT.sunGold/sunGoldDeep/sunGoldSoft`(语音态)· `CT.bannerError` #C03B1E
- 字体:聊天用系统字体;`CT.mono(_:)` = `.system(design:.monospaced)` 给代码块用。

### 1.3 现有数值(统一基线)
- 气泡圆角 18pt(Voice)/ 16pt(Companion)→ **统一为 18pt continuous**
- 气泡内边距 14×9;输入框内边距 12×8;输入框圆角 18pt
- Avatar 32(Voice)/ 22(Companion);mic 按钮 40×40 圆角 12
- 边框 0.5pt;阴影 user(r6,y2)/ ai(r4,y1)

---

## 2. 接口契约(各层必须严格一致)

### 2.1 附件数据模型(TS + Swift 同步)

**`packages/core/src/companion.ts`** 新增:
```ts
export interface ChatAttachment {
  readonly id: string;
  readonly kind: "image" | "file";
  readonly fileName: string;
  readonly mimeType: string;
  readonly fileSizeBytes: number;
  readonly storagePath: string;     // bucket 内路径:"{conversationId}/{messageId}/{attachmentId}-{fileName}"
  readonly width?: number;          // image only
  readonly height?: number;         // image only
}

export interface ChatMessage {
  readonly id: ChatMessageId;
  readonly conversationId: ConversationId;
  readonly senderId: UserId;
  readonly body: string;
  readonly attachments?: readonly ChatAttachment[];   // ← 新增,可选,默认空
  readonly readAt?: string;
  readonly createdAt: string;
}
```

**`apps/ios/.../Models/ChatMessage.swift`** 镜像:
```swift
public struct ChatAttachment: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let kind: Kind            // image | file (String raw)
    public let fileName: String
    public let mimeType: String
    public let fileSizeBytes: Int
    public let storagePath: String
    public let width: Int?
    public let height: Int?
    public enum Kind: String, Codable, Sendable { case image, file }
}
// ChatMessage 加 `public let attachments: [ChatAttachment]?`
```

> parity:check 要求字段集合一致。`attachments` 在两侧都加。先跑 `pnpm parity:check` 看脚本对嵌套 ChatAttachment 的处理,再据报错调整。

### 2.2 后端迁移(`infra/supabase/migrations/0005_chat_attachments.sql`)
- 在 `chat_messages` 加 `attachments jsonb`(选 JSON 列,避免连表;与 TS 的 `attachments?` 对齐)。
- 创建 private bucket `chat-media`。
- RLS:仅会话参与者可 upload(insert)到 `{conversationId}/...` 前缀、可 select(下载用 signed URL)。
- 文件含完整可执行 SQL + 顶部注释「部署方式:supabase db push 或控制台 SQL editor」。

### 2.3 iOS 上传服务(`Services/ChatAttachmentService.swift`,新增)
```swift
protocol AttachmentUploading {
    /// 上传到 chat-media bucket,返回可写入消息的 ChatAttachment 元数据。
    func upload(_ local: LocalAttachment, conversationId: String, messageId: String) async throws -> ChatAttachment
    /// 取下载用 signed URL(有效期 ~1h)。
    func signedURL(for attachment: ChatAttachment) async throws -> URL
}
```
- 真实实现 `SupabaseAttachmentService`:`POST /storage/v1/object/chat-media/{path}` + `POST /storage/v1/object/sign/...`。
- **后端未部署时**:upload 抛明确错误 → UI 显示「附件后端未就绪」,文本消息仍可发。

### 2.4 输入栏附件回调
```swift
// 草稿态附件,发送前持有
struct LocalAttachment: Identifiable, Equatable {
    let id: UUID
    let kind: ChatAttachment.Kind
    let fileName: String
    let mimeType: String
    let data: Data
    let image: UIImage?    // 预览缩略图(image kind)
}
// 输入栏新增:
//   @Binding var attachments: [LocalAttachment]
//   内置 PhotosPicker + .fileImporter + 相机入口;发送时把 attachments 一并交给 onSend
```

---

## 3. 文件清单与分工(并行批次)

### Batch A — 数据契约层(必须先做,其它依赖它)
- `packages/core/src/companion.ts` [改] 加 ChatAttachment + ChatMessage.attachments
- `apps/ios/.../Models/ChatMessage.swift` [改] 镜像
- `infra/supabase/migrations/0005_chat_attachments.sql` [新] 迁移 + bucket + RLS
- 验收:`pnpm parity:check` 绿

### Batch B — Markdown 渲染(依赖 A 完成 SwiftPM 接入)
- `apps/ios/project.yml` [改] 加 swift-markdown-ui 依赖 → `xcodegen`
- `apps/ios/.../Views/Chat/MarkdownMessageText.swift` [新] 封装 `Markdown(...)` + 聊天主题(代码块/inline code/链接/列表/引用样式,亮暗自适应,用 CT token)
- `apps/ios/.../Views/Chat/MessageBubble.swift` [改] assistant 气泡文本改用 MarkdownMessageText;user 气泡保持纯文本;流式节流
- 验收:构建绿;/tmp PNG 视觉验证 md(代码块/列表/加粗/链接/引用)

### Batch C — Instagram 风输入栏 + 附件 UI(依赖 A 的 LocalAttachment)
- `apps/ios/.../Views/Chat/ChatInputBar.swift` [改] 加「+」附件菜单(相机/相册/文件)、PhotosPicker、.fileImporter、草稿附件预览条
- `apps/ios/.../Views/Chat/AttachmentDraftStrip.swift` [新] 横向草稿附件缩略图 + 删除
- `apps/ios/.../Views/Chat/AttachmentBubble.swift` [新] 已发消息里的附件渲染(图片缩略图点开大图 / 文件卡片)
- `apps/ios/.../Views/Companion/ChatView.swift` [改] inputBar 同款附件入口 + 气泡渲染 attachments
- 验收:构建绿;选图/选文件/预览/删除可用;视觉对齐 Instagram DM

### Batch D — 服务/数据流(依赖 A、C)
- `apps/ios/.../Services/ChatAttachmentService.swift` [新] AttachmentUploading + Supabase 实现 + 未部署降级
- `apps/ios/.../Services/SupabaseClient.swift` [改] 加 storage upload/sign 方法
- `apps/ios/.../Services/ChatService.swift` [改] send 接收 attachments:先上传 → 写入 message.attachments;handleInsert 解析 attachments
- Voice Agent 侧附件本期**只做 UI 展示**(LLM 多模态接入留接口);**重点跑通 Companion DM 全链路**
- 验收:构建绿;mock 上传单测;parity 绿

### Batch E — 气泡视觉统一打磨(依赖 B、C)
- 两套气泡统一 18pt continuous、CT token、阴影/边框基线;时间戳/已读/sender 名排版精修
- `#Preview` 覆盖:user/assistant/含 md/含图片/含文件/流式
- 验收:/tmp PNG 全场景视觉验收

### Batch F — 测试 + 本地化 + 验证
- `Tests/MarkdownMessageTextTests.swift`、`Tests/ChatAttachmentServiceTests.swift`、`Tests/ChatMessageAttachmentParsingTests.swift`
- `Resources/en.lproj/Localizable.strings` 新 key(附件入口/错误/占位)
- `xcodegen` → build → test(`Executed N>0`);`pnpm parity:check`

---

## 4. 验收标准(满分清单)

- [ ] LLM 回复 Markdown 优雅渲染:代码块(等宽+底色)、有序/无序/任务列表、加粗斜体、行内代码、链接、引用块、标题 —— 亮暗模式都正确。
- [ ] 流式回复时 Markdown 平滑增量渲染,不卡顿(节流生效)。
- [ ] 输入栏 Instagram 风:文本 + 「+」附件菜单(相机/相册/文件),草稿附件横向预览可删。
- [ ] 选图(PhotosPicker)/ 选文件(.fileImporter)可用;附件随消息发送(后端就绪时真上传,未就绪时明确降级提示且文本仍可发)。
- [ ] 收到的消息正确渲染附件:图片缩略图可点开、文件显示卡片。
- [ ] 两套气泡视觉统一、精致(圆角/内边距/阴影/边框/配色用 CT token)。
- [ ] `xcodebuild build` 绿;聊天相关 XCTest 绿(真实 Executed N>0);`pnpm parity:check` 绿。
- [ ] 交付 SQL 迁移文件 + 部署说明给用户;明确标注「后端需用户部署」。
- [ ] 关键路径 /tmp PNG 肉眼验证出片质量。

## 5. 风险登记

- MarkdownUI 在 ImageRenderer/流式下的性能 → 节流 + 分享卡不走 md。
- parity:check 对嵌套 ChatAttachment 的处理未知 → A 批先跑 parity 看报错再定形。
- Storage RLS 写错会导致全员可读他人附件 → RLS 用会话参与者校验,迁移里写测试注释。
- 后端未部署 → 全链路「最后一公里」不在 Claude 手里,UI 必须优雅降级,不能假装发成功。
- supabase-swift storage vs 手写 URLSession → 优先手写(SupabaseClient 已是手写 REST 风格,一致)。
