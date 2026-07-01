import SwiftUI
import StoreKit

/// Documented VoiceOver focus order for every onboarding page.
///
/// VoiceOver visits accessibility elements in **descending** sort-priority order
/// (higher reads first). The intended reading order on each page is therefore:
/// `title → subtitle → (page content) → primary CTA → skip`.
///
/// Exposed (not private) so `OnboardingA11yOrderTest` asserts against the same
/// source of truth the views apply via `.accessibilitySortPriority(_:)`.
enum OnboardingA11ySortPriority {
    static let title: Double = 100
    static let subtitle: Double = 90
    /// Mid-page interactive content (e.g. travel-style options) read after the
    /// subtitle but before the primary call to action.
    static let content: Double = 80
    static let primaryCTA: Double = 50
    static let skip: Double = 10

    /// The documented order, highest priority (read first) to lowest (read last).
    static let documentedOrder: [Double] = [title, subtitle, content, primaryCTA, skip]
}

/// Four-step first-run flow shown once via `.fullScreenCover` from CompassMapView.
/// Steps: Welcome → Experiences concept → Solo Score & Now → Travel style.
/// Gated by `UserPreferences.hasCompletedOnboarding`.
public struct OnboardingView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Optional — when present, the final paywall step uses real StoreKit
    /// purchases. When absent (e.g. previews/tests that don't inject the
    /// service), the paywall step renders but the CTA falls back to skip.
    @Environment(SubscriptionService.self) private var subscription
    let onComplete: () -> Void

    @State private var step: Int = 0
    @State private var paywallPurchaseInFlight: Bool = false

    /// UserDefaults flag set the first time the user finishes (or skips) the
    /// onboarding paywall step. We never re-show the onboarding paywall after
    /// this is true — returning users hit the SettingsView paywall entry
    /// point instead, which is intentional (the Apple HIG requirement is one
    /// non-modal post-onboarding paywall, not repeated wall-of-trial popups).
    private static let onboardingPaywallSeenKey = "hasSeenOnboardingPaywall"

    // P1.2: added two new steps after styleStep — vibe (#120) at index 4
    // and city (#121) at index 5 — so the paywall step now sits at index 6.
    private static let totalSteps = 7

    private var slideTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    public var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            switch step {
            case 0:
                welcomeStep
                    .transition(slideTransition)
                    .id(0)
            case 1:
                conceptsStep
                    .transition(slideTransition)
                    .id(1)
            case 2:
                scoringStep
                    .transition(slideTransition)
                    .id(2)
            case 3:
                styleStep
                    .transition(slideTransition)
                    .id(3)
            case 4:
                vibeStep
                    .transition(slideTransition)
                    .id(4)
            case 5:
                cityStep
                    .transition(slideTransition)
                    .id(5)
            default:
                paywallStep
                    .transition(slideTransition)
                    .id(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            skipButton
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Skip the whole flow

    /// Completes onboarding immediately from any step (returning users / QA).
    /// If the user is already on the paywall step, also mark it as seen so a
    /// future onboarding re-entry doesn't re-pitch the trial.
    private var skipButton: some View {
        Button {
            if step == 6 {
                UserDefaults.standard.set(true, forKey: Self.onboardingPaywallSeenKey)
            }
            preferences.completeOnboarding()
            onComplete()
        } label: {
            Text(NSLocalizedString("onboarding.skip", comment: "Skip the entire onboarding flow"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .padding(.top, 8)
        .padding(.trailing, 8)
        .accessibilityIdentifier("onboarding.skip")
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == step ? 20 : 6, height: 6)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: - Step 0: Welcome + location permission

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)

            // Golden-ratio weighting: a lighter top spacer lifts the hero toward
            // ~38% height so the first screen doesn't feel bottom-heavy.
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                Image(systemName: "map.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.welcome.title", comment: "Onboarding title"))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .accessibilitySortPriority(OnboardingA11ySortPriority.title)

                    Text(NSLocalizedString("onboarding.welcome.subtitle", comment: "Onboarding subtitle"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .accessibilitySortPriority(OnboardingA11ySortPriority.subtitle)
                }
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    locationService.requestPermission()
                    step = 1
                } label: {
                    Text(NSLocalizedString("onboarding.welcome.cta", comment: "Find me on the map"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .accessibilitySortPriority(OnboardingA11ySortPriority.primaryCTA)

                Button {
                    step = 1
                } label: {
                    Text(NSLocalizedString("onboarding.welcome.skip", comment: "Browse first"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilitySortPriority(OnboardingA11ySortPriority.skip)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Step 1: Core concepts (Experience)

    private var conceptsStep: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)

            Spacer(minLength: 0)

            VStack(spacing: 24) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.concepts.title", comment: "What is an Experience?"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .accessibilitySortPriority(OnboardingA11ySortPriority.title)

                    Text(NSLocalizedString("onboarding.concepts.subtitle", comment: "Not just places"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .accessibilitySortPriority(OnboardingA11ySortPriority.subtitle)
                }
            }

            Spacer(minLength: 16)

            VStack(spacing: 16) {
                conceptRow(
                    icon: "mappin.and.ellipse",
                    title: NSLocalizedString("onboarding.concepts.item1.title", comment: ""),
                    description: NSLocalizedString("onboarding.concepts.item1.desc", comment: "")
                )
                conceptRow(
                    icon: "clock.badge.checkmark",
                    title: NSLocalizedString("onboarding.concepts.item2.title", comment: ""),
                    description: NSLocalizedString("onboarding.concepts.item2.desc", comment: "")
                )
            }
            .padding(.horizontal, 24)
            .accessibilitySortPriority(OnboardingA11ySortPriority.content)

            Spacer(minLength: 0)

            Button {
                step = 2
            } label: {
                Text(NSLocalizedString("onboarding.concepts.cta", comment: "Got it"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .accessibilitySortPriority(OnboardingA11ySortPriority.primaryCTA)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Step 2: Solo Score & Now

    private var scoringStep: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)

            Spacer(minLength: 0)

            VStack(spacing: 24) {
                Image(systemName: "gauge.open.with.lines.needle.33percent.and.arrowtriangle")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.scoring.title", comment: "Smart ranking"))
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .accessibilitySortPriority(OnboardingA11ySortPriority.title)

                    Text(NSLocalizedString("onboarding.scoring.subtitle", comment: "How we rank"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .accessibilitySortPriority(OnboardingA11ySortPriority.subtitle)
                }
            }

            Spacer(minLength: 16)

            VStack(spacing: 16) {
                conceptRow(
                    icon: "star.fill",
                    title: NSLocalizedString("onboarding.scoring.item1.title", comment: ""),
                    description: NSLocalizedString("onboarding.scoring.item1.desc", comment: "")
                )
                conceptRow(
                    icon: "sun.horizon.fill",
                    title: NSLocalizedString("onboarding.scoring.item2.title", comment: ""),
                    description: NSLocalizedString("onboarding.scoring.item2.desc", comment: "")
                )
            }
            .padding(.horizontal, 24)
            .accessibilitySortPriority(OnboardingA11ySortPriority.content)

            Spacer(minLength: 0)

            Button {
                step = 3
            } label: {
                Text(NSLocalizedString("onboarding.scoring.cta", comment: "Makes sense"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .accessibilitySortPriority(OnboardingA11ySortPriority.primaryCTA)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Concept row helper

    private func conceptRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Step 3: Travel style

    private var styleStep: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)

            // Match the welcome step's golden-ratio weighting so paging between
            // steps doesn't shift the visual anchor.
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                Text(NSLocalizedString("onboarding.style.title", comment: "Travel style title"))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilitySortPriority(OnboardingA11ySortPriority.title)

                Text(NSLocalizedString("onboarding.style.subtitle", comment: "Travel style subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilitySortPriority(OnboardingA11ySortPriority.subtitle)

                VStack(spacing: 10) {
                    ForEach(UserPreferences.SoloTravelStyle.allCases) { style in
                        styleRow(style)
                    }
                }
                .padding(.horizontal, 24)
                .accessibilitySortPriority(OnboardingA11ySortPriority.content)
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    // P1.2: vibe (step 4) + city (step 5) come BEFORE any paywall
                    // gating now, so styleStep always advances to vibe. The
                    // "skip the paywall pitch" gate is consulted later, in the
                    // city step's onContinue handler.
                    withAnimation { step = 4 }
                } label: {
                    Text(NSLocalizedString("onboarding.style.cta", comment: "Start exploring"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                .accessibilitySortPriority(OnboardingA11ySortPriority.primaryCTA)

                Button {
                    withAnimation { step = 4 }
                } label: {
                    Text(NSLocalizedString("onboarding.style.skip", comment: "Decide later"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilitySortPriority(OnboardingA11ySortPriority.skip)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Step 4: Paywall (1-month free trial via StoreKit)

    /// True if we should bypass the onboarding paywall and finish immediately.
    /// Covers three cases that all share the same UX rule: the user has
    /// already seen the trial pitch, so nagging them again on warm re-entry
    /// would be hostile.
    ///
    /// 1. Already Pro / mid-trial: they're paying customers, the paywall is
    ///    a regression.
    /// 2. Previously dismissed: opening onboarding again for any reason
    ///    (mid-flow kill recovery, QA replay) shouldn't re-trigger the upsell.
    /// 3. Test/preview env without a SubscriptionService injected: degrade
    ///    cleanly to completion rather than crashing on missing env.
    private var shouldSkipOnboardingPaywall: Bool {
        if subscription.entitlement.isActive { return true }
        if UserDefaults.standard.bool(forKey: Self.onboardingPaywallSeenKey) { return true }
        return false
    }

    /// Marks the onboarding paywall as seen and finishes the flow. Called both
    /// after a successful purchase and after the user taps "Maybe later" —
    /// the seen flag is independent of whether they actually subscribed.
    private func finishOnboardingPaywall() {
        UserDefaults.standard.set(true, forKey: Self.onboardingPaywallSeenKey)
        preferences.completeOnboarding()
        onComplete()
    }

    // MARK: - Step 4: Vibe (P1.2 #120)

    /// Embed the standalone OnboardingVibeStep view inside the same step
    /// chrome the rest of the flow uses. The step indicator runs at the
    /// top; the embedded view owns the photo-picker + CTA + skip.
    private var vibeStep: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)
            OnboardingVibeStep {
                withAnimation { step = 5 }
            }
        }
    }

    // MARK: - Step 5: City + afternoon (P1.2 #121)

    /// After city is picked, the user either lands on the paywall or — if the
    /// onboarding paywall has already been seen this device — finishes the
    /// whole flow directly. We never re-pitch the onboarding paywall.
    private var cityStep: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)
            OnboardingCityStep {
                if shouldSkipOnboardingPaywall {
                    preferences.completeOnboarding()
                    onComplete()
                } else {
                    withAnimation { step = 6 }
                }
            }
        }
    }

    private var paywallStep: some View {
        VStack(spacing: 0) {
            stepIndicator
                .padding(.top, 24)

            Spacer(minLength: 0)

            VStack(spacing: 20) {
                // Hero glyph — sparkles in warm amber, matches PaywallView so
                // the user sees one visual identity for "Pro" across surfaces.
                Image(systemName: "sparkles")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255))
                    .accessibilityHidden(true)

                Text(NSLocalizedString("onboarding.paywall.title", comment: "Trial step title"))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilitySortPriority(OnboardingA11ySortPriority.title)

                Text(NSLocalizedString("onboarding.paywall.subtitle", comment: "Trial step subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .accessibilitySortPriority(OnboardingA11ySortPriority.subtitle)

                // Trial-benefit bullets. Kept to three so the page feels
                // confident, not a feature dump.
                VStack(alignment: .leading, spacing: 12) {
                    onboardingPaywallBullet("sparkle.magnifyingglass",
                                            key: "onboarding.paywall.bullet.explore")
                    onboardingPaywallBullet("mic.fill",
                                            key: "onboarding.paywall.bullet.voice")
                    onboardingPaywallBullet("brain.head.profile",
                                            key: "onboarding.paywall.bullet.insight")
                }
                .padding(.horizontal, 28)
                .accessibilitySortPriority(OnboardingA11ySortPriority.content)
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    Task { await runOnboardingPurchase() }
                } label: {
                    HStack(spacing: 8) {
                        if paywallPurchaseInFlight {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color(red: 0x3A/255, green: 0x2A/255, blue: 0x05/255))
                        }
                        Text(NSLocalizedString("onboarding.paywall.cta", comment: "Start free month CTA"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .foregroundStyle(Color(red: 0x3A/255, green: 0x2A/255, blue: 0x05/255))
                }
                .disabled(paywallPurchaseInFlight)
                .accessibilitySortPriority(OnboardingA11ySortPriority.primaryCTA)
                .accessibilityIdentifier("onboarding.paywall.cta")

                // Apple legally requires the trial price disclosure to be
                // visible near the CTA, not buried in fine print. Resolved
                // from the live StoreKit product when available; falls back
                // to a generic copy when products haven't loaded yet.
                Text(trialFinePrintCopy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .accessibilityLabel(Text(trialFinePrintCopy))

                Button {
                    finishOnboardingPaywall()
                } label: {
                    Text(NSLocalizedString("onboarding.paywall.later", comment: "Skip trial"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilitySortPriority(OnboardingA11ySortPriority.skip)
                .accessibilityIdentifier("onboarding.paywall.later")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .accessibilityElement(children: .contain)
        .task {
            // Eager product load so the price is rendered before the user
            // even reads the bullets — no "loading…" flash on tap.
            if subscription.products.isEmpty {
                await subscription.loadProducts()
            }
        }
    }

    @ViewBuilder
    private func onboardingPaywallBullet(_ icon: String, key: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255))
                .frame(width: 24)
            Text(NSLocalizedString(key, comment: ""))
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Resolves the StoreKit-driven fine-print copy. Falls back to a
    /// localized generic line when products haven't loaded yet — never
    /// shows an empty string, which would let the CTA float without
    /// disclosure (App Store 3.1.2 requirement).
    private var trialFinePrintCopy: String {
        let monthly = subscription.products.first(where: { $0.id == SubscriptionService.monthlyProductID })
        if let monthly {
            let fmt = NSLocalizedString("onboarding.paywall.fineprint.format",
                                        comment: "Trial fineprint with %@ price")
            return String(format: fmt, monthly.displayPrice)
        }
        return NSLocalizedString("onboarding.paywall.fineprint.fallback",
                                 comment: "Trial fineprint without price")
    }

    private func runOnboardingPurchase() async {
        guard let product = subscription.products.first(where: { $0.id == SubscriptionService.monthlyProductID })
                ?? subscription.products.first
        else {
            // StoreKit catalog empty (sandbox not configured / offline). In
            // DEBUG SubscriptionService._setEntitlementForTesting could be
            // called here, but the cleaner UX in Release is to finish
            // onboarding silently so the user isn't trapped on a dead button.
            #if DEBUG
            subscription._setEntitlementForTesting(.proTrial)
            #endif
            finishOnboardingPaywall()
            return
        }
        paywallPurchaseInFlight = true
        defer { paywallPurchaseInFlight = false }
        let unlocked = await subscription.purchase(product)
        // Whether purchase succeeded or the user cancelled at the StoreKit
        // sheet, the onboarding paywall is "done" — we don't re-prompt.
        finishOnboardingPaywall()
        _ = unlocked  // status reflected via subscription.entitlement everywhere else
    }

    @ViewBuilder
    private func styleRow(_ style: UserPreferences.SoloTravelStyle) -> some View {
        let selected = preferences.soloTravelStyle == style
        Button {
            Haptics.selection()
            preferences.soloTravelStyle = style
        } label: {
            HStack(spacing: 14) {
                Image(systemName: styleIcon(style))
                    .font(.title3)
                    .foregroundStyle(selected ? Color.white : Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(selected ? Color.accentColor : Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.localizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(style.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? Color.accentColor.opacity(0.08) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(style.localizedTitle), \(style.localizedDescription)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func styleIcon(_ style: UserPreferences.SoloTravelStyle) -> String {
        switch style {
        case .explorer:      return "figure.walk"
        case .worker:        return "laptopcomputer"
        case .foodie:        return "fork.knife"
        case .cultureSeeker: return "building.columns"
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .environment(LocationService.shared)
        .environment(UserPreferences())
        .environment(SubscriptionService())
}
