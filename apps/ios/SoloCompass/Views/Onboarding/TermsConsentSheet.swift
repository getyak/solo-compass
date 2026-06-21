import SwiftUI

/// First-launch Terms of Service + Privacy Policy + data-use disclosure.
/// App Store 审核 (Guideline 5.1.1) and PIPL/GDPR require a clear,
/// accept-or-quit gate before the app processes any personal data. We
/// piggyback the data-use summary (#63) into the same sheet so the user
/// reads everything once instead of being interrupted twice.
///
/// Storage: a single bool `SoloCompass.hasAcceptedTerms` in UserDefaults,
/// read at app launch via `TermsConsentSheet.hasAccepted`. No SwiftData /
/// UserPreferences snapshot involvement — the bit must survive every model
/// migration and codec failure, so it stays at the cheapest persistent layer.
public struct TermsConsentSheet: View {
    /// User confirmed acceptance — caller dismisses + bootstraps the rest of
    /// the app (location request, etc.).
    public var onAccept: () -> Void

    /// User refused. Caller usually exits or shows a "the app needs this to
    /// work" screen — Apple permits refuse-then-degrade but not silent-collect.
    public var onDecline: () -> Void

    private static let acceptedKey = "SoloCompass.hasAcceptedTerms"

    public static var hasAccepted: Bool {
        UserDefaults.standard.bool(forKey: acceptedKey)
    }

    public init(onAccept: @escaping () -> Void, onDecline: @escaping () -> Void = {}) {
        self.onAccept = onAccept
        self.onDecline = onDecline
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(NSLocalizedString("terms.title", comment: "Sheet title"))
                        .font(.title2.weight(.bold))
                        .padding(.top, 24)

                    Text(NSLocalizedString("terms.intro", comment: "One-paragraph intro"))
                        .font(.body)
                        .foregroundStyle(.secondary)

                    Divider()

                    // Data-use summary (subsumes #63 — telling the user what
                    // we collect + where it goes without making them read the
                    // full Privacy Policy).
                    Text(NSLocalizedString("terms.dataUse.title", comment: "Data use header"))
                        .font(.headline)

                    bullet("terms.dataUse.location")
                    bullet("terms.dataUse.chat")
                    bullet("terms.dataUse.noContacts")
                    bullet("terms.dataUse.noTrackers")

                    Divider()

                    Text(NSLocalizedString("terms.links.title", comment: "Documents header"))
                        .font(.headline)

                    Link(NSLocalizedString("terms.links.privacy", comment: "Privacy policy link"),
                         destination: URL(string: "https://solocompass.app/privacy")!)
                    Link(NSLocalizedString("terms.links.tos", comment: "Terms of service link"),
                         destination: URL(string: "https://solocompass.app/terms")!)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            VStack(spacing: 12) {
                Button {
                    UserDefaults.standard.set(true, forKey: Self.acceptedKey)
                    onAccept()
                } label: {
                    Text(NSLocalizedString("terms.button.accept", comment: "Accept all"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(role: .cancel, action: onDecline) {
                    Text(NSLocalizedString("terms.button.decline", comment: "Decline"))
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.regular)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .interactiveDismissDisabled() // Force user to choose; PIPL requires affirmative consent.
    }

    @ViewBuilder
    private func bullet(_ key: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(NSLocalizedString(key, comment: ""))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    TermsConsentSheet(onAccept: {}, onDecline: {})
}
