import Foundation
import Observation
import Supabase

/// Realtime chat service for a single conversation (US-013).
///
/// Uses Supabase Realtime (supabase-swift SDK v2) to subscribe to postgres
/// INSERT events on `chat_messages` filtered by `conversation_id`.
/// On reconnect the channel re-subscribes and we re-fetch messages since
/// `lastSeen` so no messages are missed during network gaps.
///
/// All network calls are gated by `FeatureFlags.companion`. When the flag
/// is off, send is a no-op and the message list stays empty.
@Observable
@MainActor
public final class ChatService {
    public var messages: [ChatMessage] = []
    public var isSending = false
    public var lastError: String?

    private let conversationId: ConversationId
    private let restClient: SupabaseClientProtocol
    /// Uploads draft attachments to Storage before the message row is written.
    /// Injectable so tests can supply a mock (and assert the degrade path).
    private let attachmentService: AttachmentUploading
    private var sdkClient: Supabase.SupabaseClient?
    private var realtimeTask: Task<Void, Never>?
    /// ISO 8601 timestamp of the latest message received locally.
    private var lastSeen: String?

    public init(
        conversationId: ConversationId,
        client: SupabaseClientProtocol = SupabaseClient.shared,
        attachmentService: AttachmentUploading = SupabaseAttachmentService()
    ) {
        self.conversationId = conversationId
        self.restClient = client
        self.attachmentService = attachmentService
    }

    // MARK: - Lifecycle

    /// Load history then open the realtime subscription.
    public func start() async {
        guard FeatureFlags.companion else { return }
        await fetchHistory(since: nil)
        startRealtime()
    }

    /// Cancel the realtime subscription.
    public func stop() {
        realtimeTask?.cancel()
        realtimeTask = nil
        sdkClient = nil
    }

    // MARK: - Send

    /// Send a plain-text message (≤1000 chars). Enforced client-side; RLS
    /// ensures only conversation participants can insert.
    public func send(_ text: String) async {
        await send(text, attachments: [])
    }

    /// Send a message with optional attachments. Attachments are uploaded to
    /// Storage first, then their metadata is written into the message's
    /// `attachments` jsonb column.
    ///
    /// Degrade path: if the storage backend isn't deployed yet (any upload
    /// throws `.backendNotReady`), we surface a clear error and STILL send the
    /// text-only message so the user never loses their words.
    public func send(_ text: String, attachments: [LocalAttachment]) async {
        guard FeatureFlags.companion else { return }
        guard let userId = restClient.currentSession?.userId else {
            lastError = NSLocalizedString("companion.chat.error.auth", comment: "Not signed in")
            return
        }
        let trimmed = String(text.prefix(1000))
        // Allow attachment-only messages, but a fully empty send is a no-op.
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        isSending = true
        lastError = nil
        defer { isSending = false }

        // Generate the messageId up front so uploaded objects can be keyed by
        // it ("{conversationId}/{messageId}/...") before the row is written.
        let messageId = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())

        // All-or-nothing upload: if ANY attachment fails, drop them ALL and keep
        // only the text. Sending a message with a silent subset of attachments
        // (e.g. 2 of 3, where #2 was too large) is a data-integrity trap — the
        // recipient sees an incomplete set and the sender only sees one error.
        var uploaded: [ChatAttachment] = []
        var attachmentsDropped = false
        for local in attachments {
            do {
                let attachment = try await attachmentService.upload(
                    local,
                    conversationId: conversationId.rawValue,
                    messageId: messageId
                )
                uploaded.append(attachment)
            } catch {
                // Surface the specific reason (backendNotReady / tooLarge /
                // rateLimited / uploadFailed) but treat every failure the same:
                // abandon the whole attachment set, keep the text.
                lastError = error.localizedDescription
                attachmentsDropped = true
                uploaded.removeAll()
                break
            }
        }

        if attachmentsDropped {
            // If there's no text to fall back on, there's nothing to send — the
            // user must retry the attachments rather than receive an empty row.
            guard !trimmed.isEmpty else { return }
        }

        let msg = ChatMessage(
            id: ChatMessageId(rawValue: messageId),
            conversationId: conversationId,
            senderId: userId,
            body: trimmed,
            attachments: uploaded.isEmpty ? nil : uploaded,
            createdAt: now
        )

        guard let data = try? JSONEncoder.iso8601Encoder.encode(msg) else {
            lastError = NSLocalizedString("companion.chat.error.encode", comment: "Encode failed")
            return
        }

