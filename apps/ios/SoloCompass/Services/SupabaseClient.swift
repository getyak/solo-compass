import Foundation
import Observation

/// Protocol allowing `DeviceIdentityService` (and tests) to inject a
/// different back-end without touching the singleton.
@MainActor
public protocol SupabaseClientProtocol: AnyObject {
    var currentSession: SupabaseClient.Session? { get }
    func signInAnonymously() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError>
    func refreshSession() async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError>
    func post(table: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError>
    func get(table: String, query: [URLQueryItem]) async -> Result<Data, SupabaseClient.SupabaseError>
    func invoke(function: String, body: Data) async -> Result<Data, SupabaseClient.SupabaseError>
    /// Link an anonymous account to an Apple ID using the credential from
    /// ASAuthorizationAppleIDCredential. Returns the updated session whose
    /// userId is now the permanent (non-anonymous) Supabase user id.
    func linkAppleIdentity(identityToken: String, nonce: String) async -> Result<SupabaseClient.Session, SupabaseClient.SupabaseError>
    /// Whether the current session belongs to an anonymous (not yet linked) user.
    var isAnonymous: Bool { get async }
}

/// Minimal Supabase REST client using URLSession — no third-party SDK.
///
/// This keeps the iOS bundle dep-free (project rule: zero deps where
/// reasonable) and lets us ship the same API surface no matter which
/// version of supabase-swift is current. The trade-off: realtime
/// subscriptions and storage are not wrapped here. We don't need them
/// for v1.1 (sync is poll-based, not realtime).
///
/// All methods are gated by `FeatureFlags.backendSync`. When the flag
/// is off (default in beta.1), every method short-circuits to a
/// "do nothing" path that returns the empty / success equivalent. This
/// preserves PRD G7 (local-first invariant): the app stays fully
/// usable when the backend is unreachable.
@Observable
@MainActor
public final class SupabaseClient: SupabaseClientProtocol {
    public static let shared = SupabaseClient()

    public enum SupabaseError: Error, LocalizedError, Sendable {
        case missingConfig
        case requestFailed(status: Int, body: String)
        case decoding(String)
        case notSignedIn
        case backendDisabled

        public var errorDescription: String? {
            switch self {
            case .missingConfig:        return "Supabase URL/key missing"
            case .requestFailed(let s, let b): return "Supabase HTTP \(s): \(b)"
            case .decoding(let m):      return "Supabase decode failed: \(m)"
            case .notSignedIn:          return "No active Supabase session"
            case .backendDisabled:      return "Backend sync feature flag is off"
            }
        }
    }

    public struct Session: Codable, Sendable {
        public let userId: String
        public let accessToken: String
        public let refreshToken: String
        public let expiresAt: Date

        public var isExpired: Bool { expiresAt <= Date() }
    }

    /// Read the active session from Keychain. May return nil if the
    /// user has never signed in or the session was cleared.
    public var currentSession: Session? {
        guard let blob = KeychainStore.read(account: Self.sessionKey),
              let data = blob.data(using: .utf8),
              let s = try? JSONDecoder.iso8601Decoder.decode(Session.self, from: data)
        else { return nil }
        return s
    }

    private static let sessionKey = "sc.supabase.session"

    private let urlSession: URLSession
    public init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    // MARK: - Config

    private struct Config {
        let url: URL
        let anonKey: String
    }

    private static func loadConfig() -> Config? {
        let envURL = ProcessInfo.processInfo.environment["SUPABASE_URL"]
        let envKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]
            ?? ProcessInfo.processInfo.environment["SUPABASE_KEY"]
        let urlString = envURL ?? readSecretsString("SUPABASE_URL")
        let key = envKey ?? readSecretsString("SUPABASE_ANON_KEY") ?? readSecretsString("SUPABASE_KEY")
        guard let urlString, let url = URL(string: urlString), let key, !key.isEmpty else {
            return nil
        }
        return Config(url: url, anonKey: key)
    }

    private static func readSecretsString(_ key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist[key] as? String
    }

    // MARK: - Auth

