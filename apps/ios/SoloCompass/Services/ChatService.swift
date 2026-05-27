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
    private var sdkClient: Supabase.SupabaseClient?
    private var realtimeTask: Task<Void, Never>?
    /// ISO 8601 timestamp of the latest message received locally.
    private var lastSeen: String?

    public init(
        conversationId: ConversationId,
        client: SupabaseClientProtocol = SupabaseClient.shared
    ) {
        self.conversationId = conversationId
        self.restClient = client
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
        guard FeatureFlags.companion else { return }
        guard let userId = restClient.currentSession?.userId else {
            lastError = NSLocalizedString("companion.chat.error.auth", comment: "Not signed in")
            return
        }
        let trimmed = String(text.prefix(1000))
        guard !trimmed.isEmpty else { return }

        isSending = true
        lastError = nil
        defer { isSending = false }

        let now = ISO8601DateFormatter().string(from: Date())
        let msg = ChatMessage(
            id: ChatMessageId(rawValue: UUID().uuidString),
            conversationId: conversationId,
            senderId: userId,
            body: trimmed,
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
        case .failure(let err):
            lastError = err.localizedDescription
        }
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
            readAt: readAt,
            createdAt: createdStr
        )
        appendIfNew(msg)
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
