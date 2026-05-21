import SwiftUI
import CoreLocation

/// Three-step first-run flow shown once via `.fullScreenCover` from CompassMapView.
/// Gated by `UserPreferences.hasCompletedOnboarding`.
public struct OnboardingView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(UserPreferences.self) private var preferences
    let onComplete: () -> Void

    @State private var step: Int = 0

    public var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            switch step {
            case 0: welcomeStep
            case 1: styleStep
            default: welcomeStep
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Step 0: Welcome + location permission

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "map.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text(NSLocalizedString("onboarding.welcome.title", comment: "Onboarding title"))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text(NSLocalizedString("onboarding.welcome.subtitle", comment: "Onboarding subtitle"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

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

                Button {
                    step = 1
                } label: {
                    Text(NSLocalizedString("onboarding.welcome.skip", comment: "Browse first"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Step 1: Travel style

    private var styleStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Text(NSLocalizedString("onboarding.style.title", comment: "Travel style title"))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("onboarding.style.subtitle", comment: "Travel style subtitle"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                VStack(spacing: 10) {
                    ForEach(UserPreferences.SoloTravelStyle.allCases) { style in
                        styleRow(style)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

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

                Button {
                    preferences.completeOnboarding()
                    onComplete()
                } label: {
                    Text(NSLocalizedString("onboarding.style.skip", comment: "Decide later"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
        }
    }

    @ViewBuilder
    private func styleRow(_ style: UserPreferences.SoloTravelStyle) -> some View {
        let selected = preferences.soloTravelStyle == style
        Button {
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
