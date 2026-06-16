import SwiftUI

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
    let onComplete: () -> Void

    @State private var step: Int = 0

    private static let totalSteps = 4

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
            default:
                styleStep
                    .transition(slideTransition)
                    .id(3)
            }
        }
        .overlay(alignment: .topTrailing) {
            skipButton
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Skip the whole flow

    /// Completes onboarding immediately from any step (returning users / QA).
    private var skipButton: some View {
        Button {
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
                    preferences.completeOnboarding()
                    onComplete()
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
                    preferences.completeOnboarding()
                    onComplete()
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
}
