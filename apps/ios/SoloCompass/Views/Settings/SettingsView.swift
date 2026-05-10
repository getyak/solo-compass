import SwiftUI

/// User preferences editor — travel style, category filters, max distance.
/// Accessed via the map's navigation bar settings button.
public struct SettingsView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(NotificationService.self) private var notificationService
    @Environment(SubscriptionService.self) private var subscriptionService
    var onClose: () -> Void
    var onShowFavorites: (() -> Void)?

    @State private var showingClearConfirm = false
    @State private var restoreToast: String?
    @State private var restoreInFlight = false

    public init(onClose: @escaping () -> Void = {}, onShowFavorites: (() -> Void)? = nil) {
        self.onClose = onClose
        self.onShowFavorites = onShowFavorites
    }

    public var body: some View {
        NavigationStack {
            List {
                travelStyleSection
                preferredCategoriesSection
                dislikedCategoriesSection
                distanceSection
                notificationsSection
                subscriptionSection
                statsSection
                dataSection
            }
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
        }
    }

    // MARK: - Travel Style

    private var travelStyleSection: some View {
        Section {
            ForEach(UserPreferences.SoloTravelStyle.allCases) { style in
                HStack {
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
            Text(NSLocalizedString("settings.travelStyle", comment: "Travel Style"))
        } footer: {
            Text(NSLocalizedString("settings.travelStyle.footer", comment: "Your style shapes which experiences float to the top."))
        }
    }

    // MARK: - Preferred Categories

    private var preferredCategoriesSection: some View {
        Section {
            ForEach(ExperienceCategory.allCases) { category in
                let isPreferred = preferences.preferredCategories.contains(category)
                let isDisliked = preferences.dislikedCategories.contains(category)
                HStack(spacing: 12) {
                    Image(systemName: category.symbol).frame(width: 28).foregroundStyle(category.color)
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
            Text(NSLocalizedString("settings.preferences", comment: "Preferences"))
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
                        Image(systemName: category.symbol).frame(width: 28).foregroundStyle(.secondary)
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
                Text(NSLocalizedString("settings.hidden", comment: "Hidden Categories"))
            }
        }
    }

    // MARK: - Distance

    private var distanceSection: some View {
        Section {
            @Bindable var prefs = preferences
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(NSLocalizedString("settings.maxDistance", comment: "Max Distance"))
                    Spacer()
                    Text(distanceLabel(preferences.maxDistanceKm))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $prefs.maxDistanceKm, in: 1...25, step: 0.5).tint(.blue)
            }
        } header: {
            Text(NSLocalizedString("settings.distance", comment: "Discovery Radius"))
        } footer: {
            Text(NSLocalizedString("settings.distance.footer", comment: "Only experiences within this radius appear on the map."))
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
                        .foregroundStyle(.orange)
                        .frame(width: 28)
                    Text(NSLocalizedString("settings.notifications", comment: "Notifications"))
                }
            }
        } header: {
            Text(NSLocalizedString("settings.notifications.header", comment: "Notifications section header"))
        } footer: {
            Text(NSLocalizedString("settings.notifications.footer", comment: "Notifications footer"))
        }
    }

    // MARK: - Stats

    private var statsSection: some View {
        Section {
            Button {
                onShowFavorites?()
                onClose()
            } label: {
                labelRow(icon: "heart.fill", color: .red,
                         label: NSLocalizedString("settings.favorites", comment: "Favorites"),
                         value: "\(preferences.favoritedExperiences.count)")
            }
            .foregroundStyle(.primary)

            labelRow(icon: "checkmark.circle", color: .green,
                     label: NSLocalizedString("settings.completed", comment: "Completed"),
                     value: "\(preferences.completedExperiences.count)")
        } header: {
            Text(NSLocalizedString("settings.stats", comment: "Your Journey"))
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            Button(role: .destructive) {
                showingClearConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .frame(width: 28)
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
                }
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("settings.clearData.confirm.message", comment: "Clear all data message"))
            }
        } header: {
            Text(NSLocalizedString("settings.data.header", comment: "Data section header"))
        }
    }

    // MARK: - Helpers

    private func labelRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color).frame(width: 28)
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
        }
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

            Link(
                NSLocalizedString("settings.manage", comment: "Manage subscription"),
                destination: URL(string: "https://apps.apple.com/account/subscriptions")!
            )
        } header: {
            Text(NSLocalizedString("settings.subscription", comment: "Subscription"))
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
}
