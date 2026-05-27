import SwiftUI

/// Companion profile settings — avatar emoji, bio, languages, and visibility.
///
/// US-009: visibility defaults to `.off`; when off the user never appears in
/// any discovery list. Users can escalate to `itinerary_only` or
/// `nearby_and_itinerary` at any time.
public struct CompanionProfileView: View {
    @Environment(UserPreferences.self) private var preferences

    @State private var showingEmojiPicker = false
    @State private var languageInput = ""

    // Common travel-language options
    private static let suggestedLanguages: [(code: String, name: String)] = [
        ("en", "English"), ("zh", "中文"), ("ja", "日本語"),
        ("ko", "한국어"), ("es", "Español"), ("fr", "Français"),
        ("de", "Deutsch"), ("pt", "Português"), ("it", "Italiano"),
        ("th", "ภาษาไทย"), ("ar", "العربية"), ("hi", "हिन्दी"),
    ]

    private static let avatarEmojis = [
        "🧭", "🌏", "🗺️", "✈️", "🎒", "🚀", "🌄", "🏔️", "🌊", "🌿",
        "🦋", "🐉", "🦊", "🌙", "⭐", "🔥", "💫", "🌸", "🍀", "🎭",
    ]

    public init() {}

    public var body: some View {
        @Bindable var prefs = preferences
        NavigationStack {
            Form {
                avatarSection(prefs: prefs)
                bioSection(prefs: prefs)
                languagesSection(prefs: prefs)
                visibilitySection(prefs: prefs)
            }
            .navigationTitle(NSLocalizedString("companion.profile.title", comment: "Companion Profile nav title"))
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func avatarSection(prefs: Bindable<UserPreferences>) -> some View {
        Section {
            HStack {
                Spacer()
                Button {
                    showingEmojiPicker.toggle()
                } label: {
                    Text(preferences.companionAvatarEmoji)
                        .font(.system(size: 64))
                        .frame(width: 96, height: 96)
                        .background(
                            Circle().fill(Color.accentColor.opacity(0.1))
                        )
                }
                .accessibilityLabel(NSLocalizedString("companion.profile.avatar.a11y", comment: "Change avatar emoji"))
                Spacer()
            }
            .listRowBackground(Color.clear)

            if showingEmojiPicker {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(Self.avatarEmojis, id: \.self) { emoji in
                        Button {
                            preferences.companionAvatarEmoji = emoji
                            showingEmojiPicker = false
                        } label: {
                            Text(emoji)
                                .font(.system(size: 32))
                                .frame(width: 52, height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(preferences.companionAvatarEmoji == emoji
                                              ? Color.accentColor.opacity(0.2)
                                              : Color(.systemBackground))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(emoji)
                    }
                }
                .padding(.vertical, 8)
            }
        } header: {
            Text(NSLocalizedString("companion.profile.avatar.header", comment: "Avatar section header"))
        } footer: {
            Text(NSLocalizedString("companion.profile.avatar.footer", comment: "No real photo — emoji only"))
        }
    }

    @ViewBuilder
    private func bioSection(prefs: Bindable<UserPreferences>) -> some View {
        Section {
            TextField(
                NSLocalizedString("companion.profile.bio.placeholder", comment: "Bio text field placeholder"),
                text: prefs.companionBio,
                axis: .vertical
            )
            .lineLimit(3...6)
            .onChange(of: preferences.companionBio) { _, new in
                if new.count > 280 {
                    preferences.companionBio = String(new.prefix(280))
                }
            }
        } header: {
            Text(NSLocalizedString("companion.profile.bio.header", comment: "Bio section header"))
        } footer: {
            Text(String(
                format: NSLocalizedString("companion.profile.bio.footer", comment: "Character count footer"),
                preferences.companionBio.count, 280
            ))
        }
    }

    @ViewBuilder
    private func languagesSection(prefs: Bindable<UserPreferences>) -> some View {
        Section {
            let currentCodes = Set(preferences.companionLanguages)
            ForEach(Self.suggestedLanguages, id: \.code) { lang in
                Button {
                    if currentCodes.contains(lang.code) {
                        preferences.companionLanguages.removeAll { $0 == lang.code }
                    } else {
                        preferences.companionLanguages.append(lang.code)
                    }
                } label: {
                    HStack {
                        Text(lang.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if currentCodes.contains(lang.code) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .font(.footnote.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(NSLocalizedString("companion.profile.languages.header", comment: "Languages section header"))
        } footer: {
            Text(NSLocalizedString("companion.profile.languages.footer", comment: "Languages section footer"))
        }
    }

    @ViewBuilder
    private func visibilitySection(prefs: Bindable<UserPreferences>) -> some View {
        Section {
            ForEach(CompanionVisibility.allCases, id: \.self) { option in
                Button {
                    preferences.companionVisibility = option
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: visibilityIcon(option))
                            .frame(width: 24)
                            .foregroundStyle(
                                preferences.companionVisibility == option
                                ? Color.accentColor : .secondary
                            )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(visibilityTitle(option))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(visibilityDescription(option))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if preferences.companionVisibility == option {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text(NSLocalizedString("companion.profile.visibility.header", comment: "Visibility section header"))
        } footer: {
            if preferences.companionVisibility == .off {
                Text(NSLocalizedString("companion.profile.visibility.off.footer", comment: "Off visibility explanation"))
            }
        }
    }

    // MARK: - Helpers

    private func visibilityIcon(_ v: CompanionVisibility) -> String {
        switch v {
        case .off: return "eye.slash"
        case .itinerary_only: return "map"
        case .nearby_and_itinerary: return "person.2.wave.2"
        }
    }

    private func visibilityTitle(_ v: CompanionVisibility) -> String {
        switch v {
        case .off:
            return NSLocalizedString("companion.visibility.off.title", comment: "Off visibility title")
        case .itinerary_only:
            return NSLocalizedString("companion.visibility.itinerary_only.title", comment: "Itinerary-only visibility title")
        case .nearby_and_itinerary:
            return NSLocalizedString("companion.visibility.nearby_and_itinerary.title", comment: "Nearby + itinerary visibility title")
        }
    }

    private func visibilityDescription(_ v: CompanionVisibility) -> String {
        switch v {
        case .off:
            return NSLocalizedString("companion.visibility.off.description", comment: "Off visibility description")
        case .itinerary_only:
            return NSLocalizedString("companion.visibility.itinerary_only.description", comment: "Itinerary-only visibility description")
        case .nearby_and_itinerary:
            return NSLocalizedString("companion.visibility.nearby_and_itinerary.description", comment: "Nearby + itinerary visibility description")
        }
    }
}

// MARK: - Preview

#Preview("Default (off)") {
    CompanionProfileView()
        .environment(UserPreferences())
}

#Preview("Configured profile") {
    let prefs = UserPreferences()
    prefs.companionAvatarEmoji = "🌊"
    prefs.companionBio = "Solo traveler, 12 countries. Coffee shops and hidden temples."
    prefs.companionLanguages = ["en", "zh", "ja"]
    prefs.companionVisibility = .itinerary_only
    return CompanionProfileView()
        .environment(prefs)
}
