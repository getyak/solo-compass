import Foundation

/// Uploads draft attachments to Supabase Storage and resolves download URLs.
///
/// Mirrors the design doc §2.3. The protocol seam lets `ChatService` inject a
/// mock in tests and lets the UI degrade gracefully when the storage backend
/// (bucket `chat-media` + RLS) has not been deployed yet.
@MainActor
public protocol AttachmentUploading {
    /// Upload one draft to the `chat-media` bucket and return the persisted
    /// `ChatAttachment` metadata ready to write into a message row.
    func upload(_ local: LocalAttachment, conversationId: String, messageId: String) async throws -> ChatAttachment
    /// Resolve a short-lived (~1h) signed URL for downloading an attachment.
    func signedURL(for attachment: ChatAttachment) async throws -> URL
}

/// Typed, user-presentable failures from the attachment pipeline.
///
/// `backendNotReady` is the critical case: the user has not deployed the
/// Storage bucket / RLS migration yet, so any 400/401/403/404 from storage is
/// surfaced as a clear "deploy the backend" message rather than a generic
/// failure — the UI degrades by still sending the text-only message.
public enum AttachmentError: Error, LocalizedError, Sendable {
    case backendNotReady
    case tooLarge
    case rateLimited
    case uploadFailed(Int)
    case notSignedIn
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .backendNotReady:
            return NSLocalizedString(
                "companion.chat.attachment.backendNotReady",
                comment: "Attachments need the storage backend deployed"
            )
        case .tooLarge:
            return NSLocalizedString(
                "companion.chat.attachment.tooLarge",
                comment: "Attachment is too large to upload"
            )
        case .rateLimited:
            return NSLocalizedString(
                "companion.chat.attachment.rateLimited",
                comment: "Too many uploads — try again shortly"
            )
        case .uploadFailed(let status):
            return String(
                format: NSLocalizedString(
                    "companion.chat.attachment.uploadFailed",
                    comment: "Attachment upload failed (HTTP %d)"
                ),
                status
            )
        case .notSignedIn:
            return NSLocalizedString(
                "companion.chat.attachment.notSignedIn",
                comment: "Sign in to send attachments"
            )
        case .badResponse:
            return NSLocalizedString(
                "companion.chat.attachment.badResponse",
                comment: "Attachment service returned an unexpected response"
            )
        }
    }
}

/// Real implementation backed by Supabase Storage's REST endpoints.
///
/// Hand-written URLSession to match `SupabaseClient`'s dependency-free REST
/// style (the SDK's storage wrapper is intentionally not used). Config (base
/// URL + anon key) is read the SAME way `SupabaseClient.loadConfig` does:
/// env override → bundled `Secrets.plist` → build-time `GeneratedSecrets`.
@MainActor
public final class SupabaseAttachmentService: AttachmentUploading {

    /// Storage bucket holding all chat media. Created by migration 0005.
    private static let bucket = "chat-media"

    private let client: SupabaseClientProtocol
    private let urlSession: URLSession

    public init(
        client: SupabaseClientProtocol = SupabaseClient.shared,
        urlSession: URLSession = .shared
    ) {
        self.client = client
        self.urlSession = urlSession
    }

    // MARK: - Config (mirrors SupabaseClient.loadConfig)

    private struct Config { let url: URL; let anonKey: String }