    /// Anonymous sign-in. Persists the session to Keychain; subsequent
    /// `currentSession` reads return it. Returns `.failure(.backendDisabled)`
    /// when `FF_BACKEND_SYNC` is off — callers should treat that as a
    /// no-op, not a real error.
    @discardableResult
    public func signInAnonymously() async -> Result<Session, SupabaseError> {
        guard FeatureFlags.backendSync else {
            return .failure(.backendDisabled)
        }
        if let s = currentSession, !s.isExpired {
            return .success(s)
        }
        // Session exists but is expired — try the refresh-token flow first.
        if let s = currentSession, s.isExpired, !s.refreshToken.isEmpty {
            let refreshResult = await refreshSession()
            if case .success = refreshResult { return refreshResult }
            // Refresh failed (token revoked, network error) — fall through to fresh signup.
        }
        guard let cfg = Self.loadConfig() else { return .failure(.missingConfig) }

        var req = URLRequest(url: cfg.url.appendingPathComponent("/auth/v1/signup"))
        req.httpMethod = "POST"
        req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Supabase anonymous signup: empty body + apikey is enough.
        req.httpBody = "{}".data(using: .utf8)

        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.requestFailed(status: 0, body: ""))
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(.requestFailed(status: http.statusCode,
                                               body: String(data: data, encoding: .utf8) ?? ""))
            }
            struct AuthResponse: Decodable {
                let access_token: String
                let refresh_token: String
                let expires_in: Int
                let user: AuthUser
            }
            struct AuthUser: Decodable { let id: String }
            let resp = try JSONDecoder().decode(AuthResponse.self, from: data)
            let s = Session(
                userId: resp.user.id,
                accessToken: resp.access_token,
                refreshToken: resp.refresh_token,
                expiresAt: Date().addingTimeInterval(TimeInterval(resp.expires_in))
            )
            persist(s)
            return .success(s)
        } catch {
            return .failure(.requestFailed(status: 0, body: error.localizedDescription))
        }
    }

    /// Refresh an expired session using the stored refresh token.
    /// Returns `.failure(.backendDisabled)` when `FF_BACKEND_SYNC` is off.
    /// Returns `.failure(.notSignedIn)` when there is no session to refresh.
    @discardableResult
    public func refreshSession() async -> Result<Session, SupabaseError> {
        guard FeatureFlags.backendSync else {
            return .failure(.backendDisabled)
        }
        guard let s = currentSession, !s.refreshToken.isEmpty else {
            return .failure(.notSignedIn)
        }
        guard let cfg = Self.loadConfig() else { return .failure(.missingConfig) }

        var req = URLRequest(url: cfg.url.appendingPathComponent("/auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")]))
        req.httpMethod = "POST"
        req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try? JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
        req.httpBody = body

        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.requestFailed(status: 0, body: ""))
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(.requestFailed(status: http.statusCode,
                                               body: String(data: data, encoding: .utf8) ?? ""))
            }
            struct RefreshResponse: Decodable {
                let access_token: String
                let refresh_token: String
                let expires_in: Int
                let user: RefreshUser
            }
            struct RefreshUser: Decodable { let id: String }
            let resp = try JSONDecoder().decode(RefreshResponse.self, from: data)
            let refreshed = Session(
                userId: resp.user.id,
                accessToken: resp.access_token,
                refreshToken: resp.refresh_token,
                expiresAt: Date().addingTimeInterval(TimeInterval(resp.expires_in))
            )
            persist(refreshed)
            return .success(refreshed)
        } catch {
            return .failure(.requestFailed(status: 0, body: error.localizedDescription))
        }
    }

    /// Clear the local session. Does not invalidate it server-side
    /// (Supabase anonymous sessions don't have a sign-out endpoint
    /// per se; we just discard the token).
    public func signOut() {
        _ = KeychainStore.delete(account: Self.sessionKey)
    }

    // MARK: - US-036: Apple ID link

    /// Link the current anonymous account to an Apple ID.
    ///
    /// Calls `POST /auth/v1/user/identities/authorize` with the Apple
    /// OIDC credential. On success Supabase converts the anonymous user
    /// to a permanent user and issues a new session with a new userId
    /// (the permanent one). We persist the new session so every
    /// subsequent `currentSession` read returns the permanent identity.
    ///
    /// Returns `.failure(.backendDisabled)` when `FF_BACKEND_SYNC` is off.
    @discardableResult
    public func linkAppleIdentity(identityToken: String, nonce: String) async -> Result<Session, SupabaseError> {
        guard FeatureFlags.backendSync else { return .failure(.backendDisabled) }
        guard let cfg = Self.loadConfig() else { return .failure(.missingConfig) }
        guard let token = currentSession?.accessToken else { return .failure(.notSignedIn) }

        var req = URLRequest(url: cfg.url.appendingPathComponent("/auth/v1/user/identities/authorize"))
        req.httpMethod = "POST"
        req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyDict: [String: Any] = [
            "provider": "apple",
            "id_token": identityToken,
            "nonce": nonce,
            "skip_http_redirect": true,
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: bodyDict) else {
            return .failure(.decoding("could not encode link body"))
        }
        req.httpBody = bodyData

        do {
            let (data, response) = try await urlSession.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.requestFailed(status: 0, body: ""))
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(.requestFailed(status: http.statusCode,
                                               body: String(data: data, encoding: .utf8) ?? ""))
            }
            struct LinkResponse: Decodable {
                let access_token: String
                let refresh_token: String
                let expires_in: Int
                let user: LinkUser
            }
            struct LinkUser: Decodable { let id: String }
            let resp = try JSONDecoder().decode(LinkResponse.self, from: data)
            let s = Session(
                userId: resp.user.id,
                accessToken: resp.access_token,
                refreshToken: resp.refresh_token,
                expiresAt: Date().addingTimeInterval(TimeInterval(resp.expires_in))
            )
            persist(s)
            return .success(s)
        } catch {
            return .failure(.requestFailed(status: 0, body: error.localizedDescription))
        }
    }

    /// Query Supabase `/auth/v1/user` to check whether the current user is
    /// still anonymous. Returns `true` when the user has not yet linked an
    /// Apple ID (or any other provider). Returns `false` when not signed in or
    /// when `FF_BACKEND_SYNC` is off (treat as non-anonymous to avoid surfacing
    /// the sign-in prompt when the backend is unreachable).
    public var isAnonymous: Bool {
        get async {
            guard FeatureFlags.backendSync else { return false }
            guard let cfg = Self.loadConfig(),
                  let token = currentSession?.accessToken else { return false }

            var req = URLRequest(url: cfg.url.appendingPathComponent("/auth/v1/user"))
            req.httpMethod = "GET"
            req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            guard let (data, response) = try? await urlSession.data(for: req),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return false }

            struct UserResponse: Decodable { let is_anonymous: Bool? }
            let user = try? JSONDecoder().decode(UserResponse.self, from: data)
            return user?.is_anonymous ?? false
        }
    }

    // MARK: - REST helpers (used by SyncService US-029)

    /// Generic POST to a PostgREST table. Returns response body bytes
    /// on success. Returns `.success(empty Data)` when FF_BACKEND_SYNC
    /// is off so callers can treat sync as best-effort fire-and-forget.
    public func post(table: String, body: Data) async -> Result<Data, SupabaseError> {
        guard FeatureFlags.backendSync else { return .success(Data()) }
        guard let cfg = Self.loadConfig() else { return .failure(.missingConfig) }
        guard let token = currentSession?.accessToken else { return .failure(.notSignedIn) }

        var req = URLRequest(url: cfg.url.appendingPathComponent("/rest/v1/\(table)"))
        req.httpMethod = "POST"
        req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Prefer: resolution=merge-duplicates so upsert semantics match
        // SyncService's outbox idempotency.
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = body

        return await sendREST(req)
    }

    /// Generic GET from a PostgREST table with optional query string params.
    /// Returns `.success(empty Data)` when FF_BACKEND_SYNC is off.
    public func get(table: String, query: [URLQueryItem] = []) async -> Result<Data, SupabaseError> {
        guard FeatureFlags.backendSync else { return .success(Data()) }
        guard let cfg = Self.loadConfig() else { return .failure(.missingConfig) }
        guard let token = currentSession?.accessToken else { return .failure(.notSignedIn) }

        var components = URLComponents(
            url: cfg.url.appendingPathComponent("/rest/v1/\(table)"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else { return .failure(.missingConfig) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        return await sendREST(req)
    }

    /// Invoke a Supabase Edge Function with the user's bearer token.
    /// Returns `.success(empty Data)` when FF_BACKEND_SYNC is off.
    public func invoke(function: String, body: Data) async -> Result<Data, SupabaseError> {
        guard FeatureFlags.backendSync else { return .success(Data()) }
        guard let cfg = Self.loadConfig() else { return .failure(.missingConfig) }
        guard let token = currentSession?.accessToken else { return .failure(.notSignedIn) }

        var req = URLRequest(url: cfg.url.appendingPathComponent("/functions/v1/\(function)"))
        req.httpMethod = "POST"
        req.setValue(cfg.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        return await sendREST(req)
    }

    // MARK: - Internals

    private func sendREST(_ request: URLRequest) async -> Result<Data, SupabaseError> {
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failure(.requestFailed(status: 0, body: ""))
            }
            guard (200..<300).contains(http.statusCode) else {
                return .failure(.requestFailed(status: http.statusCode,
                                               body: String(data: data, encoding: .utf8) ?? ""))
            }
            return .success(data)
        } catch {
            return .failure(.requestFailed(status: 0, body: error.localizedDescription))
        }
    }

    private func persist(_ s: Session) {
        guard let data = try? JSONEncoder.iso8601Encoder.encode(s),
              let str = String(data: data, encoding: .utf8) else { return }
        _ = KeychainStore.write(account: Self.sessionKey, value: str)
    }
}
