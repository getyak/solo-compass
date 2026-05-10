import Foundation
import StoreKit
import Observation

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

    // MARK: - Product IDs

    public static let monthlyProductID = "com.solocompass.pro.monthly"
    public static let yearlyProductID = "com.solocompass.pro.yearly"
    public static let allProductIDs: [String] = [monthlyProductID, yearlyProductID]

    // MARK: - Entitlement

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
            #if DEBUG
            print("[SubscriptionService] product load failed: \(error)")
            #endif
        }
    }

    /// Walk Transaction.currentEntitlements and pick the strongest
    /// entitlement. Updates `entitlement` and writes through to Keychain.
    public func refreshEntitlement() async {
        var resolved: Entitlement = .free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else { continue }
            guard Self.allProductIDs.contains(txn.productID) else { continue }
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
        setEntitlement(resolved)
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
}