    private func loadConfig() -> Config? {
        let envURL = ProcessInfo.processInfo.environment["SUPABASE_URL"]
        let envKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ProcessInfo.processInfo.environment["SUPABASE_KEY"]
        let urlStr = envURL ?? plistValue("SUPABASE_URL")
            ?? (Secrets.supabaseURL.isEmpty ? nil : Secrets.supabaseURL)
        let key = envKey ?? plistValue("SUPABASE_ANON_KEY") ?? plistValue("SUPABASE_KEY")
            ?? (Secrets.supabaseAnonKey.isEmpty ? nil : Secrets.supabaseAnonKey)
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

    // MARK: - Upload

    public func upload(
        _ local: LocalAttachment,
        conversationId: String,
        messageId: String
    ) async throws -> ChatAttachment {
        guard let cfg = loadConfig() else { throw AttachmentError.backendNotReady }
        guard let token = client.currentSession?.accessToken else { throw AttachmentError.notSignedIn }

        let attachmentId = UUID().uuidString
        // Path convention from the design doc:
        // "{conversationId}/{messageId}/{attachmentId}-{fileName}".
        let path = "\(conversationId)/\(messageId)/\(attachmentId)-\(local.fileName)"
        guard let objectURL = storageURL(base: cfg.url, suffix: "object/\(Self.bucket)/\(path)") else {
            throw AttachmentError.badResponse
        }

        var req = URLRequest(url: objectURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        req.setValue(local.mimeType, forHTTPHeaderField: "Content-Type")
        // Idempotent re-send on retry: overwrite rather than 409 on duplicate.
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = local.data

        let status = try await send(req)
        guard (200..<300).contains(status) else {
            throw Self.mapStatus(status)
        }

        let width = local.image.map { Int($0.size.width) }
        let height = local.image.map { Int($0.size.height) }
        return ChatAttachment(
            id: attachmentId,
            kind: local.kind,
            fileName: local.fileName,
            mimeType: local.mimeType,
            fileSizeBytes: local.data.count,
            storagePath: path,
            width: local.kind == .image ? width : nil,
            height: local.kind == .image ? height : nil
        )
    }

    // MARK: - Signed URL

    public func signedURL(for attachment: ChatAttachment) async throws -> URL {
        guard let cfg = loadConfig() else { throw AttachmentError.backendNotReady }
        guard let token = client.currentSession?.accessToken else { throw AttachmentError.notSignedIn }
        guard let signURL = storageURL(base: cfg.url, suffix: "object/sign/\(Self.bucket)/\(attachment.storagePath)") else {
            throw AttachmentError.badResponse
        }

        var req = URLRequest(url: signURL)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["expiresIn": 3600])

        let (data, response) = try await urlSession.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw AttachmentError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapStatus(http.statusCode)
        }

        struct SignResponse: Decodable { let signedURL: String }
        guard let resp = try? JSONDecoder().decode(SignResponse.self, from: data) else {
            throw AttachmentError.badResponse
        }
        // Supabase returns a relative path ("/storage/v1/...") — resolve it
        // against the project base URL to get an absolute, fetchable URL.
        let relative = resp.signedURL.hasPrefix("/") ? String(resp.signedURL.dropFirst()) : resp.signedURL
        guard let absolute = URL(string: relative, relativeTo: cfg.url)?.absoluteURL else {
            throw AttachmentError.badResponse
        }
        return absolute
    }

    // MARK: - Internals

    /// Maps a non-2xx storage status to a user-meaningful error.
    /// - 400/401/403/404 → `backendNotReady` (bucket / RLS not deployed yet — the
    ///   dominant pre-deploy case; UI degrades to text-only).
    /// - 413 → `tooLarge`, 429 → `rateLimited` (actionable user feedback rather
    ///   than a bare HTTP code).
    /// - anything else → `uploadFailed(status)`.
    static func mapStatus(_ status: Int) -> AttachmentError {
        switch status {
        case 400, 401, 403, 404: return .backendNotReady
        case 413:                return .tooLarge
        case 429:                return .rateLimited
        default:                 return .uploadFailed(status)
        }
    }

    /// Builds a `/storage/v1/{suffix}` URL, percent-encoding path segments so
    /// file names with spaces / unicode survive the round trip.
    private func storageURL(base: URL, suffix: String) -> URL? {
        let encoded = suffix
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "storage/v1/\(encoded)", relativeTo: base)?.absoluteURL
    }

    /// Performs the request and returns the HTTP status code.
    private func send(_ request: URLRequest) async throws -> Int {
        let (_, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AttachmentError.badResponse }
        return http.statusCode
    }
}
