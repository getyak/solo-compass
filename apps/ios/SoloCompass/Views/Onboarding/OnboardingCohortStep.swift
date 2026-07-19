import SwiftUI

/// Nomad OS B1-e onboarding step: how often does the traveler change cities?
///
/// This is the data floor for the digital-nomad convergence strategy — the
/// selected band (`UserPreferences.NomadCohort`) maps directly to the sharpness
/// of the visa / 90-180-day compliance pain point, and so to willingness to pay
/// for the B2 ledger. It sits right after the travel-style step: both answer
/// "who is this traveler", so they read as one identity beat.
///
/// Mirrors `OnboardingCityStep`'s shape — a standalone view driven by an
/// `onContinue` callback, embedded inside the shared step chrome by
/// `OnboardingView`. Selecting a band writes `preferences.nomadCohort`
/// immediately (a tap is a commit), so there is no separate save action and the
/// signal survives even if the user force-quits before finishing onboarding.
public struct OnboardingCohortStep: View {

    /// Called when the user confirms a band (or taps continue after selecting).
    public let onContinue: () -> Void

    @Environment(UserPreferences.self) private var preferences

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 24) {
                header

                VStack(spacing: 10) {
                    ForEach(UserPreferences.NomadCohort.selectableCases) { cohort in
                        cohortRow(cohort)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)
            Spacer(minLength: 0)

            actions
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 24) {
            Text(NSLocalizedString("onboarding.cohort.title", comment: "Cohort step title"))
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("onboarding.cohort.subtitle", comment: "Cohort step subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func cohortRow(_ cohort: UserPreferences.NomadCohort) -> some View {
        let selected = preferences.nomadCohort == cohort
        return Button {
            Haptics.selection()
            preferences.nomadCohort = cohort
        } label: {
            HStack(spacing: 14) {
                Image(systemName: cohort.symbol)
                    .font(.title3)
                    .foregroundStyle(selected ? Color.white : CT.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(selected ? CT.accent : CT.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(cohort.localizedTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(cohort.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(CT.accent)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? CT.accent.opacity(0.08) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selected ? CT.accent : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(cohort.localizedTitle), \(cohort.localizedDescription)"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                onContinue()
            } label: {
                Text(NSLocalizedString("onboarding.cohort.cta", comment: "Continue after picking a frequency"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(CT.accent, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }

            Button {
                onContinue()
            } label: {
                Text(NSLocalizedString("onboarding.cohort.skip", comment: "Skip picking a frequency"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 48)
    }
}

// MARK: - NomadCohort display

extension UserPreferences.NomadCohort {
    /// SF Symbol for each band — a rising cadence from a single anchor
    /// (settled) to a globe (frequent). `.unset` is never rendered as a row.
    var symbol: String {
        switch self {
        case .unset:    return "questionmark"
        case .settled:  return "house"
        case .slow:     return "leaf"
        case .active:   return "airplane"
        case .frequent: return "globe"
        }
    }

    var localizedTitle: String {
        switch self {
        case .unset:
            return NSLocalizedString("onboarding.cohort.unset.title", comment: "Cohort: not set")
        case .settled:
            return NSLocalizedString("onboarding.cohort.settled.title", comment: "Cohort: settled")
        case .slow:
            return NSLocalizedString("onboarding.cohort.slow.title", comment: "Cohort: slow travel")
        case .active:
            return NSLocalizedString("onboarding.cohort.active.title", comment: "Cohort: active nomad")
        case .frequent:
            return NSLocalizedString("onboarding.cohort.frequent.title", comment: "Cohort: high frequency")
        }
    }

    var localizedDescription: String {
        switch self {
        case .unset:
            return ""
        case .settled:
            return NSLocalizedString("onboarding.cohort.settled.desc", comment: "1-2 cities a year")
        case .slow:
            return NSLocalizedString("onboarding.cohort.slow.desc", comment: "3-5 cities a year")
        case .active:
            return NSLocalizedString("onboarding.cohort.active.desc", comment: "6-11 cities a year")
        case .frequent:
            return NSLocalizedString("onboarding.cohort.frequent.desc", comment: "12+ cities a year")
        }
    }
}

#Preview {
    OnboardingCohortStep(onContinue: {})
        .environment(UserPreferences())
}
