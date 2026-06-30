import SwiftUI
import StoreKit

/// First user-visible paid moment. Shows the two product cards (yearly
/// emphasized as "Best value"), the 1-month free trial CTA, restore link,
/// and fine-print legal copy.
///
/// Driven by `SubscriptionService` from the environment. On a successful
/// purchase, dismisses and calls the `onUnlocked` closure so the caller
/// can resume whatever gated action triggered the paywall.
public struct PaywallView: View {
    @Environment(SubscriptionService.self) private var subscription
    @Environment(\.dismiss) private var dismiss

    // Default selection = monthly because the Introductory Offer (1-month
    // free trial) is configured on the monthly SKU. Pre-selecting yearly
    // would suppress the trial pitch — bad funnel design even though yearly
    // has higher LTV.
    @State private var selectedProductID: String = SubscriptionService.monthlyProductID
    @State private var purchaseInFlight = false
    @State private var purchaseError: String?
    /// Whether the App Store Apple ID currently looking at this paywall is
    /// still eligible for the monthly Introductory Offer (1 month free).
    /// Defaults to `true` so the trial banner is visible while we're still
    /// resolving — false positives are recoverable (StoreKit will fall back
    /// to the regular price at purchase time and the user will see it in
    /// Apple's own purchase sheet); false negatives would silently hide our
    /// most important hook.
    @State private var introOfferEligible: Bool = true

    /// Called after a successful purchase or restore so callers can
    /// resume the action that triggered the paywall.
    var onUnlocked: () -> Void

    public init(onUnlocked: @escaping () -> Void = {}) {
        self.onUnlocked = onUnlocked
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                // Mid-trial state takes precedence: a paying-trial user
                // re-opening the paywall (from MeSheet) should see "X days
                // left" + manage, not the upsell pitch again.
                if subscription.entitlement == .proTrial {
                    midTrialBanner
                } else if introOfferEligible {
                    trialBanner
                }
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
            // Refresh intro-offer eligibility after products are in hand.
            // Done in a separate Task so a slow StoreKit call doesn't block
            // the bullets/CTA from rendering — if it's late, the optimistic
            // default keeps the banner visible until the truth lands.
            if let monthly = subscription.products.first(where: { $0.id == SubscriptionService.monthlyProductID }) {
                introOfferEligible = await subscription.isEligibleForIntroOffer(monthly)
            }
            // Make sure the mid-trial banner reads from a fresh
            // currentExpirationDate. refreshEntitlement is idempotent.
            await subscription.refreshEntitlement()
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

    /// "Get 1 month free" pitch banner shown to eligible Apple IDs.
    /// Pulls live monthly displayPrice so the price disclosure satisfies
    /// App Store 3.1.2 without us hard-coding currency-localized strings.
    private var trialBanner: some View {
        let amber = Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)
        let monthly = subscription.products.first(where: { $0.id == SubscriptionService.monthlyProductID })
        let priceCopy: String = {
            if let monthly {
                let fmt = NSLocalizedString("paywall.trialBanner.format",
                                            comment: "Trial banner with %@ monthly price")
                return String(format: fmt, monthly.displayPrice)
            }
            return NSLocalizedString("paywall.trialBanner.fallback",
                                     comment: "Trial banner without price")
        }()
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.title3)
                .foregroundStyle(amber)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("paywall.trialBanner.headline",
                                       comment: "Trial banner headline"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(priceCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(amber.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(amber.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// Status banner for users already inside the trial period — replaces
    /// the "Get 1 month free" pitch with renewal context and a manage link.
    private var midTrialBanner: some View {
        let amber = Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)
        let days = subscription.trialDaysRemaining ?? 0
        let headline: String = {
            let fmt = NSLocalizedString("paywall.midTrial.headline.format",
                                        comment: "Trial-active headline (%d days)")
            return String(format: fmt, days)
        }()
        let detail: String = {
            guard let exp = subscription.currentExpirationDate else {
                return NSLocalizedString("paywall.midTrial.detail.fallback",
                                         comment: "Trial-active detail without date")
            }
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            let fmt = NSLocalizedString("paywall.midTrial.detail.format",
                                        comment: "Trial-active detail with renewal date")
            return String(format: fmt, df.string(from: exp))
        }()
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(amber)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(amber.opacity(0.12))
        )
        .accessibilityElement(children: .combine)
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
        let isMonthly = product.id == SubscriptionService.monthlyProductID
        let isSelected = selectedProductID == product.id
        let showTrialBadge = isMonthly && introOfferEligible && subscription.entitlement != .proTrial
        // Dark brown for badge text — same WCAG-AA-clear pairing the CTA uses
        // on the amber fill.
        let badgeText = Color(red: 0x3A/255, green: 0x2A/255, blue: 0x05/255)
        return Button {
            selectedProductID = product.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.headline)
                        if showTrialBadge {
                            Text(NSLocalizedString("paywall.trialBadge",
                                                   comment: "1-month free trial badge"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)))
                                .foregroundStyle(badgeText)
                        } else if isYearly {
                            Text(NSLocalizedString("paywall.bestValue", comment: "Best value badge"))
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)))
                                .foregroundStyle(badgeText)
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

    /// Dynamic CTA copy: emphasize the free month when eligible, fall back
    /// to "Subscribe" for ineligible Apple IDs (returning users who already
    /// burned the introductory offer) so we don't promise what StoreKit
    /// won't deliver.
    private var ctaTitle: String {
        let isMonthly = selectedProductID == SubscriptionService.monthlyProductID
        if isMonthly && introOfferEligible && subscription.entitlement != .proTrial {
            return NSLocalizedString("paywall.cta.startMonthFree",
                                     comment: "Start 1-month free trial CTA")
        }
        return NSLocalizedString("paywall.cta.subscribe",
                                 comment: "Plain subscribe CTA")
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
                    Text(ctaTitle)
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
        // Re-resolve copy by trial vs no-trial so the legal disclosure
        // matches what the CTA actually offers — Apple's Reviewer #1 thing.
        let key: String
        if selectedProductID == SubscriptionService.monthlyProductID
            && introOfferEligible
            && subscription.entitlement != .proTrial {
            key = "paywall.fineprint.month"
        } else {
            key = "paywall.fineprint"
        }
        return Text(NSLocalizedString(key, comment: "Subscription fine print"))
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
