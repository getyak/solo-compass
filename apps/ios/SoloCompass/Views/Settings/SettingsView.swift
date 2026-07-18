import SwiftData
import SwiftUI

/// User preferences editor — travel style, category filters, max distance.
/// Accessed via the map's navigation bar settings button.
///
/// P1.3 #130 — consolidated from 14 sections to 6 + a hidden Advanced group:
///
/// 1. **Your Taste** — travel style, category preferences, filter-bar
///    customization (all child pages, current value shown on the row).
/// 2. **Discovery** — radius slider + nearby-nudge toggle.
/// 3. **Appearance & Language** — theme, haptics, language (menu picker;
///    a real language change still schedules the restart alert).
/// 4. **Companion** — the opt-in toggle plus a single hub link that
///    replaces the former 5 inline NavigationLinks.
/// 5. **Account** — Apple ID link + subscription status / restore / manage.
/// 6. **Data & About** — export toggle, destructive resets, version row.
///
/// Power-user surfaces (AI provider, tester-email unlock, developer
/// options) are hidden behind a 7-tap gesture on the version row. The
/// former Stats section was removed — the same numbers live in MeSheet.
public struct SettingsView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(ExperienceService.self) private var experienceService
    @Environment(NotificationService.self) private var notificationService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(LanguageService.self) private var languageService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.themeService) private var themeService
    var onClose: () -> Void
    var onDistanceCommitted: (() -> Void)?

    @State private var showingClearConfirm = false
    // P2.0 #204: "Forget me" — wipes the AgentMemorySnapshot + TasteProfile
    // singletons so the Chat Agent no longer greets the user by past habits.
    // Separate confirm from the broader `showingClearConfirm` because this
    // one specifically targets AI-personalisation state, not routes /
    // favorites / preferences.
    @State private var showingForgetMeConfirm = false
    @State private var forgetMeToast: String?
    // Data-sovereignty export twin of "Forget me". Renders the four
    // high-stickiness personal assets (visits / capsules / notes / taste) to
    // temp files and hands them to a share sheet so they survive device
    // migration. `exportedFileURLs` non-empty drives the share sheet; the toast
    // covers the empty-data case (nothing accrued yet → no files to share).
    @State private var exportedFileURLs: [URL] = []
    @State private var showingExportShare = false
    @State private var exportToast: String?
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

    // US-012: Companion opt-in safety consent gate
    @State private var showingCompanionConsent = false

    // #130: Advanced tools reveal — 7 taps on the version row, persisted so
    // the user never has to rediscover the gesture.
    @AppStorage("settings.advancedUnlocked") private var advancedUnlocked = false
    @State private var versionTapCount = 0

    public init(
        onClose: @escaping () -> Void = {},
        onDistanceCommitted: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onDistanceCommitted = onDistanceCommitted
    }

    public var body: some View {
        NavigationStack {
            List {
                tasteSection
                discoverySection
                appearanceSection
                companionSection
                accountSection
                dataAboutSection
                advancedSection
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
            // US-020: Companion safety consent. Anchored to the stable List —
            // NOT to `companionSection` — so List row recycling can't tear
            // down the presentation source mid-transition. Accepting flips
            // `companionEnabled`, which grows that Section by a row; when the
            // sheet was anchored to the Section, that row churn destroyed its
            // own presentation anchor and crashed on device, leaving the flag
            // unwritten ("enable failed").
            .sheet(isPresented: $showingCompanionConsent) {
                // Cancel path: companionEnabled stays false (only accept
                // writes it). The Toggle re-reads from preferences and
                // auto-rolls-back. The sheet dismisses itself via the
                // environment `dismiss`, which resets this binding — so we
                // only flip the persisted flag here (no double dismissal).
                CompanionSafetyConsentSheet(onAccepted: {
                    preferences.companionEnabled = true
                })
                .environment(preferences)
            }
        }
    }

    // MARK: - 1. Your Taste

    private var tasteSection: some View {
        Section {
            NavigationLink {
                TravelStyleSettingsView()
                    .environment(preferences)
            } label: {
                settingsIconRow(
                    icon: "figure.walk", color: .blue,
                    label: NSLocalizedString("settings.travelStyle", comment: "Travel Style"),
                    value: preferences.soloTravelStyle.localizedTitle
                )
            }

            NavigationLink {
                CategoryPreferencesView()
                    .environment(preferences)
            } label: {
                settingsIconRow(
                    icon: "square.grid.2x2", color: .pink,
                    label: NSLocalizedString("settings.preferences", comment: "Category Preferences"),
                    value: String(
                        format: NSLocalizedString("settings.categories.value", comment: "Loved/hidden counts"),
                        preferences.preferredCategories.count,
                        preferences.dislikedCategories.count
                    )
                )
            }

            NavigationLink {
                VisibleCategoriesView()
                    .environment(preferences)
            } label: {
                settingsIconRow(
                    icon: "line.3.horizontal.decrease.circle", color: .indigo,
                    label: NSLocalizedString("settings.filter.visible_categories", comment: "Visible categories"),
                    value: "\(preferences.visibleCategories.count)/\(ExperienceCategory.allCases.count)"
                )
            }

            NavigationLink {
                CustomTagsView()
                    .environment(preferences)
            } label: {
                settingsIconRow(
                    icon: "tag", color: .purple,
                    label: NSLocalizedString("settings.filter.custom_tags", comment: "Custom tags"),
                    value: "\(preferences.customTags.count)"
                )
            }
        } header: {
            settingsSectionHeader("heart", label: NSLocalizedString("settings.personalize", comment: "Your Taste"))
        } footer: {
            Text(NSLocalizedString("settings.personalize.footer", comment: "Taste section footer"))
        }
    }

    // MARK: - 2. Discovery

    private var discoverySection: some View {
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

            Toggle(isOn: Binding(
                get: { preferences.notificationsEnabled },
                set: { enabled in
                    preferences.notificationsEnabled = enabled
                    if enabled {
                        Task { await notificationService.requestAuthorization() }
                    }
                }
            )) {
                settingsIconLabel(
                    icon: "bell.badge", color: .red,
                    label: NSLocalizedString("settings.notifications", comment: "Notifications")
                )
            }
        } header: {
            settingsSectionHeader("location.circle", label: NSLocalizedString("settings.discovery", comment: "Discovery"))
        } footer: {
            Text(NSLocalizedString("settings.discovery.footer", comment: "Discovery section footer"))
        }
    }

    // MARK: - 3. Appearance & Language

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

            Toggle(isOn: Binding(
                get: { HapticService.shared.isEnabled },
                set: { newValue in
                    HapticService.shared.isEnabled = newValue
                    if newValue {
                        HapticService.shared.impact(style: .light)
                    }
                }
            )) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(
                            LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                    Text(NSLocalizedString("settings.haptics.toggle", comment: "Haptic Feedback"))
                }
            }
            .accessibilityLabel(NSLocalizedString("settings.haptics.toggle.a11y", comment: "Toggle haptic feedback"))

            // Language collapsed from 3 checkmark rows to one menu picker.
            // A *real* change still schedules the restart alert (US-044).
            Picker(selection: Binding(
                get: { languageService.current },
                set: { option in
                    Haptics.selection()
                    if languageService.setLanguage(option) {
                        showingLanguageRestartAlert = true
                    }
                }
            )) {
                ForEach(LanguageService.Option.allCases) { option in
                    Text(languageOptionLabel(option)).tag(option)
                }
            } label: {
                settingsIconLabel(
                    icon: "globe", color: .blue,
                    label: NSLocalizedString("settings.language", comment: "Language")
                )
            }
            .pickerStyle(.menu)
        } header: {
            settingsSectionHeader("paintpalette", label: NSLocalizedString("settings.appearanceLanguage", comment: "Appearance & Language"))
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

    // MARK: - 4. Companion (US-012)

    /// US-012: Single experimental opt-in gate for the companion feature.
    /// false→true requires accepting the safety consent sheet; true→false
    /// is persisted immediately with no confirmation. When enabled, one hub
    /// link replaces the former 5 inline NavigationLinks.
    private var companionSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.companionEnabled },
                set: { newValue in
                    if newValue && !preferences.companionEnabled {
                        // false → true: gate behind safety consent
                        showingCompanionConsent = true
                    } else {
                        preferences.companionEnabled = newValue
                    }
                }
            )) {
                settingsIconLabel(
                    icon: "person.2.fill", color: .pink,
                    label: NSLocalizedString("settings.companion.toggle", comment: "Companion toggle label")
                )
            }

            if preferences.companionEnabled {
                NavigationLink {
                    CompanionHubView()
                        .environment(preferences)
                } label: {
                    settingsIconLabel(
                        icon: "person.2.wave.2", color: .teal,
                        label: NSLocalizedString("settings.companion.hub", comment: "Companion hub link")
                    )
                }
            }
        } header: {
            settingsSectionHeader(
                "person.2",
                label: NSLocalizedString("settings.companion.header", comment: "Companion (Experimental) section header")
            )
        } footer: {
            Text(NSLocalizedString("settings.companion.footer", comment: "Companion section footer"))
        }
    }

    // MARK: - 5. Account

    private var accountSection: some View {
        Section {
            // US-036: Save with Apple (anonymous only) / Linked to Apple ID
            appleIDRow

            HStack {
                settingsIconLabel(
                    icon: "crown", color: .orange,
                    label: NSLocalizedString("settings.subscription", comment: "Subscription")
                )
                Spacer()
                Text(entitlementLabel)
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

            Link(
                NSLocalizedString("settings.manage", comment: "Manage subscription"),
                destination: URL(string: "https://apps.apple.com/account/subscriptions")!
            )
        } header: {
            settingsSectionHeader("person.crop.circle", label: NSLocalizedString("settings.account", comment: "Account"))
        }
        .alert(
            restoreToast ?? "",
            // Writable binding so any dismiss path clears the toast;
            // `.constant(...)` stayed true and could immediately re-present.
            isPresented: Binding(
                get: { restoreToast != nil },
                set: { if !$0 { restoreToast = nil } }
            ),
            actions: {
                Button(NSLocalizedString("common.ok", comment: "OK")) {
                    restoreToast = nil
                }
            }
        )
        .alert(
            appleSignInToast ?? "",
            isPresented: Binding(
                get: { appleSignInToast != nil },
                set: { if !$0 { appleSignInToast = nil } }
            ),
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

    // MARK: - 6. Data & About

    private var dataAboutSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { preferences.includeMapInExport },
                set: { preferences.includeMapInExport = $0 }
            )) {
                settingsIconLabel(
                    icon: "map", color: .teal,
                    label: NSLocalizedString("settings.exportMapPreview", comment: "Include map preview in exports")
                )
            }

            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                settingsIconLabel(
                    icon: "trash", color: .red,
                    label: NSLocalizedString("settings.clearData", comment: "Clear all data")
                )
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

            // Data-sovereignty export — the read-side twin of "Forget me".
            // Non-destructive, so it sits BEFORE the two nukes: offer the user
            // a way to carry their data out before offering ways to erase it.
            Button {
                let result = PersonalDataExporter.shared.exportEverything()
                if result.isEmpty {
                    exportToast = NSLocalizedString(
                        "settings.exportData.toast.empty",
                        comment: "Export empty (nothing accrued yet)"
                    )
                    return
                }
                exportedFileURLs = Self.writeExportFiles(result.files)
                if exportedFileURLs.isEmpty {
                    exportToast = NSLocalizedString(
                        "settings.exportData.toast.failure",
                        comment: "Export write failed"
                    )
                } else {
                    showingExportShare = true
                }
            } label: {
                settingsIconLabel(
                    icon: "square.and.arrow.up", color: .blue,
                    label: NSLocalizedString("settings.exportData", comment: "Export my data")
                )
            }
            .sheet(isPresented: $showingExportShare) {
                DataExportActivitySheet(items: exportedFileURLs)
            }

            // P2.0 #204: "Forget me" — narrower than Clear All Data. Wipes
            // the AgentMemorySnapshot + TasteProfile singletons so the
            // Chat Agent forgets any accumulated personalisation. Routes,
            // favorites, and preferences stay intact. Deliberately placed
            // AFTER Clear All Data because it's the softer of two nukes.
            Button(role: .destructive) {
                showingForgetMeConfirm = true
            } label: {
                settingsIconLabel(
                    icon: "brain.head.profile", color: .orange,
                    label: NSLocalizedString("settings.forgetMe", comment: "Forget me")
                )
            }
            .confirmationDialog(
                NSLocalizedString("settings.forgetMe.confirm.title", comment: "Forget me confirm title"),
                isPresented: $showingForgetMeConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("settings.forgetMe.confirm.action", comment: "Forget me action"), role: .destructive) {
                    let ok = MemoryDigestService.shared.forgetMe()
                    forgetMeToast = ok
                        ? NSLocalizedString("settings.forgetMe.toast.success", comment: "Forget me success")
                        : NSLocalizedString("settings.forgetMe.toast.failure", comment: "Forget me failure")
                }
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("settings.forgetMe.confirm.message", comment: "Forget me message"))
            }

            // #130: 7 taps here reveal the Advanced section (AI provider,
            // tester unlock, developer options). Persisted via @AppStorage.
            HStack {
                settingsIconLabel(
                    icon: "info.circle", color: .gray,
                    label: NSLocalizedString("settings.about.version", comment: "Version")
                )
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
            .onTapGesture { handleVersionTap() }
        } header: {
            settingsSectionHeader("externaldrive", label: NSLocalizedString("settings.dataAbout", comment: "Data & About"))
        }
        // P2.0 #204: forget-me result toast. Writable-binding pattern (see
        // the restoreToast alert above for why `.constant` was wrong).
        .alert(
            forgetMeToast ?? "",
            isPresented: Binding(
                get: { forgetMeToast != nil },
                set: { if !$0 { forgetMeToast = nil } }
            ),
            actions: {
                Button(NSLocalizedString("common.ok", comment: "OK")) {
                    forgetMeToast = nil
                }
            }
        )
        // Data-export result toast — covers the empty-data and write-failure
        // cases (success opens the share sheet instead of a toast). Same
        // writable-binding pattern as the two alerts above.
        .alert(
            exportToast ?? "",
            isPresented: Binding(
                get: { exportToast != nil },
                set: { if !$0 { exportToast = nil } }
            ),
            actions: {
                Button(NSLocalizedString("common.ok", comment: "OK")) {
                    exportToast = nil
                }
            }
        )
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// Write each exported `File` to a uniquely-scoped temp directory and
    /// return the URLs for the share sheet. A per-export subdirectory keeps
    /// filenames stable (the share target shows `solo-compass-visits-….csv`,
    /// not a UUID) while still avoiding collisions across repeat exports. A
    /// file that fails to write is skipped rather than aborting the whole
    /// export — the user still gets whatever assets serialized cleanly.
    private static func writeExportFiles(_ files: [PersonalDataExporter.File]) -> [URL] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("data-export-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return []
        }
        var urls: [URL] = []
        for file in files {
            let url = dir.appendingPathComponent(file.filename)
            do {
                try file.contents.write(to: url, atomically: true, encoding: .utf8)
                urls.append(url)
            } catch {
                continue
            }
        }
        return urls
    }

    private func handleVersionTap() {
        guard !advancedUnlocked else { return }
        versionTapCount += 1
        if versionTapCount >= 7 {
            advancedUnlocked = true
            Haptics.notify(.success)
        } else if versionTapCount >= 4 {
            // Progressive feedback so the gesture feels discoverable once found.
            Haptics.selection()
        }
    }

    // MARK: - Advanced (hidden behind 7-tap / tester unlock)

    /// Power-user tools kept out of the everyday list: AI provider config,
    /// the tester-email Pro unlock, and (once email-unlocked) developer
    /// options. `@ViewBuilder` so the section fully disappears otherwise.
    @ViewBuilder
    private var advancedSection: some View {
        if advancedUnlocked || subscriptionService.developerModeUnlocked {
            Section {
                NavigationLink {
                    AIProviderSettingsView()
                        .environment(preferences)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(aiStatusColor, in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(NSLocalizedString("settings.aiProvider", comment: "AI Provider row label"))
                                .font(.body)
                            Text(aiStatusSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Tester / admin email unlock — only unlocks when the entered
                // email is on the allow-list.
                Button {
                    adminEmailInput = ""
                    showingAdminUnlock = true
                } label: {
                    settingsIconLabel(
                        icon: "envelope.badge", color: .blue,
                        label: NSLocalizedString("settings.adminUnlock", comment: "Unlock with tester email")
                    )
                }
                .foregroundStyle(.primary)

                if subscriptionService.developerModeUnlocked {
                    NavigationLink {
                        DeveloperOptionsView()
                            .environment(preferences)
                            .environment(subscriptionService)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Color.gray, in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(NSLocalizedString("dev.title", comment: "Developer Options"))
                                    .font(.body)
                                Text(NSLocalizedString("dev.entry.subtitle", comment: "Developer options subtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                settingsSectionHeader("wrench.and.screwdriver", label: NSLocalizedString("settings.advanced", comment: "Advanced"))
            } footer: {
                Text(NSLocalizedString("settings.advanced.footer", comment: "Advanced section footer"))
            }
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
    }

    private var aiStatusColor: Color {
        preferences.aiApiKey.isEmpty ? .orange : .green
    }

    private var aiStatusSubtitle: String {
        preferences.aiApiKey.isEmpty
            ? NSLocalizedString("settings.aiProvider.status.unconfigured", comment: "AI not configured subtitle")
            : String(
                format: NSLocalizedString("settings.aiProvider.status.configured", comment: "AI configured subtitle"),
                preferences.aiProvider.displayName
              )
    }

    private var entitlementLabel: String {
        switch subscriptionService.entitlement {
        case .pro:        return NSLocalizedString("subscription.tier.pro", comment: "Subscription tier: Pro")
        case .proTrial:   return NSLocalizedString("subscription.tier.proTrial", comment: "Subscription tier: Pro trial")
        case .proExpired: return NSLocalizedString("subscription.tier.expired", comment: "Subscription tier: expired")
        case .free:       return NSLocalizedString("subscription.tier.free", comment: "Subscription tier: Free")
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

    // MARK: - Helpers

    private func distanceLabel(_ km: Double) -> String {
        if Locale.current.measurementSystem == .us {
            return String(format: "%.1f mi", km * 0.621371)
        }
        return km >= 10 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
    }
}

// MARK: - Shared row helpers

/// US-020: Apple Settings-style section header with subheadline medium weight.
func settingsSectionHeader(_ symbol: String, label: String) -> some View {
    Label(label, systemImage: symbol)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
}

/// US-020: 30×30 rounded filled icon + label (no trailing value).
func settingsIconLabel(icon: String, color: Color, label: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color, in: RoundedRectangle(cornerRadius: 7))
        Text(label)
    }
}

/// US-020: Row with a 30×30 rounded filled icon and a secondary trailing value.
func settingsIconRow(icon: String, color: Color, label: String, value: String) -> some View {
    HStack {
        settingsIconLabel(icon: icon, color: color, label: label)
        Spacer()
        Text(value).foregroundStyle(.secondary).monospacedDigit()
    }
}

// MARK: - Travel Style (child page)

/// #130: The former inline 4-row travel style section, now a child page.
struct TravelStyleSettingsView: View {
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        List {
            Section {
                ForEach(UserPreferences.SoloTravelStyle.allCases) { style in
                    HStack {
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
                    .onTapGesture { Haptics.selection(); preferences.soloTravelStyle = style }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(preferences.soloTravelStyle == style ? [.isButton, .isSelected] : .isButton)
                }
            } footer: {
                Text(NSLocalizedString("settings.travelStyle.footer", comment: "Travel style footer"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("settings.travelStyle", comment: "Travel Style"))
        .navigationBarTitleDisplayMode(.inline)
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
}

// MARK: - Category Preferences (child page)

/// #130: Merges the former "Preferred" + "Hidden" sections into one page —
/// tap to love, swipe left to hide, hidden list underneath.
struct CategoryPreferencesView: View {
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        List {
            Section {
                ForEach(ExperienceCategory.allCases) { category in
                    let isPreferred = preferences.preferredCategories.contains(category)
                    let isDisliked = preferences.dislikedCategories.contains(category)
                    HStack(spacing: 12) {
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
            } footer: {
                Text(NSLocalizedString("settings.preferences.footer", comment: "Category preferences footer"))
            }

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
                                Haptics.selection()
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
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("settings.preferences", comment: "Category Preferences"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func togglePreferred(_ category: ExperienceCategory) {
        Haptics.selection()
        preferences.dislikedCategories.removeAll { $0 == category }
        if preferences.preferredCategories.contains(category) {
            preferences.preferredCategories.removeAll { $0 == category }
        } else {
            preferences.preferredCategories.append(category)
        }
    }

    private func toggleDisliked(_ category: ExperienceCategory) {
        Haptics.notify(.warning)
        preferences.preferredCategories.removeAll { $0 == category }
        if preferences.dislikedCategories.contains(category) {
            preferences.dislikedCategories.removeAll { $0 == category }
        } else {
            preferences.dislikedCategories.append(category)
        }
    }
}

// MARK: - Companion Hub (child page)

/// #130: Single destination replacing the former 5 inline companion
/// NavigationLinks in the main settings list.
struct CompanionHubView: View {
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CompanionProfileView()
                        .environment(preferences)
                } label: {
                    settingsIconLabel(
                        icon: "person.crop.circle", color: .indigo,
                        label: NSLocalizedString("settings.companion.profile", comment: "Companion profile link")
                    )
                }

                NavigationLink {
                    MyRequestsListView()
                } label: {
                    settingsIconLabel(
                        icon: "tray.and.arrow.up", color: .orange,
                        label: NSLocalizedString("settings.companion.requests", comment: "My recruitment requests link")
                    )
                }

                NavigationLink {
                    CompanionConversationsListView()
                } label: {
                    settingsIconLabel(
                        icon: "bubble.left.and.bubble.right", color: .teal,
                        label: NSLocalizedString("settings.companion.conversations", comment: "Joined conversations link")
                    )
                }

                // US-032: Discover recruiting routes
                NavigationLink {
                    DiscoverRecruitingRoutesView()
                        .environment(preferences)
                } label: {
                    settingsIconLabel(
                        icon: "map.fill", color: .green,
                        label: NSLocalizedString("settings.companion.discover.routes", comment: "Discover recruiting routes link")
                    )
                }

                // US-034: My hosted routes (approval queue entry point)
                NavigationLink {
                    MyHostedRoutesListView()
                } label: {
                    settingsIconLabel(
                        // anti-pattern-lint:allow standard Apple SF Symbol for key access, not gamification
                        icon: "person.badge.key.fill", color: .purple,
                        label: NSLocalizedString("settings.companion.hosted.routes", comment: "My hosted routes link")
                    )
                }
            } footer: {
                Text(NSLocalizedString("settings.companion.footer", comment: "Companion section footer"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("settings.companion.hub", comment: "Companion hub"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Group Conversations List (US-037)

/// Lists all group-route conversations the current user participates in.
/// Replaces the US-012 stub with live SwiftData reads.
struct CompanionConversationsListView: View {
    @Environment(\.modelContext) private var modelContext
    // Use an explicit SortDescriptor array rather than the bare KeyPath +
    // `order:` overload of @Query. Under SWIFT_STRICT_CONCURRENCY=complete the
    // KeyPath overload triggers a "sending KeyPath risks data races" warning;
    // SortDescriptor is Sendable, so this form is clean.
    @Query(
        filter: #Predicate<ConversationRecord> { $0.type == "groupRoute" },
        sort: [SortDescriptor(\ConversationRecord.createdAt, order: .reverse)]
    ) private var records: [ConversationRecord]

    private var currentUserId: String? {
        DeviceIdentityService.shared.anonymousUserId
    }

    private var myGroupConversations: [Conversation] {
        let uid = currentUserId ?? ""
        return records.map(\.asValue).filter { $0.participantIds.contains(uid) }
    }

    var body: some View {
        List {
            if myGroupConversations.isEmpty {
                Text(NSLocalizedString(
                    "settings.companion.conversations.empty",
                    comment: "Empty state for joined conversations"
                ))
                .foregroundStyle(.secondary)
                .font(.subheadline)
            } else {
                ForEach(myGroupConversations) { conv in
                    NavigationLink {
                        ChatView(conversation: conv, currentUserId: currentUserId)
                    } label: {
                        GroupConversationRow(conversation: conv, modelContext: modelContext)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString(
            "settings.companion.conversations",
            comment: "Joined conversations title"
        ))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - GroupConversationRow

private struct GroupConversationRow: View {
    let conversation: Conversation
    let modelContext: ModelContext

    private var route: Route? {
        guard let rid = conversation.routeId else { return nil }
        return RouteStore(context: modelContext).get(RouteId(rawValue: rid))
    }

    private var memberCount: Int { conversation.participantIds.count }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.teal, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(route?.title ?? NSLocalizedString(
                    "companion.chat.group.unknownRoute",
                    comment: "Unknown route placeholder for group chat row"
                ))
                .font(.subheadline.weight(.medium))
                .lineLimit(1)

                Text(String(
                    format: NSLocalizedString(
                        "companion.chat.group.memberCount",
                        comment: "Group member count label, e.g. '3 members'"
                    ),
                    memberCount
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
        Haptics.selection()
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
            Haptics.notify(.error)
            errorMessage = NSLocalizedString(
                "settings.filter.custom_tags.empty_error",
                comment: "Empty tag error"
            )
            return
        }
        if preferences.customTags.contains(trimmed) {
            Haptics.notify(.error)
            errorMessage = NSLocalizedString(
                "settings.filter.custom_tags.duplicate_error",
                comment: "Duplicate tag error"
            )
            return
        }
        preferences.customTags.append(trimmed)
        Haptics.notify(.success)
        draft = ""
        errorMessage = nil
    }

    private func deleteTags(at offsets: IndexSet) {
        Haptics.impact(.light)
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

/// Wraps `UIActivityViewController` so the Settings data-export button can hand
/// the rendered files to the system share sheet. Mirrors the private wrapper in
/// `ShareSheet.swift`; kept file-private here to avoid coupling Settings to the
/// Experience share module.
private struct DataExportActivitySheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
