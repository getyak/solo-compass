import Foundation
import StoreKit
import Observation
import os
import SwiftData

/// StoreKit 2 wrapper. The single source of truth for "is this user
/// Pro?" is `Transaction.currentEntitlements`. Everything else
/// (Keychain cache, refreshEntitlement) is plumbing to make that
/// answer fast and correct under bad network conditions.
///
/// Pro features (Explore Here AI synthesis, voice intent, AI
/// explanations) are gated by `entitlement.isActive` (Epic D US-024).
/// Free users still get OSM-only skeleton mode.
@MainActor
@Observable
public final class SubscriptionService {

    // MARK: - Logging

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.solocompass", category: "SubscriptionService")

    // MARK: - Product IDs

    public static let monthlyProductID = "com.solocompass.pro.monthly"
    public static let yearlyProductID = "com.solocompass.pro.yearly"
    public static let allProductIDs: [String] = [monthlyProductID, yearlyProductID]

    // MARK: - Admin / tester email allow-list
    //
    // Emails listed here unlock Pro without going through StoreKit. Use for
    // internal testers and the project owner — never bake in real user
    // emails. Matching is case-insensitive and whitespace-tolerant.
    public static let adminEmails: Set<String> = [
        "3293172751nss@gmail.com",
        "xiong3293172751@outlook.com"
    ]

    /// Case-insensitive, whitespace-tolerant membership check against
    /// `adminEmails`. Pure — no side effects.
    public static func isAdminEmail(_ email: String) -> Bool {
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return adminEmails.contains(where: { $0.lowercased() == normalized })
    }

    // MARK: - Entitlement

    /// The traveler's current access level, from free through Pro trial to full Pro.
    public enum Entitlement: String, CaseIterable, Sendable {
        case free
        case proTrial
        case pro
        case proExpired

        public var isActive: Bool {
            self == .pro || self == .proTrial
        }
    }

    // MARK: - State

    public private(set) var products: [Product] = []
    public private(set) var entitlement: Entitlement
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    // MARK: - Init

    private static let keychainAccount = "entitlement"
    nonisolated(unsafe) private var transactionListenerTask: Task<Void, Never>?

    public init() {
        // Seed entitlement from Keychain so the UI can render Pro state
        // immediately on launch — before the StoreKit refresh comes back.
        if let cached = KeychainStore.read(account: Self.keychainAccount),
           let value = Entitlement(rawValue: cached) {
            self.entitlement = value
        } else {
            self.entitlement = .free
        }

        // Spin up the transaction listener BEFORE the first product/
        // entitlement fetch, so we never miss a renewal that arrives
        // mid-launch.
        startTransactionListener()

        #if DEBUG
        // Debug builds default to Pro so the simulator can exercise the
        // AI-gated surfaces (Explore, AI Insight, voice) without a StoreKit
        // sandbox. Set FF_DEBUG_FORCE_PRO=0 to test the free/paywall path.
        // Stripped entirely from Release builds by the #if DEBUG guard.
        // Sets the in-memory field directly (not setEntitlement) so we don't
        // persist a fake Pro state to Keychain.
        let env = ProcessInfo.processInfo.environment["FF_DEBUG_FORCE_PRO"]
        if env != "0" && env?.lowercased() != "false" {
            self.entitlement = .pro
        }
        #endif
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: - Public API

    /// Fetch product catalog from StoreKit. Idempotent — calling twice
    /// is fine. Sets `isLoading` so the paywall can show a spinner.
    public func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await Product.products(for: Self.allProductIDs)
            // Sort: yearly first (we want it as the "Best value" card on top).
            self.products = fetched.sorted { lhs, _ in
                lhs.id == Self.yearlyProductID
            }
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
            logger.error("product load failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Walk Transaction.currentEntitlements and pick the strongest
    /// entitlement. Updates `entitlement` and writes through to Keychain.
    public func refreshEntitlement() async {
        #if DEBUG
        // Honour the debug Pro override (set in init from FF_DEBUG_FORCE_PRO).
        // Without this, the StoreKit walk below resolves .free on a simulator
        // with no sandbox subscription and overwrites the forced .pro — which
        // silently routes Explore through the free/skeleton path.
        let env = ProcessInfo.processInfo.environment["FF_DEBUG_FORCE_PRO"]
        if env != "0" && env?.lowercased() != "false" {
            if entitlement != .pro { setEntitlement(.pro) }
            return
        }
        #endif
        var resolved: Entitlement = .free
        var latestTransaction: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else { continue }
            guard Self.allProductIDs.contains(txn.productID) else { continue }
            latestTransaction = txn
            // If revoked or refunded, skip — never count as Pro.
            if txn.revocationDate != nil { continue }
            // Expired transactions count as proExpired only if we don't
            // see an active one in the same loop.
            if let expires = txn.expirationDate, expires < Date() {
                if resolved == .free { resolved = .proExpired }
                continue
            }
            // Active. Trial vs paid distinction. The .offer accessor
            // landed in iOS 17.2; on 17.0/17.1 we fall back to the
            // legacy isUpgraded heuristic (offerType == .introductory
            // implies first paid period within trial window).
            if #available(iOS 17.2, *) {
                if let offerType = txn.offer?.type, offerType == .introductory {
                    resolved = .proTrial
                } else {
                    resolved = .pro
                    break
                }
            } else {
                // Best-effort: offerType lives at txn.offerType on 17.0/17.1.
                if txn.offerType == .introductory {
                    resolved = .proTrial
                } else {
                    resolved = .pro
                    break
                }
            }
        }
        let prior = entitlement
        setEntitlement(resolved)
        // Epic E US-032: emit a subscription_events row when the
        // resolved entitlement changes. Routed through the SyncService
        // outbox so it survives offline boots; FF-off path is a no-op.
        if prior != resolved, let txn = latestTransaction {
            emitSubscriptionEvent(prior: prior, current: resolved, transaction: txn)
        }
    }

