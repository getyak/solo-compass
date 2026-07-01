import SwiftUI

/// Onboarding step that pins the user's starting city + lets them describe
/// the kind of afternoon they want (P1.2 #121).
///
/// Deliberately lighter than the in-app `CityPickerSheet` — that view
/// requires a fully wired `MapViewModel`, which is overkill during the
/// pre-bootstrap onboarding window. We pick from a small hand-curated set
/// of cities (matching `MapViewModel.knownCityCenters`) and write the
/// selection straight to `preferences.lastSelectedCity`.
///
/// Voice input (todo.md #121: "语音/文字二选一") is intentionally text-only
/// in P1.2 — the existing `VoiceService` lives behind a permission dialog
/// and a microphone prompt, both of which we want to keep out of onboarding.
/// The text field captures the same intent, and the user can re-state it
/// via the Solo Agent once they're past onboarding.
public struct OnboardingCityStep: View {

    /// Called once the user picks a city + writes (or skips) the description.
    public let onContinue: () -> Void

    /// Curated launch cities — code → display label. Codes match
    /// `MapViewModel.knownCityCenters` so the persisted `lastSelectedCity`
    /// resolves to a real center on the first map render.
    public static let launchCities: [(code: String, label: String)] = [
        ("cmi", NSLocalizedString("city.cmi", comment: "Chiang Mai")),
        ("SZX", NSLocalizedString("city.szx", comment: "Shenzhen")),
        ("VTE", NSLocalizedString("city.vte", comment: "Vientiane")),
        ("san-francisco", NSLocalizedString("city.sf", comment: "San Francisco")),
    ]

    @Environment(UserPreferences.self) private var preferences
    @State private var selectedCode: String = "cmi"
    @State private var afternoonText: String = ""

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            cityPicker
            afternoonField
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .onAppear { hydrateFromPreferences() }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("onboarding.city.title", comment: "City step title"))
                .font(.system(.title2, design: .rounded).weight(.semibold))
            Text(NSLocalizedString("onboarding.city.subtitle", comment: "City step explainer"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var cityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("onboarding.city.label", comment: "City picker label"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker(
                NSLocalizedString("onboarding.city.label", comment: "City picker label"),
                selection: $selectedCode
            ) {
                ForEach(Self.launchCities, id: \.code) { city in
                    Text(city.label).tag(city.code)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var afternoonField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(NSLocalizedString("onboarding.city.afternoon.label", comment: "Afternoon question"))
                .font(.subheadline)
                .foregroundStyle(.primary)
            TextField(
                NSLocalizedString("onboarding.city.afternoon.placeholder", comment: "Afternoon description placeholder"),
                text: $afternoonText,
                axis: .vertical
            )
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
        }
    }

    private var actions: some View {
        Button {
            commit()
            onContinue()
        } label: {
            Text(NSLocalizedString("onboarding.city.continue", comment: "Continue button"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: - Persistence

    private func hydrateFromPreferences() {
        if let saved = preferences.lastSelectedCity,
           Self.launchCities.contains(where: { $0.code == saved }) {
            selectedCode = saved
        }
    }

    private func commit() {
        preferences.lastSelectedCity = selectedCode
        // The free-form afternoon text is captured into the user's customTags
        // as a single phrase — the `Solo Agent` (Phase 2) reads tags to bias
        // its first recommendations. Empty input is a no-op, so the user can
        // pick a city and move on without writing anything.
        let trimmed = afternoonText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            var tags = preferences.customTags
            if !tags.contains(trimmed) {
                tags.append(trimmed)
                preferences.customTags = tags
            }
        }
    }
}
