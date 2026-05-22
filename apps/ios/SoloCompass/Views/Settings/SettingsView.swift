import AuthenticationServices
import SwiftData
import SwiftUI

/// User preferences editor — travel style, category filters, max distance.
/// Accessed via the map's navigation bar settings button.
public struct SettingsView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(ExperienceService.self) private var experienceService
    @Environment(NotificationService.self) private var notificationService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(LanguageService.self) private var languageService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeService) private var themeService
    var onClose: () -> Void
    var onShowFavorites: (() -> Void)?
    var onDistanceCommitted: (() -> Void)?

    @State private var showingClearConfirm = false
    @State private var restoreToast: String?
    @State private var restoreInFlight = false
    @State private var showingLanguageRestartAlert = false

    // Draft value shown in the label while the slider is being dragged.
    // Written to preferences.maxDistanceKm only on release.
    @State private var draftDistanceKm: Double? = nil

    // Admin / tester email unlock — bypasses StoreKit for allow-listed
    // emails so internal testers and the project owner can reach Pro
    // without a sandbox Apple ID.
    @State private var showingAdminUnlock = false
    @State private var adminEmailInput = ""

    // US-036: Apple ID link state
    @State private var isAnonymous: Bool = false
    @State private var appleSignInInFlight = false
    @State private var appleSignInToast: String?
    @State private var appleSignInService = AppleSignInService()

    public init(
        onClose: @escaping () -> Void = {},
        onShowFavorites: (() -> Void)? = nil,
        onDistanceCommitted: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onShowFavorites = onShowFavorites
        self.onDistanceCommitted = onDistanceCommitted
    }

    public var body: some View {
        NavigationStack {
            List {
                // US-020: Apple Settings-style InsetGrouped layout
                // Section: Preferences
                travelStyleSection
                preferredCategoriesSection
                dislikedCategoriesSection
                distanceSection
                // Section: Filter bar (US-007)
                filterBarSection
                // Section: Appearance (US-039)
                appearanceSection
                // Section: AI & Privacy
                languageSection
                notificationsSection
                exportSection
                // Section: Subscription
                subscriptionSection
                // Section: About / Stats / Data
                statsSection
                dataSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(NSLocalizedString("settings.title", comment: "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("settings.done", comment: "Done")) {
                        onClose()
                    }
                    .fontWeight(.semibold)
                }
            }
            .task {
                isAnonymous = await SupabaseClient.shared.isAnonymous
            }
        }
    }

    // MARK: - Travel Style

    private var travelStyleSection: some View {
        Section {
            ForEach(UserPreferences.SoloTravelStyle.allCases) { style in
                HStack {
                    // US-020: Rounded filled icon on the left
                    Image(systemName: travelStyleIcon(style))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(travelStyleColor(style), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.localizedTitle).font(.body)
                        Text(style.localizedDescription).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if preferences.soloTravelStyle == style {
                        Image(systemName: "checkmark").foregroundStyle(.blue).fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { preferences.soloTravelStyle = style }
            }
        } header: {
            settingsSectionHeader("figure.walk", label: NSLocalizedString("settings.travelStyle", comment: "Travel Style"))
        } footer: {
            Text(NSLocalizedString("settings.travelStyle.footer", comment: "Your style shapes which experiences float to the top."))
        }
    }

    private func travelStyleIcon(_ style: UserPreferences.SoloTravelStyle) -> String {
        switch style {
        case .explorer: return "map"
        case .worker: return "laptopcomputer"
        case .foodie: return "fork.knife"
        case .cultureSeeker: return "building.columns"
        }
    }

    private func travelStyleColor(_ style: UserPreferences.SoloTravelStyle) -> Color {
        switch style {
        case .explorer: return .blue
        case .worker: return .purple
        case .foodie: return .orange
        case .cultureSeeker: return .brown
        }
    }

    // MARK: - Preferred Categories

    private var preferredCategoriesSection: some View {
        Section {
            ForEach(ExperienceCategory.allCases) { category in
                let isPreferred = preferences.preferredCategories.contains(category)
                let isDisliked = preferences.dislikedCategories.contains(category)
                HStack(spacing: 12) {
                    // US-020: Rounded filled icon
                    Image(systemName: category.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(category.color, in: RoundedRectangle(cornerRadius: 7))
                    Text(category.localizedTitle)
                    Spacer()
                    if isPreferred {
                        Image(systemName: "heart.fill").foregroundStyle(.pink)
                    } else if isDisliked {
                        Image(systemName: "hand.thumbsdown.fill").foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { togglePreferred(category) }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { toggleDisliked(category) } label: {
                        Label(NSLocalizedString("settings.hide", comment: "Hide"), systemImage: "eye.slash")
                    }
                }
            }
        } header: {
            settingsSectionHeader("slider.horizontal.3", label: NSLocalizedString("settings.preferences", comment: "Preferences"))
        } footer: {
            Text(NSLocalizedString("settings.preferences.footer", comment: "Tap to love a category. Swipe left to hide it."))
        }
    }

    // MARK: - Disliked Categories

    @ViewBuilder
    private var dislikedCategoriesSection: some View {
        if !preferences.dislikedCategories.isEmpty {
            Section {
                ForEach(preferences.dislikedCategories) { category in
                    HStack(spacing: 12) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.secondary, in: RoundedRectangle(cornerRadius: 7))
                        Text(category.localizedTitle).foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            preferences.dislikedCategories.removeAll { $0 == category }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                settingsSectionHeader("eye.slash", label: NSLocalizedString("settings.hidden", comment: "Hidden Categories"))
            }
        }
    }

    // MARK: - Distance

    private var distanceSection: some View {
        Section {
            let displayedKm = draftDistanceKm ?? preferences.maxDistanceKm
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "location.magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.green, in: RoundedRectangle(cornerRadius: 7))
                    Text(NSLocalizedString("settings.maxDistance", comment: "Max Distance"))
                    Spacer()
                    Text(distanceLabel(displayedKm))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { draftDistanceKm ?? preferences.maxDistanceKm },
                        set: { draftDistanceKm = $0 }
                    ),
                    in: 1...25,
                    step: 0.5,
                    onEditingChanged: { editing in
                        if !editing, let draft = draftDistanceKm {
                            preferences.maxDistanceKm = draft
                            draftDistanceKm = nil
                            onDistanceCommitted?()
                        }
                    }
                ).tint(.blue)
            }
        } header: {
            settingsSectionHeader("location.circle", label: NSLocalizedString("settings.distance", comment: "Discovery Radius"))
        } footer: {
            Text(NSLocalizedString("settings.distance.footer", comment: "Only experiences within this radius appear on the map."))
        }
    }

    // MARK: - Filter Bar (US-007)

    private var filterBarSection: some View {
        Section {
            NavigationLink {
                VisibleCategoriesView()
                    .environment(preferences)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.indigo, in: RoundedRectangle(cornerRadius: 7))
                    Text(NSLocalizedString("settings.filter.visible_categories", comment: "Visible categories"))
                    Spacer()
                    Text("\(preferences.visibleCategories.count)/\(ExperienceCategory.allCases.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            // US-009: Custom tags management
            NavigationLink {
                CustomTagsView()
                    .environment(preferences)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 7))
                    Text(NSLocalizedString("settings.filter.custom_tags", comment: "Custom tags"))
                    Spacer()
                    Text("\(preferences.customTags.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            settingsSectionHeader(
                "slider.horizontal.below.rectangle",
                label: NSLocalizedString("settings.filterBar", comment: "Filter bar")
            )
        } footer: {
            Text(NSLocalizedString(
                "settings.filter.visible_categories.footer",
                comment: "Filter bar visible categories footer"
            ))
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.includeMapInExport },
                set: { preferences.includeMapInExport = $0 }
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "map")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.teal, in: RoundedRectangle(cornerRadius: 7))
                    Text(NSLocalizedString("settings.exportMapPreview", comment: "Include map preview in exports"))
                }
            }
        } header: {
            settingsSectionHeader("square.and.arrow.up", label: NSLocalizedString("export.preview", comment: "Export preview"))
        }
    }

    // MARK: - Notifications

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.notificationsEnabled },
                set: { enabled in
                    preferences.notificationsEnabled = enabled
                    if enabled {
                        Task { await notificationService.requestAuthorization() }
                    }
                }
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 7))
                    Text(NSLocalizedString("settings.notifications", comment: "Notifications"))
                }
            }
        } header: {
            settingsSectionHeader("bell", label: NSLocalizedString("settings.notifications.header", comment: "Notifications section header"))
        } footer: {
            Text(NSLocalizedString("settings.notifications.footer", comment: "Notifications footer"))
        }
    }

    // MARK: - Language

    private var languageSection: some View {
        Section {
            ForEach(LanguageService.Option.allCases) { option in
                HStack {
                    Image(systemName: "globe")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 7))
                    Text(languageOptionLabel(option))
                    Spacer()
                    if languageService.current == option {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if languageService.setLanguage(option) {
                        showingLanguageRestartAlert = true
                    }
                }
            }
        } header: {
            settingsSectionHeader("brain.head.profile", label: NSLocalizedString("settings.language", comment: "Language section header"))
        } footer: {
            Text(NSLocalizedString("settings.language.footer", comment: "Language footer"))
        }
        .alert(
            NSLocalizedString("settings.language.restart.title", comment: "Restart required"),
            isPresented: $showingLanguageRestartAlert
        ) {
            Button(NSLocalizedString("settings.language.restart.ok", comment: "OK")) {}
        } message: {
            Text(NSLocalizedString("settings.language.restart.message", comment: "Restart message"))
        }
    }

    private func languageOptionLabel(_ option: LanguageService.Option) -> String {
        switch option {
        case .system:
            return NSLocalizedString("settings.language.system", comment: "Follow system")
        case .english:
            return NSLocalizedString("settings.language.english", comment: "English")
        case .simplifiedChinese:
            return NSLocalizedString("settings.language.zh-Hans", comment: "Simplified Chinese")
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section {
            Button {
                onShowFavorites?()
                onClose()
            } label: {
                settingsIconRow(icon: "heart.fill", color: .red,
                                label: NSLocalizedString("settings.favorites", comment: "Favorites"),
                                value: "\(preferences.favoritedExperiences.count)")
            }
            .foregroundStyle(.primary)

            settingsIconRow(icon: "checkmark.circle", color: .green,
                            label: NSLocalizedString("settings.completed", comment: "Completed"),
                            value: "\(preferences.completedExperiences.count)")
        } header: {
            settingsSectionHeader("trophy", label: NSLocalizedString("settings.stats", comment: "Your Journey"))
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            // US-036: Save with Apple (anonymous only) / Linked to Apple ID
            appleIDRow

            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.red, in: RoundedRectangle(cornerRadius: 7))
                    Text(NSLocalizedString("settings.clearData", comment: "Clear all data"))
                }
            }
            .confirmationDialog(
                NSLocalizedString("settings.clearData.confirm.title", comment: "Clear all data confirm"),
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("settings.clearData.confirm.action", comment: "Clear"), role: .destructive) {
                    preferences.completedExperiences = []
                    preferences.favoritedExperiences = []
                    preferences.favoritedAt = [:]
                    preferences.visitHistory = [:]
                    preferences.pendingCheckIns = [:]
                    preferences.preferredCategories = []
                    preferences.dislikedCategories = []
                    experienceService.repo.clearAllUserData()
                }
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("settings.clearData.confirm.message", comment: "Clear all data message"))
            }
        } header: {
            settingsSectionHeader("externaldrive", label: NSLocalizedString("settings.data.header", comment: "Data section header"))
        }
        .alert(
            appleSignInToast ?? "",
            isPresented: .constant(appleSignInToast != nil),
            actions: {
                Button(NSLocalizedString("common.ok", comment: "OK")) {
                    appleSignInToast = nil
                }
            }
        )
    }

    @ViewBuilder
    private var appleIDRow: some View {
        if isAnonymous {
            Button {
                Task { await runAppleLink() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "applelogo")
                        .frame(width: 28)
                        .foregroundStyle(.primary)
                    Text(NSLocalizedString("settings.saveWithApple", comment: "Save with Apple"))
                    Spacer()
                    if appleSignInInFlight {
                        ProgressView()
                    }
                }
            }
            .disabled(appleSignInInFlight)
            .foregroundStyle(.primary)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "applelogo")
                    .frame(width: 28)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("settings.linkedToAppleID", comment: "Linked to Apple ID"))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "checkmark").foregroundStyle(.green)
            }
        }
    }

    private func runAppleLink() async {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }

        appleSignInInFlight = true
        defer { appleSignInInFlight = false }

        let result = await appleSignInService.link(
            presentationAnchor: window,
            context: modelContext
        )

        switch result {
        case .linked:
            isAnonymous = false
            appleSignInToast = NSLocalizedString("settings.appleLink.success", comment: "Apple link success")
        case .cancelled:
            break  // silent — user deliberately dismissed the sheet
        case .failed:
            appleSignInToast = NSLocalizedString("settings.appleLink.failure", comment: "Apple link failure")
        }
    }

    // MARK: - Helpers

    /// US-020: Apple Settings-style section header with subheadline medium weight.
    private func settingsSectionHeader(_ symbol: String, label: String) -> some View {
        Label(label, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    /// US-020: Row with a 30×30 rounded filled icon on the left.
    private func settingsIconRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 7))
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func labelRow(icon: String, color: Color, label: String, value: String) -> some View {
        settingsIconRow(icon: icon, color: color, label: label, value: value)
    }

    private func distanceLabel(_ km: Double) -> String {
        if Locale.current.measurementSystem == .us {
            return String(format: "%.1f mi", km * 0.621371)
        }
        return km >= 10 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
    }

    private func togglePreferred(_ category: ExperienceCategory) {
        preferences.dislikedCategories.removeAll { $0 == category }
        if preferences.preferredCategories.contains(category) {
            preferences.preferredCategories.removeAll { $0 == category }
        } else {
            preferences.preferredCategories.append(category)
        }
    }

    private func toggleDisliked(_ category: ExperienceCategory) {
        preferences.preferredCategories.removeAll { $0 == category }
        if preferences.dislikedCategories.contains(category) {
            preferences.dislikedCategories.removeAll { $0 == category }
        } else {
            preferences.dislikedCategories.append(category)
        }
    }

    // MARK: - Subscription section (Epic D US-025)

    private var subscriptionSection: some View {
        Section {
            HStack {
                Text(NSLocalizedString("settings.subscription", comment: "Subscription"))
                Spacer()
                Text(entitlementLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await runRestore() }
            } label: {
                HStack {
                    Text(NSLocalizedString("settings.restore", comment: "Restore purchases"))
                    Spacer()
                    if restoreInFlight {
                        ProgressView()
                    }
                }
            }
            .disabled(restoreInFlight)

            // Tester / admin email unlock — visible to everyone but only
            // unlocks when the entered email is on the allow-list.
            Button {
                adminEmailInput = ""
                showingAdminUnlock = true
            } label: {
                Text(NSLocalizedString("settings.adminUnlock", comment: "Unlock with tester email"))
            }

            Link(
                NSLocalizedString("settings.manage", comment: "Manage subscription"),
                destination: URL(string: "https://apps.apple.com/account/subscriptions")!
            )
        } header: {
            settingsSectionHeader("crown", label: NSLocalizedString("settings.subscription", comment: "Subscription"))
        }
        .alert(
            restoreToast ?? "",
            isPresented: .constant(restoreToast != nil),
            actions: {
                Button(NSLocalizedString("common.ok", comment: "OK")) {
                    restoreToast = nil
                }
            }
        )
        .alert(
            NSLocalizedString("settings.adminUnlock.title", comment: "Admin unlock title"),
            isPresented: $showingAdminUnlock
        ) {
            TextField(
                NSLocalizedString("settings.adminUnlock.placeholder", comment: "Email placeholder"),
                text: $adminEmailInput
            )
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
            Button(NSLocalizedString("settings.adminUnlock.action", comment: "Unlock")) {
                runAdminUnlock()
            }
        } message: {
            Text(NSLocalizedString("settings.adminUnlock.message", comment: "Admin unlock message"))
        }
    }

    private var entitlementLabel: String {
        switch subscriptionService.entitlement {
        case .pro:        return "Pro"
        case .proTrial:   return "Pro (trial)"
        case .proExpired: return "Expired"
        case .free:       return "Free"
        }
    }

    private func runRestore() async {
        restoreInFlight = true
        defer { restoreInFlight = false }
        let success = await subscriptionService.restorePurchases()
        restoreToast = NSLocalizedString(
            success ? "restore.success" : "restore.failure",
            comment: "Restore result"
        )
    }

    private func runAdminUnlock() {
        let success = subscriptionService.unlockWithAdminEmail(adminEmailInput)
        restoreToast = NSLocalizedString(
            success ? "settings.adminUnlock.success" : "settings.adminUnlock.failure",
            comment: "Admin unlock result"
        )
    }

    // MARK: - Appearance (US-039)

    private var appearanceSection: some View {
        Section {
            Picker(NSLocalizedString("settings.theme", comment: "Theme"), selection: Binding(
                get: { themeService.selectedOption },
                set: { themeService.selectedOption = $0 }
            )) {
                ForEach(ThemeService.ThemeOption.allCases) { option in
                    Text(option.localizedName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            settingsSectionHeader("paintpalette", label: NSLocalizedString("settings.appearance", comment: "Appearance"))
        }
    }
}

// MARK: - SoloTravelStyle display helpers

extension UserPreferences.SoloTravelStyle {
    var localizedTitle: String {
        NSLocalizedString("style.\(rawValue).title", comment: "Travel style title")
    }
    var localizedDescription: String {
        NSLocalizedString("style.\(rawValue).description", comment: "Travel style description")
    }
}

#Preview {
    SettingsView()
        .environment(UserPreferences())
        .environment(LanguageService())
}

// MARK: - Visible Categories (US-007)

/// Multi-select list of the 8 built-in ExperienceCategory cases. Toggling a
/// checkbox writes through to `UserPreferences.visibleCategories` immediately,
/// which persists via the existing UserDefaults Codable blob.
struct VisibleCategoriesView: View {
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        List {
            Section {
                ForEach(ExperienceCategory.allCases) { category in
                    let isOn = preferences.visibleCategories.contains(category)
                    HStack(spacing: 12) {
                        Image(systemName: category.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(category.color, in: RoundedRectangle(cornerRadius: 7))
                        Text(category.localizedTitle)
                        Spacer()
                        if isOn {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(category) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                }
            } footer: {
                Text(NSLocalizedString(
                    "settings.filter.visible_categories.footer",
                    comment: "Filter bar visible categories footer"
                ))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString(
            "settings.filter.visible_categories",
            comment: "Visible categories"
        ))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ category: ExperienceCategory) {
        var next = preferences.visibleCategories
        if next.contains(category) {
            next.remove(category)
        } else {
            next.insert(category)
        }
        preferences.visibleCategories = next
    }
}

#Preview {
    NavigationStack {
        VisibleCategoriesView()
            .environment(UserPreferences())
    }
}

// MARK: - Custom Tags (US-009)

/// Management screen for `UserPreferences.customTags`. Lets the user add new
/// free-form tags via an inline text field + "Add" button, and remove existing
/// tags via swipe-to-delete. Mutations write through to `UserPreferences`
/// immediately, which `FilterBarView` observes and re-renders.
struct CustomTagsView: View {
    @Environment(UserPreferences.self) private var preferences

    @State private var draft: String = ""
    @State private var errorMessage: String?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    TextField(
                        NSLocalizedString(
                            "settings.filter.custom_tags.add_placeholder",
                            comment: "New tag placeholder"
                        ),
                        text: $draft
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit { addDraft() }
                    .onChange(of: draft) { _, _ in errorMessage = nil }

                    Button {
                        addDraft()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    .accessibilityLabel(NSLocalizedString(
                        "settings.filter.custom_tags.add",
                        comment: "Add tag"
                    ))
                    .buttonStyle(.plain)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                if preferences.customTags.isEmpty {
                    Text(NSLocalizedString(
                        "settings.filter.custom_tags.empty_state",
                        comment: "Empty custom tags hint"
                    ))
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                } else {
                    ForEach(preferences.customTags, id: \.self) { tag in
                        HStack(spacing: 12) {
                            Image(systemName: "tag.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.purple, in: RoundedRectangle(cornerRadius: 7))
                            Text(tag)
                            Spacer()
                        }
                    }
                    .onDelete(perform: deleteTags)
                }
            } footer: {
                Text(NSLocalizedString(
                    "settings.filter.custom_tags.footer",
                    comment: "Custom tags footer"
                ))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString(
            "settings.filter.custom_tags",
            comment: "Custom tags"
        ))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = NSLocalizedString(
                "settings.filter.custom_tags.empty_error",
                comment: "Empty tag error"
            )
            return
        }
        if preferences.customTags.contains(trimmed) {
            errorMessage = NSLocalizedString(
                "settings.filter.custom_tags.duplicate_error",
                comment: "Duplicate tag error"
            )
            return
        }
        preferences.customTags.append(trimmed)
        draft = ""
        errorMessage = nil
    }

    private func deleteTags(at offsets: IndexSet) {
        var next = preferences.customTags
        next.remove(atOffsets: offsets)
        preferences.customTags = next
    }
}

#Preview {
    NavigationStack {
        CustomTagsView()
            .environment(UserPreferences())
    }
}
