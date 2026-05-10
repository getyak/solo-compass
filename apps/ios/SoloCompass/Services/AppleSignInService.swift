import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import SwiftData

/// Handles Sign in with Apple → Supabase account-link flow (US-036).
///
/// The service is purposefully thin: it owns the nonce lifecycle, delegates
/// the ASAuthorization presentation to the caller via `presentationAnchor`,
/// and then calls `SupabaseClient.linkAppleIdentity`. On success it
/// re-stamps all `PendingSyncRecord` rows so the outbox is attributed to
/// the new permanent userId rather than the old anonymous one.
///
/// Usage:
///   1. Call `link(presentationAnchor:context:)`.
///   2. Await the `LinkResult` — `.linked(newUserId:)` on success.
///   3. The service updates `DeviceIdentityService` keychain so the rest of
///      the app picks up the permanent identity on next read.
@Observable
@MainActor
public final class AppleSignInService: NSObject {

    public enum LinkResult {
        case linked(newUserId: String)
        case cancelled
        case failed(Error)
    }

    // Injected for testability.
    var supabaseClient: any SupabaseClientProtocol = SupabaseClient.shared

    // Raw nonce used when generating the SHA-256 hash sent to Apple.
    // Retained across the ASAuthorization callback.
    private var currentNonce: String?

    // Continuation bridging the delegate callback back to async.
    private var continuation: CheckedContinuation<LinkResult, Never>?

    override public init() {}

    // MARK: - Public API

    /// Present the Sign in with Apple sheet and link the result to Supabase.
    ///
    /// - Parameters:
    ///   - presentationAnchor: The `ASPresentationAnchor` (window) used by
    ///     ASAuthorizationController. Callers obtain this via the SwiftUI
    ///     `signInWithAppleButtonStyle` environment or directly from the scene.
    ///   - context: SwiftData context used to re-stamp `PendingSyncRecord` rows.
    public func link(
        presentationAnchor: ASPresentationAnchor,
        context: ModelContext
    ) async -> LinkResult {
        let nonce = Self.randomNonce()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = []  // no email/name — privacy by default
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = PresentationContextProvider(anchor: presentationAnchor)

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }.then { result in
            // Re-stamp pending rows on success before returning.
            if case .linked(let newId) = result {
                Self.restampPendingRecords(newUserId: newId, context: context)
            }
            return result
        }
    }

    // MARK: - Internals

    private func handleCredential(_ credential: ASAuthorizationAppleIDCredential) async {
        guard let nonce = currentNonce,
              let tokenData = credential.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8) else {
            continuation?.resume(returning: .failed(LinkError.missingCredentialData))
            continuation = nil
            return
        }

        let result = await supabaseClient.linkAppleIdentity(
            identityToken: identityToken,
            nonce: nonce
        )

        switch result {
        case .success(let session):
            // Update the stored anonymous userId so the rest of the app reads
            // the new permanent identity on next access.
            _ = KeychainStore.write(
                account: DeviceIdentityService.userIdKeychainAccount,
                value: session.userId
            )
            continuation?.resume(returning: .linked(newUserId: session.userId))
        case .failure(let error):
            continuation?.resume(returning: .failed(error))
        }
        continuation = nil
    }

    /// Re-stamp every PendingSyncRecord whose payload JSON contains the old
    /// (anonymous) userId so future flushes are attributed to the permanent account.
    ///
    /// This is best-effort: if a row's payload does not contain a `user_id` field
    /// the rewrite is a no-op for that row, which is fine — Supabase RLS uses
    /// the JWT subject (the access token's `sub` claim) as the authoritative
    /// identity, not the `user_id` field in the payload.
    private static func restampPendingRecords(newUserId: String, context: ModelContext) {
        let descriptor = FetchDescriptor<PendingSyncRecord>()
        guard let rows = try? context.fetch(descriptor), !rows.isEmpty else { return }
        var changed = false
        for row in rows {
            guard var dict = (try? JSONSerialization.jsonObject(with: row.payloadJSON)) as? [String: Any],
                  dict["user_id"] != nil else { continue }
            dict["user_id"] = newUserId
            if let updated = try? JSONSerialization.data(withJSONObject: dict) {
                row.payloadJSON = updated
                changed = true
            }
        }
        if changed { try? context.save() }
    }

    // MARK: - Nonce helpers (PKCE for Apple OIDC)

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .prefix(length)
            .description
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Errors

    enum LinkError: LocalizedError {
        case missingCredentialData

        var errorDescription: String? {
            switch self {
            case .missingCredentialData: return "Apple credential data was missing or invalid."
            }
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleSignInService: ASAuthorizationControllerDelegate {

    public nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Task { @MainActor [weak self] in
                self?.continuation?.resume(returning: .failed(LinkError.missingCredentialData))
                self?.continuation = nil
            }
            return
        }
        Task { @MainActor [weak self] in
            await self?.handleCredential(credential)
        }
    }

    public nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor [weak self] in
            let asError = error as? ASAuthorizationError
            if asError?.code == .canceled {
                self?.continuation?.resume(returning: .cancelled)
            } else {
                self?.continuation?.resume(returning: .failed(error))
            }
            self?.continuation = nil
        }
    }
}

// MARK: - Presentation context provider

private final class PresentationContextProvider: NSObject, ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { anchor }
}

// MARK: - then helper (local to this file)

private extension AppleSignInService.LinkResult {
    func then(_ transform: (AppleSignInService.LinkResult) -> AppleSignInService.LinkResult) -> AppleSignInService.LinkResult {
        transform(self)
    }
}
