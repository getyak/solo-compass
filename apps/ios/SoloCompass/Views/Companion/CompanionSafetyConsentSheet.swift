import SwiftUI

/// US-020: First-time companion-enable safety disclaimer and consent gate.
///
/// Shown once before the user can set their companion visibility to anything
/// other than `.off`. Requires explicit age confirmation + consent to the
/// safety terms. The accepted state is persisted in UserPreferences.
///
/// Legal terms review is a MANUAL OPEN ITEM — the text below is placeholder
/// copy that must be reviewed by legal counsel before App Store submission.
public struct CompanionSafetyConsentSheet: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss

    /// Called when the user accepts all terms. The caller should then
    /// update companion visibility to the desired value.
    public let onAccepted: () -> Void

    @State private var ageConfirmed = false
    @State private var safetyConfirmed = false

    public init(onAccepted: @escaping () -> Void) {
        self.onAccepted = onAccepted
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    safetyRulesSection
                    privacySection
                    ageSection
                    checkboxesSection
                    legalFooter
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .navigationTitle(NSLocalizedString("companion.safety.title", comment: "Safety consent sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("common.cancel", comment: "Cancel button")) {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                consentButton
                    .padding()
                    .background(.regularMaterial)
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 8)

            Text(NSLocalizedString("companion.safety.heading", comment: "Safety heading"))
                .font(.title2.weight(.bold))

            Text(NSLocalizedString("companion.safety.subtitle", comment: "Safety subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var safetyRulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("companion.safety.rules.header", comment: "Safety rules header"))
                .font(.headline)

            safetyRule(
                icon: "location.slash",
                text: NSLocalizedString("companion.safety.rule.noPreciseLocation", comment: "No precise location rule")
            )
            safetyRule(
                icon: "building.2",
                text: NSLocalizedString("companion.safety.rule.meetInPublic", comment: "Meet in public rule")
            )
            safetyRule(
                icon: "flag",
                text: NSLocalizedString("companion.safety.rule.reportSuspicious", comment: "Report suspicious rule")
            )
            safetyRule(
                icon: "person.badge.minus",
                text: NSLocalizedString("companion.safety.rule.noObligation", comment: "No obligation rule")
            )
            safetyRule(
                icon: "bell.slash",
                text: NSLocalizedString("companion.safety.rule.emergency", comment: "Emergency clause — share itinerary with trusted contacts")
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func safetyRule(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(Color.accentColor)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("companion.safety.privacy.header", comment: "Privacy header"))
                .font(.headline)
            Text(NSLocalizedString("companion.safety.privacy.body", comment: "Privacy body explaining coarse location only"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var ageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("companion.safety.age.header", comment: "Age confirmation header"))
                .font(.headline)
            Text(NSLocalizedString("companion.safety.age.body", comment: "Minor protection statement"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private var checkboxesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $ageConfirmed) {
                Text(NSLocalizedString("companion.safety.age.confirm", comment: "Age confirmation checkbox"))
                    .font(.subheadline)
            }
            .toggleStyle(.checkmark)

            Toggle(isOn: $safetyConfirmed) {
                Text(NSLocalizedString("companion.safety.rules.confirm", comment: "Safety rules confirmation checkbox"))
                    .font(.subheadline)
            }
            .toggleStyle(.checkmark)
        }
    }

    private var legalFooter: some View {
        Text(NSLocalizedString("companion.safety.legal.footer", comment: "Legal footer — MANUAL OPEN ITEM: pending legal review"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

    private var consentButton: some View {
        Button {
            preferences.isSafetyConsentAccepted = true
            onAccepted()
            dismiss()
        } label: {
            Text(NSLocalizedString("companion.safety.accept", comment: "Accept and continue button"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!ageConfirmed || !safetyConfirmed)
    }
}

// MARK: - Checkmark toggle style

private struct CheckmarkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

private extension ToggleStyle where Self == CheckmarkToggleStyle {
    static var checkmark: CheckmarkToggleStyle { CheckmarkToggleStyle() }
}

// MARK: - Preview

#Preview("Consent sheet") {
    CompanionSafetyConsentSheet(onAccepted: {})
        .environment(UserPreferences())
}