    /// Initiate a purchase. Returns true on successful verification +
    /// activation. Caller (paywall) should then dismiss + retry the
    /// gated action via its closure.
    @discardableResult
    public func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let txn) = verification {
                    await txn.finish()
                    await refreshEntitlement()
                    return entitlement.isActive
                }
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Trigger StoreKit's resync for "Restore purchases". The
    /// transaction listener will pick up any granted entitlement;
    /// we also call refresh directly to ensure the view sees the
    /// new state synchronously after this returns.
    public func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            return entitlement.isActive
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Tester / admin escape hatch: if `email` is on the allow-list, flip
    /// entitlement to `.pro` and persist via Keychain so the unlock
    /// survives relaunch. Returns true when the unlock applied.
    ///
    /// This bypasses StoreKit on purpose — internal testers shouldn't need
    /// a sandbox Apple ID, and the project owner needs a Gmail-based entry
    /// point that Sign in with Apple can't provide.
    @discardableResult
    public func unlockWithAdminEmail(_ email: String) -> Bool {
        guard Self.isAdminEmail(email) else { return false }
        setEntitlement(.pro)
        return true
    }

    // MARK: - Dependency injection (tests override these)

    /// Overridable in tests to capture enqueued records without touching
    /// the production singleton or a real SwiftData store.
    var syncService: SyncService = .shared
    var syncModelContext: ModelContext = ModelContext(SoloCompassModelContainer.shared)
    var deviceIDProvider: () -> String = { DeviceIdentityService.shared.deviceID }

    // MARK: - Internal

    private func startTransactionListener() {
        transactionListenerTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                guard case .verified = update else { continue }
                await self?.refreshEntitlement()
            }
        }
    }

    private func setEntitlement(_ new: Entitlement) {
        guard new != entitlement else { return }
        entitlement = new
        KeychainStore.write(account: Self.keychainAccount, value: new.rawValue)
    }

    /// Test-only: set entitlement directly (bypasses StoreKit) and write
    /// through to Keychain. Use sparingly — production paths must go
    /// through `refreshEntitlement()`.
    public func _setEntitlementForTesting(_ value: Entitlement) {
        setEntitlement(value)
    }

    // MARK: - Subscription event emission (Epic E US-032)

    private func emitSubscriptionEvent(
        prior: Entitlement,
        current: Entitlement,
        transaction: Transaction
    ) {
        let eventType: String
        switch (prior, current) {
        case (.free, .proTrial), (.free, .pro), (.proExpired, .proTrial), (.proExpired, .pro):
            eventType = "subscribed"
        case (.pro, .proExpired), (.proTrial, .proExpired):
            eventType = "expired"
        case (_, _) where transaction.revocationDate != nil:
            eventType = "revoked"
        default:
            eventType = "upgraded"
        }
        _emitSubscriptionEventFields(
            eventType: eventType,
            productID: transaction.productID,
            originalPurchaseDate: transaction.originalPurchaseDate,
            expiresDate: transaction.expirationDate,
            isInTrialPeriod: current == .proTrial
        )
    }

    /// Package-internal entry point for testing: enqueues a subscription_events
    /// row without requiring a real StoreKit Transaction. When FF_BACKEND_SYNC
    /// is false, the call is a silent no-op.
    func _emitSubscriptionEventFields(
        eventType: String,
        productID: String,
        originalPurchaseDate: Date?,
        expiresDate: Date?,
        isInTrialPeriod: Bool
    ) {
        // When the backend sync feature flag is off, drop the event silently.
        guard FeatureFlags.backendSync else { return }

        let payload = SubscriptionEventPayload(
            user_id: SupabaseClient.shared.currentSession?.userId,
            event_type: eventType,
            product_id: productID,
            original_purchase_date: originalPurchaseDate,
            expires_date: expiresDate,
            is_in_trial_period: isInTrialPeriod,
            device_id: deviceIDProvider()
        )
        // No PII (no email, no Apple ID). user_id is anonymous Supabase
        // UUID; device_id is the random per-device anon UUID.
        syncService.enqueue(
            tableName: "subscription_events",
            operation: "upsert",
            payload: payload,
            context: syncModelContext
        )
        logger.info("emitted subscription_events row: event_type=\(eventType, privacy: .public) product_id=\(productID, privacy: .public) is_in_trial=\(isInTrialPeriod, privacy: .public) device_id=\(self.deviceIDProvider(), privacy: .private)")
    }
}

/// Wire payload for subscription_events. snake_case so PostgREST maps
/// directly to the column names.
struct SubscriptionEventPayload: Encodable {
    let user_id: String?
    let event_type: String
    let product_id: String
    let original_purchase_date: Date?
    let expires_date: Date?
    let is_in_trial_period: Bool
    let device_id: String
}