        let result = await restClient.post(table: "chat_messages", body: data)
        switch result {
        case .success:
            // Optimistic append; dedup guard prevents doubles from realtime echo.
            appendIfNew(msg)
            // US-024: wake the OTHER party's backgrounded device with an APNs
            // banner. Fire-and-forget — the row is already written and Realtime
            // is the source of truth, so any push failure must never fail send.
            notifyRecipientOfMessage(messageId: messageId)
        case .failure(let err):
            lastError = err.localizedDescription
        }
    }

    // MARK: - US-024: APNs message push trigger

    /// Fire the `message-notify` Edge Function so the conversation's other party
    /// gets a "new message" banner when their device is backgrounded.
    ///
    /// The function derives the recipient(s) server-side (participants − sender)
    /// and never pushes the sender. Errors (feature off, no token, APNs failure)
    /// are swallowed so the push can never affect the send result.
    private func notifyRecipientOfMessage(messageId: String) {
        Task { @MainActor in
            let payload: [String: String] = ["messageId": messageId]
            guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
            _ = await restClient.invoke(function: "message-notify", body: data)
        }
    }

    /// Resolve a short-lived signed download URL for a persisted attachment,
    /// delegating to the same injected `AttachmentUploading` service used for
    /// upload. Returns `nil` (rather than throwing) so the UI degrades to a
    /// placeholder when the storage backend isn't deployed yet.
    public func resolveAttachmentURL(_ attachment: ChatAttachment) async -> URL? {
        try? await attachmentService.signedURL(for: attachment)
    }

    // MARK: - History fetch

    private func fetchHistory(since: String?) async {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "conversation_id", value: "eq.\(conversationId.rawValue)"),
            URLQueryItem(name: "order", value: "created_at.asc"),
        ]
        if let since {
            query.append(URLQueryItem(name: "created_at", value: "gt.\(since)"))
        }

        let result = await restClient.get(table: "chat_messages", query: query)
        if case .success(let data) = result, !data.isEmpty {
            if let fetched = try? JSONDecoder.iso8601Decoder.decode([ChatMessage].self, from: data) {
                fetched.forEach { appendIfNew($0) }
            }
        }
    }

    // MARK: - Realtime (Supabase SDK v2)

    private func startRealtime() {
        guard let cfg = loadConfig() else { return }
        guard restClient.currentSession?.accessToken != nil else { return }

        let client = Supabase.SupabaseClient(
            supabaseURL: cfg.url,
            supabaseKey: cfg.anonKey
        )
        sdkClient = client

        let convId = conversationId.rawValue

        realtimeTask = Task {
            let channel = client.channel("chat:\(convId)")

            let changes = channel.postgresChange(
                InsertAction.self,
                schema: "public",
                table: "chat_messages",
                filter: "conversation_id=eq.\(convId)"
            )

            await channel.subscribe()

            // After (re)subscribing, backfill any messages we may have missed.
            await self.fetchHistory(since: self.lastSeen)

            for await action in changes {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.handleInsert(action)
                }
            }
        }
    }

    private func handleInsert(_ action: InsertAction) {
        let record = action.record
        guard
            case .string(let idStr) = record["id"],
            case .string(let convIdStr) = record["conversation_id"],
            case .string(let senderStr) = record["sender_id"],
            case .string(let bodyStr) = record["body"],
            case .string(let createdStr) = record["created_at"],
            convIdStr == conversationId.rawValue
        else { return }

        let readAt: String?
        if case .string(let rs) = record["read_at"] {
            readAt = rs
        } else {
            readAt = nil
        }

        let msg = ChatMessage(
            id: ChatMessageId(rawValue: idStr),
            conversationId: ConversationId(rawValue: convIdStr),
            senderId: senderStr,
            body: bodyStr,
            attachments: decodeAttachments(from: record["attachments"]),
            readAt: readAt,
            createdAt: createdStr
        )
        appendIfNew(msg)
    }

    /// Defensively decode the realtime record's `attachments` jsonb value into
    /// `[ChatAttachment]`. Returns nil when the column is absent, null, or
    /// malformed — never crashes. Re-encodes the `AnyJSON` value to bytes and
    /// runs it through the same Codable path used for REST payloads.
    private func decodeAttachments(from value: AnyJSON?) -> [ChatAttachment]? {
        guard let value, case .array = value else { return nil }
        guard let data = try? JSONEncoder().encode(value),
              let attachments = try? JSONDecoder().decode([ChatAttachment].self, from: data),
              !attachments.isEmpty
        else { return nil }
        return attachments
    }

    // MARK: - Helpers

    private func appendIfNew(_ msg: ChatMessage) {
        guard !messages.contains(where: { $0.id == msg.id }) else { return }
        messages.append(msg)
        messages.sort { $0.createdAt < $1.createdAt }
        lastSeen = messages.last?.createdAt
    }

    private struct Config { let url: URL; let anonKey: String }

    private func loadConfig() -> Config? {
        let envURL = ProcessInfo.processInfo.environment["SUPABASE_URL"]
        let envKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ProcessInfo.processInfo.environment["SUPABASE_KEY"]
        let urlStr = envURL ?? plistValue("SUPABASE_URL")
        let key = envKey ?? plistValue("SUPABASE_ANON_KEY") ?? plistValue("SUPABASE_KEY")
        guard let urlStr, let url = URL(string: urlStr), let key, !key.isEmpty else { return nil }
        return Config(url: url, anonKey: key)
    }

    private func plistValue(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }
}
