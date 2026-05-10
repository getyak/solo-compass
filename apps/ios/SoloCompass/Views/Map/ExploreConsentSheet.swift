import SwiftUI
import UIKit

/// First-run consent sheet shown the very first time a user taps the
/// Explore-Here button (or triggers a voice-driven explore intent).
///
/// We tell them — in plain language — what data leaves the device:
///   1. coarse location → OpenStreetMap (no account, no tracking)
///   2. raw OSM tags + city slug → Anthropic (no PII, no user content)
///   3. nothing else: no contacts, no purchase history, no ads
///
/// The sheet is one-time. Tapping "Got it" persists
/// `UserPreferences.hasAcceptedExploreConsent = true` and the user
/// never sees it again. Cancel just dismisses without recording — the
/// next tap will show the sheet again.
struct ExploreConsentSheet: View {

    let onAccept: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255))
                    .padding(.top, 32)

                Text(NSLocalizedString("explore.consent.title", comment: "Title for explore consent sheet"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(NSLocalizedString("explore.consent.subtitle", comment: "Subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(alignment: .leading, spacing: 16) {
                bullet(
                    icon: "location.fill",
                    text: NSLocalizedString("explore.consent.bullet.location", comment: "Coarse location to OSM")
                )
                bullet(
                    icon: "sparkles",
                    text: NSLocalizedString("explore.consent.bullet.ai", comment: "OSM tags to Anthropic")
                )
                bullet(
                    icon: "lock.shield.fill",
                    text: NSLocalizedString("explore.consent.bullet.no_pii", comment: "No PII never tracked")
                )
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)

            Spacer()

            VStack(spacing: 10) {
                Button(action: onAccept) {
                    Text(NSLocalizedString("explore.consent.accept", comment: "Got it, continue"))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onCancel) {
                    Text(NSLocalizedString("explore.consent.cancel", comment: "Cancel"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(UIColor.systemBackground))
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func bullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color(red: 0xD4/255, green: 0xA8/255, blue: 0x43/255))
                .frame(width: 24, alignment: .center)
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// Lifts the Explore-consent sheet binding off CompassMapView.body so
/// the SwiftUI type-checker does not blow its budget on the long
/// modifier chain there.
struct ExploreConsentSheetModifier: ViewModifier {
    var viewModel: MapViewModel?
    var preferences: UserPreferences

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { viewModel?.isShowingExploreConsent ?? false },
            set: { newValue in
                if !newValue { viewModel?.isShowingExploreConsent = false }
            }
        )) {
            ExploreConsentSheet(
                onAccept: {
                    preferences.acceptExploreConsent()
                    viewModel?.isShowingExploreConsent = false
                    let resume = viewModel?.onExploreConsentAccepted
                    viewModel?.onExploreConsentAccepted = nil
                    resume?()
                },
                onCancel: {
                    viewModel?.onExploreConsentAccepted = nil
                    viewModel?.isShowingExploreConsent = false
                }
            )
        }
    }
}

#Preview("ExploreConsentSheet") {
    ExploreConsentSheet(
        onAccept: { print("accepted") },
        onCancel: { print("cancelled") }
    )
}
