import SwiftUI

/// Companion profile settings — avatar emoji, bio, languages, and visibility.
///
/// US-009: visibility defaults to `.off`; when off the user never appears in
/// any discovery list. Users can escalate to `itinerary_only` or
/// `nearby_and_itinerary` at any time.
///
/// US-030: when `companionEnabled`, shows a 'walked routes' section with up to
/// 5 thumbnail cards. A 'view all' chip navigates to `MyWalkedRoutesListView`.
///
/// US-008: upgraded into the single "My Profile" edit surface. Adds a
/// `displayHandle` field (2–20 chars, not unique) alongside the existing
/// avatar / bio / languages editors. Saving writes `User.displayHandle`
/// (persisted via `UserPreferences.displayHandle`) plus the companion
/// profile fields. `MyProfileEditView` is the canonical name; the legacy
/// `CompanionProfileView` alias is kept for existing call sites.
public struct MyProfileEditView: View {
    @Environment(UserPreferences.self) private var preferences

    @State private var showingEmojiPicker = false
    @State private var languageInput = ""
    @State private var walkedRoutes: [Route] = []
    @State private var showAllWalked = false

    /// US-008: live draft of the handle field. Seeded from `preferences`
    /// on appear; committed back (trimmed) only when it passes validation.
    @State private var handleDraft = ""

    /// Inclusive bounds for `displayHandle` length. Not unique.
    private static let handleMinLength = 2
    private static let handleMaxLength = 20

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
                avatarSection(prefs: $prefs)
                handleSection
                bioSection(prefs: $prefs)
                languagesSection(prefs: $prefs)
                visibilitySection(prefs: $prefs)
                if preferences.companionEnabled {
                    walkedRoutesSection
                }
            }
            .navigationTitle(NSLocalizedString("profile.edit.title", comment: "My Profile nav title"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadWalkedRoutes()
                handleDraft = preferences.displayHandle
            }
            .navigationDestination(isPresented: $showAllWalked) {
                MyWalkedRoutesListView(routes: walkedRoutes)
            }
        }
    }

    // MARK: - Walked routes data

    private func loadWalkedRoutes() {
        let store = RouteStore()
        let currentUserId = DeviceIdentityService.shared.deviceID
        walkedRoutes = store.all().filter { route in
            route.verification.walkedBy.contains(currentUserId)
            || (route.companion?.confirmedMembers.contains(currentUserId) == true
                && route.companion?.status == .completed)
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
                            Circle().fill(CT.accent.opacity(0.1))
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
                                              ? CT.accent.opacity(0.2)
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

    // MARK: - Handle section (US-008)

    /// Trimmed draft used for validation and persistence.
    private var trimmedHandle: String {
        handleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A handle is valid when it is empty (cleared) or within the inclusive
    /// length bounds. Not checked for uniqueness — handles are display-only.
    private var isHandleValid: Bool {
        let count = trimmedHandle.count
        return count == 0 || (count >= Self.handleMinLength && count <= Self.handleMaxLength)
    }

    /// Commits the trimmed handle to `UserPreferences.displayHandle` whenever
    /// it is valid, so the change persists across reopen without an explicit
    /// Save button (the Form auto-saves each field).
    private func commitHandleIfValid() {
        guard isHandleValid else { return }
        if preferences.displayHandle != trimmedHandle {
            preferences.displayHandle = trimmedHandle
        }
    }

    @ViewBuilder
    private var handleSection: some View {
        Section {
            TextField(
                NSLocalizedString("profile.handle.placeholder", comment: "Display handle placeholder"),
                text: $handleDraft
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: handleDraft) { _, new in
                // Hard cap input length so the field can never exceed the max.
                if new.count > Self.handleMaxLength {
                    handleDraft = String(new.prefix(Self.handleMaxLength))
                }
                commitHandleIfValid()
            }
        } header: {
            Text(NSLocalizedString("profile.handle.header", comment: "Handle section header"))
        } footer: {
            if !isHandleValid {
                Text(String(
                    format: NSLocalizedString("profile.handle.invalid", comment: "Handle length validation message"),
                    Self.handleMinLength, Self.handleMaxLength
                ))
                .foregroundStyle(CT.savedRed)
            } else {
                Text(String(
                    format: NSLocalizedString("profile.handle.footer", comment: "Handle section footer"),
                    Self.handleMinLength, Self.handleMaxLength
                ))
            }
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
                                .foregroundStyle(CT.accent)
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

    // MARK: - Walked routes section (US-030)

    private var walkedRoutesPreview: [Route] { Array(walkedRoutes.prefix(5)) }

    @ViewBuilder
    private var walkedRoutesSection: some View {
        Section {
            if walkedRoutesPreview.isEmpty {
                Text(verbatim: "—")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(walkedRoutesPreview) { route in
                            WalkedRouteCard(route: route)
                        }
                        if walkedRoutes.count > 5 {
                            Button {
                                showAllWalked = true
                            } label: {
                                Text(NSLocalizedString("profile.walkedRoutes.viewAll", comment: "View all walked routes chip"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(CT.accent)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(CT.accent.opacity(0.1))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text(String(
                format: NSLocalizedString("profile.walkedRoutes.header", comment: "Walked routes section header"),
                walkedRoutes.count
            ))
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
                                ? CT.accent : .secondary
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
                                .foregroundStyle(CT.accent)
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

// MARK: - Legacy alias

/// Backwards-compatible name for existing call sites (MeSheet, SettingsView).
/// US-008 renamed the view to `MyProfileEditView`; this alias avoids a
/// codebase-wide rename in unrelated files.
public typealias CompanionProfileView = MyProfileEditView

// MARK: - WalkedRouteCard (compact thumbnail ~140pt)

private struct WalkedRouteCard: View {
    let route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 8)
                .fill(CT.accent.opacity(0.15))
                .frame(width: 140, height: 76)
                .overlay(
                    Text(route.title.prefix(1))
                        .font(.largeTitle)
                )
            Text(route.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .frame(width: 140, alignment: .leading)
            Text("\(route.estimatedDuration) min")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140)
    }
}

// MARK: - Preview

#Preview("Default (off)") {
    CompanionProfileView()
        .environment(UserPreferences())
}

#Preview("Configured profile") {
    let prefs = UserPreferences()
    prefs.displayHandle = "wanderer"
    prefs.companionAvatarEmoji = "🌊"
    prefs.companionBio = "Solo traveler, 12 countries. Coffee shops and hidden temples."
    prefs.companionLanguages = ["en", "zh", "ja"]
    prefs.companionVisibility = .itinerary_only
    return MyProfileEditView()
        .environment(prefs)
}

#Preview("Companion enabled — walked routes empty") {
    let prefs = UserPreferences()
    prefs.companionEnabled = true
    return CompanionProfileView()
        .environment(prefs)
}
