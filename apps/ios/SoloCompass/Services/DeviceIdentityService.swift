import Foundation
import Security

/// Generates and persists an anonymous device UUID in the iOS Keychain (US-038).
/// The UUID is created once, never changes, and survives app reinstalls on the
/// same device (Keychain is not wiped on uninstall by default).
///
/// Attach the ID as `X-Device-ID` on every outbound API request via
/// `URLRequest.attachDeviceID()`.
@MainActor
public final class DeviceIdentityService {
    public static let shared = DeviceIdentityService()

    private let keychainService = "com.solocompass.device"
    private let keychainAccount = "device-id"

    /// Keychain account under which the Supabase anonymous userId is stored (US-030).
    static let userIdKeychainAccount = "sc.anon.userId"

    private let client: any SupabaseClientProtocol

    /// Designated initialiser for production (uses the real singleton).
    private convenience init() {
        self.init(client: SupabaseClient.shared)
    }

    /// Dependency-injected initialiser for unit tests.
    init(client: any SupabaseClientProtocol) {
        self.client = client
    }

    /// Returns the stable anonymous device UUID, creating it on first call.
    public var deviceID: String {
        if let existing = readFromKeychain() { return existing }
        let new = UUID().uuidString
        writeToKeychain(new)
        return new
    }

    /// The Supabase anonymous userId persisted in Keychain after first sign-in.
    public var anonymousUserId: String? {
        KeychainStore.read(account: Self.userIdKeychainAccount)
    }

    /// Bootstrap the device identity + Supabase anonymous session (US-030).
    /// Called from `SoloCompassApp.onAppear`. When `FF_BACKEND_SYNC` is off
    /// this is a fast no-op (SupabaseClient short-circuits to
    /// `.failure(.backendDisabled)`).
    ///
    /// First launch: calls `signInAnonymously()` and persists `userId` under
    /// `sc.anon.userId` in the Keychain. Subsequent launches: the SDK's
    /// built-in refresh-token flow restores the session; `signInAnonymously`
    /// returns the cached (or refreshed) session without making a new signup
    /// request, so `signInAnonymously` is NOT called a second time in the
    /// sense of creating a new account.
    public func bootstrap() async {
        // Touch deviceID so the keychain row is created on first launch.
        _ = self.deviceID

        // Best-effort: anonymous Supabase sign-in (or session restore).
        // We never block the UI on this — the local-first app must work
        // without a session.
        let result = await client.signInAnonymously()

        // On success, persist the userId separately so other callers can
        // read the stable anon identity without decoding the full session.
        if case .success(let session) = result {
            _ = KeychainStore.write(account: Self.userIdKeychainAccount, value: session.userId)
        }
    }

    // MARK: - Keychain

    private func readFromKeychain() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeToKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: keychainService,
                kSecAttrAccount: keychainAccount,
            ]
            SecItemUpdate(updateQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        }
    }
}

// MARK: - URLRequest convenience

extension URLRequest {
    /// Attaches the anonymous device ID as `X-Device-ID`. Call on every outbound API request.
    @MainActor
    mutating func attachDeviceID() {
        setValue(DeviceIdentityService.shared.deviceID, forHTTPHeaderField: "X-Device-ID")
    }
}
