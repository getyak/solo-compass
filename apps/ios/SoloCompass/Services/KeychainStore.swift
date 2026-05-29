import Foundation
import Security

/// Tiny wrapper around Security framework for single string values.
/// Used by SubscriptionService (US-022) to cache the entitlement so a
/// brief offline launch still respects Pro state.
///
/// Not generic on purpose — each call site that needs Keychain should
/// pass an explicit account name. Service is "com.solocompass" globally.
public enum KeychainStore {
    private static let service = "com.solocompass"

    /// Read a string for the given account. Returns nil on miss or
    /// any Keychain error (we treat errors as "not present"; callers
    /// fall back to whatever default makes sense for them).
    public static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = withUnsafeMutablePointer(to: &result) {
            SecItemCopyMatching(query as CFDictionary, $0)
        }
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Write a string for the given account. Replaces any existing
    /// value. Returns true on success. Failures are silent because
    /// Keychain is best-effort (not a source of truth — the source of
    /// truth is StoreKit's Transaction.currentEntitlements).
    @discardableResult
    public static func write(account: String, value: String) -> Bool {
        // Delete then insert so we don't have to handle SecItemUpdate
        // separately. The double-call is cheap.
        delete(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Removes a stored secret for the given account from the Keychain.
    @discardableResult
    public static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
