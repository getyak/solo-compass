import SwiftUI

/// Subscription-state strip rendered at the top of `MeSheet`. Three faces:
///
/// - **proTrial** — progress bar + "X days left · billing starts MMM d".
///   Tapping pushes PaywallView so the user can see/manage the upcoming
///   charge (Apple's settings link lives there).
/// - **pro** — confident green-check + "Pro · renews MMM d". Tapping pushes
///   PaywallView (which routes to App Store subscription management).
/// - **free / proExpired** — amber CTA card: "Try free for 1 month".
///   Tapping pushes PaywallView in upsell mode.
///
/// The banner is intentionally tappable in every state so the user has a
/// single, predictable affordance for "manage my subscription" — no hidden
/// settings-deep-link discovery.
struct EntitlementBanner: View {
    @Environment(SubscriptionService.self) private var subscription

    var body: some View {
        NavigationLink {
            PaywallView()
        } label: {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(backgroundFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(NSLocalizedString("me.entitlement.a11y.hint",
                                             comment: "Opens subscription details"))
    }

    // MARK: - Content variants

    @ViewBuilder
    private var content: some View {
        switch subscription.entitlement {
        case .proTrial:
            trialContent
        case .pro:
            proContent
        case .free, .proExpired:
            upsellContent
        }
    }

    /// Mid-trial: progress + days remaining + billing date.
    private var trialContent: some View {
        let days = subscription.trialDaysRemaining ?? 0
        let progress = trialProgress
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headlineText(days: days))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            // Progress bar — full at trial start, drains to zero on the
            // last day. tint=amber for trial, intentionally not red so we
            // don't make the user feel they're being rushed.
            ProgressView(value: progress)
                .tint(amber)
                .progressViewStyle(.linear)
        }
    }

    /// Steady-state Pro: clean badge + renewal date.
    private var proContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("me.entitlement.pro.title",
                                       comment: "Pro headline"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(proRenewalDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// Free / proExpired: warm CTA card.
    private var upsellContent: some View {
        HStack(spacing: 10) {
            Image(systemName: "gift.fill")
                .font(.headline)
                .foregroundStyle(amber)
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("me.entitlement.upsell.title",
                                       comment: "Try free for 1 month"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(NSLocalizedString("me.entitlement.upsell.detail",
                                       comment: "Pro features hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Derived values

    /// Headline copy resolves on days-remaining boundary so users see
    /// "Last day of trial" specifically on the final day — a quiet but
    /// honest nudge that beats the generic "1 day left" plural.
    private func headlineText(days: Int) -> String {
        if days <= 0 {
            return NSLocalizedString("me.entitlement.trial.lastDay",
                                     comment: "Last day of trial")
        }
        let fmt = NSLocalizedString("me.entitlement.trial.headline.format",
                                    comment: "Trial headline (%d days)")
        return String(format: fmt, days)
    }

    /// Detail row: "Billing starts on MMM d" — only renders the date if
    /// we have one; falls back to a generic copy so the row is never empty.
    private var detailText: String {
        guard let exp = subscription.currentExpirationDate else {
            return NSLocalizedString("me.entitlement.trial.detail.fallback",
                                     comment: "Trial detail without date")
        }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        let fmt = NSLocalizedString("me.entitlement.trial.detail.format",
                                    comment: "Trial detail with date")
        return String(format: fmt, df.string(from: exp))
    }

    private var proRenewalDetail: String {
        guard let exp = subscription.currentExpirationDate else {
            return NSLocalizedString("me.entitlement.pro.detail.fallback",
                                     comment: "Pro detail without date")
        }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        let fmt = NSLocalizedString("me.entitlement.pro.detail.format",
                                    comment: "Pro detail with renewal date")
        return String(format: fmt, df.string(from: exp))
    }

    /// Drain progress over the 30-day trial. Defensively bounded so a
    /// missing expiration date doesn't show an empty bar and a far-future
    /// one doesn't render past the trough.
    private var trialProgress: Double {
        guard let exp = subscription.currentExpirationDate else { return 0 }
        let remaining = exp.timeIntervalSinceNow
        let trialSeconds: TimeInterval = 30 * 86_400
        let consumed = max(0, trialSeconds - remaining)
        return max(0, min(1, consumed / trialSeconds))
    }

    // MARK: - Styling

    private var amber: Color {
        Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255)
    }

    private var backgroundFill: Color {
        switch subscription.entitlement {
        case .proTrial, .free, .proExpired:
            return amber.opacity(0.10)
        case .pro:
            return amber.opacity(0.06)
        }
    }

    private var borderColor: Color {
        switch subscription.entitlement {
        case .proTrial: return amber.opacity(0.35)
        case .pro:      return amber.opacity(0.20)
        case .free, .proExpired: return amber.opacity(0.30)
        }
    }
}

#Preview {
    NavigationStack {
        List {
            Section { EntitlementBanner() }
        }
    }
    .environment(SubscriptionService())
}
