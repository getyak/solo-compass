import SwiftUI
import StoreKit

/// First user-visible paid moment. Shows the two product cards (yearly
/// emphasized as "Best value"), the 7-day free trial CTA, restore link,
/// and fine-print legal copy.
///
/// Driven by `SubscriptionService` from the environment. On a successful
/// purchase, dismisses and calls the `onUnlocked` closure so the caller
/// can resume whatever gated action triggered the paywall.
public struct PaywallView: View {
    @Environment(SubscriptionService.self) private var subscription
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProductID: String = SubscriptionService.yearlyProductID
    @State private var purchaseInFlight = false
    @State private var purchaseError: String?

    /// Called after a successful purchase or restore so callers can
    /// resume the action that triggered the paywall.
    var onUnlocked: () -> Void

    public init(onUnlocked: @escaping () -> Void = {}) {
        self.onUnlocked = onUnlocked
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                hero
                bullets
                productCards
                ctaButton
                continueFreeButton
                fineprint
                actionLinks
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(NSLocalizedString("paywall.close", comment: "Close paywall"))
                }
            }
        }
        .task {
            if subscription.products.isEmpty {
                await subscription.loadProducts()
            }
        }
        .alert(
            NSLocalizedString("paywall.error.title", comment: "Purchase error"),
            isPresented: .constant(purchaseError != nil),
            actions: {
                Button(NSLocalizedString("common.ok", comment: "OK")) {
                    purchaseError = nil
                }
            },
            message: { Text(purchaseError ?? "") }
        )
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255))
            Text(NSLocalizedString("paywall.hero.title", comment: "Unlock Solo Compass Pro"))
                .font(.title.bold())
            Text(NSLocalizedString("paywall.hero.subtitle", comment: "Subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 12) {
            bullet("paywall.feature.explore", icon: "sparkle.magnifyingglass")
            bullet("paywall.feature.voice", icon: "mic.fill")
            bullet("paywall.feature.insight", icon: "brain.head.profile")
            bullet("paywall.feature.quota", icon: "speedometer")
        }
    }

    private func bullet(_ key: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255))
            Text(NSLocalizedString(key, comment: ""))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var productCards: some View {
        VStack(spacing: 12) {
            if subscription.isLoading && subscription.products.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(subscription.products, id: \.id) { product in
                    productCard(product)
                }
            }
        }
    }

    private func productCard(_ product: Product) -> some View {
        let isYearly = product.id == SubscriptionService.yearlyProductID
        let isSelected = selectedProductID == product.id
        return Button {
            selectedProductID = product.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.headline)
                        if isYearly {
                            Text(NSLocalizedString("paywall.bestValue", comment: "Best value badge"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(product.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.title3.bold())
                    Text(periodLabel(product))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255).opacity(0.12) : Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected
                            ? Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)
                            : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(product.displayName))
    }

    private func periodLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        let value = period.value
        switch period.unit {
        case .day:   return value == 1 ? "/day" : "/\(value)d"
        case .week:  return value == 1 ? "/week" : "/\(value)w"
        case .month: return value == 1 ? "/month" : "/\(value)mo"
        case .year:  return value == 1 ? "/year" : "/\(value)y"
        @unknown default: return ""
        }
    }

    private var ctaButton: some View {
        // The CTA must always be tappable (except mid-purchase). Previously
        // Release builds disabled it whenever `products.isEmpty`, which made
        // the button physically un-tappable on device when App Store Connect
        // hadn't returned the catalog yet — the user got a dead button with no
        // feedback. Instead we keep it tappable and, on tap, retry the product
        // load and surface an explicit error if the catalog is still empty
        // (see `runPurchase()`).
        let isDisabled = purchaseInFlight
        // White text on the gold fill (#D4A843) only reaches ~2.2:1 contrast,
        // below WCAG AA (4.5:1). Use a dark brown that's harmonious with the
        // gold and clears AA comfortably (~6.4:1) for low-vision legibility.
        let ctaText = Color(red: 0x3A/255, green: 0x2A/255, blue: 0x05/255)
        return Button {
            Task { await runPurchase() }
        } label: {
            HStack {
                if purchaseInFlight {
                    ProgressView().tint(ctaText)
                } else {
                    Text(NSLocalizedString("paywall.cta.startTrial", comment: "Start 7-day free trial"))
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255))
            .foregroundStyle(ctaText)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isDisabled)
    }

    private var continueFreeButton: some View {
        Button {
            dismiss()
        } label: {
            Text(NSLocalizedString("paywall.continueFree", comment: "Continue with Free"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var fineprint: some View {
        Text(NSLocalizedString("paywall.fineprint", comment: "Subscription fine print"))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
    }

    private var actionLinks: some View {
        HStack(spacing: 24) {
            Button(NSLocalizedString("paywall.restore", comment: "Restore purchases")) {
                Task { await runRestore() }
            }
            .font(.caption)

            Spacer()

            Link(
                NSLocalizedString("paywall.manage", comment: "Manage subscription"),
                destination: URL(string: "https://apps.apple.com/account/subscriptions")!
            )
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func runPurchase() async {
        purchaseInFlight = true
        defer { purchaseInFlight = false }

        // The catalog can be empty on first tap if App Store Connect was slow
        // (or the network blipped) during `.task`'s initial load. Retry once
        // before giving up so the user isn't stuck behind a transient miss.
        if subscription.products.isEmpty {
            await subscription.loadProducts()
        }

        guard let product = subscription.products.first(where: { $0.id == selectedProductID })
            ?? subscription.products.first
        else {
            #if DEBUG
            // DEBUG-only escape hatch: when StoreKit returned no products
            // (e.g. simulator without a .storekit config), flip entitlement
            // locally so the rest of the flow is testable.
            subscription._setEntitlementForTesting(.proTrial)
            onUnlocked()
            dismiss()
            #else
            // Release: no products even after a retry — surface an explicit,
            // actionable error instead of a silent dead button. Common causes
            // are an unsigned Paid Apps Agreement or products not yet "Ready
            // to Submit" in App Store Connect.
            purchaseError = subscription.lastError
                ?? NSLocalizedString("paywall.error.unavailable", comment: "Products unavailable")
            #endif
            return
        }

        let success = await subscription.purchase(product)
        if success {
            onUnlocked()
            dismiss()
        } else if let err = subscription.lastError {
            purchaseError = err
        }
    }

    private func runRestore() async {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        let success = await subscription.restorePurchases()
        if success {
            onUnlocked()
            dismiss()
        }
    }
}

#Preview {
    PaywallView()
        .environment(SubscriptionService())
}
