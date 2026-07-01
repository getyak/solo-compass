import SwiftUI

/// Developer / tester tooling, reachable from Settings only after a successful
/// tester-email unlock (`SubscriptionService.developerModeUnlocked`).
///
/// Three jobs:
///   1. **API configuration** — override the baked-in keys (AI provider,
///      Foursquare, OpenWeather, Amap) at runtime so testers can point the app
///      at their own accounts for debugging. Written straight to the same
///      `UserDefaults` keys the `Secrets.resolved*` accessors already prefer
///      over the compiled defaults, so changes take effect without a rebuild.
///   2. **Feature flags** — flip the `FeatureFlags.developerFlags` on/off (or
///      back to default) at runtime to trial not-yet-shipped surfaces.
///   3. **Debug tools** — force an entitlement tier, reset onboarding, clear
///      overrides, and lock the panel back up.
///
/// Nothing here is reachable by a normal user: the entry point in
/// `SettingsView` is gated on `developerModeUnlocked`, which only the
/// allow-listed tester unlock sets.
struct DeveloperOptionsView: View {
    @Environment(UserPreferences.self) private var preferences
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(\.dismiss) private var dismiss

    // Local mirror of the entitlement picker so it reflects immediately.
    @State private var entitlementSelection: SubscriptionService.Entitlement = .free
    // Bump to force the flag rows to re-read their UserDefaults override after
    // "Reset overrides" clears them all at once.
    @State private var flagsRevision = 0
    @State private var showingResetConfirm = false
    @State private var toast: String?

    var body: some View {
        List {
            statusSection
            apiConfigSection
            featureFlagsSection
            debugToolsSection
            lockSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("dev.title", comment: "Developer Options"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { entitlementSelection = subscriptionService.entitlement }
        .alert(
            toast ?? "",
            isPresented: Binding(get: { toast != nil }, set: { if !$0 { toast = nil } })
        ) {
            Button(NSLocalizedString("common.ok", comment: "OK")) { toast = nil }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            infoRow(icon: "hammer", color: .gray,
                    label: NSLocalizedString("dev.status.build", comment: "Build configuration"),
                    value: buildConfiguration)
            infoRow(icon: "number", color: .gray,
                    label: NSLocalizedString("dev.status.version", comment: "App version"),
                    value: appVersion)
            infoRow(icon: "crown", color: .yellow,
                    label: NSLocalizedString("dev.status.entitlement", comment: "Entitlement"),
                    value: subscriptionService.entitlement.rawValue)
            infoRow(icon: "brain", color: .blue,
                    label: NSLocalizedString("dev.status.aiModel", comment: "Resolved AI model"),
                    value: resolvedAIModel)
            infoRow(icon: "icloud", color: .teal,
                    label: NSLocalizedString("dev.status.backendSync", comment: "Backend sync"),
                    value: onOff(FeatureFlags.backendSync))
        } header: {
            header("info.circle", NSLocalizedString("dev.status.header", comment: "Status"))
        } footer: {
            Text(NSLocalizedString("dev.status.footer", comment: "Read-only diagnostics footer"))
        }
    }

    // MARK: - API configuration

    private var apiConfigSection: some View {
        Section {
            NavigationLink {
                AIProviderSettingsView()
                    .environment(preferences)
            } label: {
                iconLabel(icon: "brain.head.profile", color: aiKeyConfigured ? .green : .orange,
                          title: NSLocalizedString("settings.aiProvider", comment: "AI Provider"),
                          subtitle: aiKeyConfigured
                            ? preferences.aiProvider.displayName
                            : NSLocalizedString("dev.api.notSet", comment: "Not set"))
            }

            APIKeyOverrideField(
                defaultsKey: Secrets.RuntimeKeys.foursquareApiKey,
                icon: "mappin.and.ellipse", color: .pink,
                title: NSLocalizedString("dev.api.foursquare", comment: "Foursquare API key"))
            APIKeyOverrideField(
                defaultsKey: Secrets.RuntimeKeys.openWeatherApiKey,
                icon: "cloud.sun", color: .cyan,
                title: NSLocalizedString("dev.api.openWeather", comment: "OpenWeather API key"))
            APIKeyOverrideField(
                defaultsKey: Secrets.RuntimeKeys.amapApiKey,
                icon: "map", color: .green,
                title: NSLocalizedString("dev.api.amap", comment: "Amap API key"))
        } header: {
            header("key.fill", NSLocalizedString("dev.api.header", comment: "API configuration"))
        } footer: {
            Text(NSLocalizedString("dev.api.footer", comment: "API override footer"))
        }
    }

    // MARK: - Feature flags

    private var featureFlagsSection: some View {
        Section {
            ForEach(FeatureFlags.developerFlags) { flag in
                FeatureFlagRow(flag: flag)
                    .id("\(flag.key)-\(flagsRevision)")
            }
        } header: {
            header("flag", NSLocalizedString("dev.flags.header", comment: "Feature flags"))
        } footer: {
            Text(NSLocalizedString("dev.flags.footer", comment: "Feature flags footer"))
        }
    }

    // MARK: - Debug tools

    private var debugToolsSection: some View {
        Section {
            Picker(
                NSLocalizedString("dev.tools.entitlement", comment: "Force entitlement"),
                selection: $entitlementSelection
            ) {
                ForEach(SubscriptionService.Entitlement.allCases, id: \.self) { tier in
                    Text(tier.rawValue).tag(tier)
                }
            }
            .onChange(of: entitlementSelection) { _, newValue in
                subscriptionService._setEntitlementForTesting(newValue)
                Haptics.selection()
            }

            Button {
                preferences.hasCompletedOnboarding = false
                Haptics.notify(.success)
                toast = NSLocalizedString("dev.tools.resetOnboarding.done", comment: "Onboarding reset toast")
            } label: {
                iconLabel(icon: "arrow.counterclockwise", color: .orange,
                          title: NSLocalizedString("dev.tools.resetOnboarding", comment: "Reset onboarding"),
                          subtitle: nil)
            }
            .foregroundStyle(.primary)

            Button(role: .destructive) {
                showingResetConfirm = true
            } label: {
                iconLabel(icon: "trash", color: .red,
                          title: NSLocalizedString("dev.tools.resetOverrides", comment: "Reset overrides"),
                          subtitle: nil)
            }
            .confirmationDialog(
                NSLocalizedString("dev.tools.resetOverrides.confirm", comment: "Reset overrides confirm"),
                isPresented: $showingResetConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("dev.tools.resetOverrides", comment: "Reset overrides"), role: .destructive) {
                    FeatureFlags.clearAllOverrides()
                    flagsRevision += 1
                    Haptics.notify(.success)
                    toast = NSLocalizedString("dev.tools.resetOverrides.done", comment: "Overrides reset toast")
                }
                Button(NSLocalizedString("common.cancel", comment: "Cancel"), role: .cancel) {}
            }
        } header: {
            header("wrench.and.screwdriver", NSLocalizedString("dev.tools.header", comment: "Debug tools"))
        }
    }

    // MARK: - Lock

    private var lockSection: some View {
        Section {
            Button(role: .destructive) {
                subscriptionService.lockDeveloperMode()
                Haptics.impact(.medium)
                // Pop back to Settings; the entry row is now gone (the flag is
                // observed) so there's nothing to return to here.
                dismiss()
            } label: {
                iconLabel(icon: "lock", color: .secondary,
                          title: NSLocalizedString("dev.lock", comment: "Lock developer options"),
                          subtitle: nil)
            }
        } footer: {
            Text(NSLocalizedString("dev.lock.footer", comment: "Lock footer"))
        }
    }

    // MARK: - Derived values

    private var buildConfiguration: String {
        #if DEBUG
        return "DEBUG"
        #else
        return "RELEASE"
        #endif
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var resolvedAIModel: String {
        preferences.aiModelName.isEmpty ? preferences.aiProvider.defaultModel : preferences.aiModelName
    }

    private var aiKeyConfigured: Bool { !preferences.aiApiKey.isEmpty }

    private func onOff(_ value: Bool) -> String {
        value
            ? NSLocalizedString("dev.value.on", comment: "On")
            : NSLocalizedString("dev.value.off", comment: "Off")
    }

    // MARK: - Row builders

    private func header(_ symbol: String, _ label: String) -> some View {
        Label(label, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    private func infoRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 7))
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.callout)
                .monospaced()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func iconLabel(icon: String, color: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(color, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - APIKeyOverrideField

/// A SecureField bound to a `UserDefaults` string key, with a trailing clear
/// button that removes the override so the compiled-in default resumes. Used
/// for the Foursquare / OpenWeather / Amap runtime key overrides.
private struct APIKeyOverrideField: View {
    let defaultsKey: String
    let icon: String
    let color: Color
    let title: String

    @State private var value: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color, in: RoundedRectangle(cornerRadius: 7))
                Text(title).font(.body)
                Spacer()
                if !value.isEmpty {
                    Button {
                        value = ""
                        UserDefaults.standard.removeObject(forKey: defaultsKey)
                        Haptics.selection()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("dev.api.clear", comment: "Clear override"))
                }
            }
            SecureField(
                NSLocalizedString("dev.api.placeholder", comment: "Paste key placeholder"),
                text: $value
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .monospaced()
            .font(.callout)
            .onChange(of: value) { _, newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    UserDefaults.standard.removeObject(forKey: defaultsKey)
                } else {
                    UserDefaults.standard.set(trimmed, forKey: defaultsKey)
                }
            }
        }
        .onAppear {
            value = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        }
    }
}

// MARK: - FeatureFlagRow

/// Tri-state control for one developer flag: Default / On / Off. "Default"
/// clears the override so the flag falls back to its plist/compiled value.
private struct FeatureFlagRow: View {
    let flag: FeatureFlags.DeveloperFlag

    private enum State3: Hashable { case defaultValue, on, off }

    @State private var selection: State3 = .defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString(flag.titleKey, comment: "Feature flag title"))
                    .font(.body)
                Text(NSLocalizedString(flag.subtitleKey, comment: "Feature flag subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("", selection: $selection) {
                Text(defaultLabel).tag(State3.defaultValue)
                Text(NSLocalizedString("dev.value.on", comment: "On")).tag(State3.on)
                Text(NSLocalizedString("dev.value.off", comment: "Off")).tag(State3.off)
            }
            .pickerStyle(.segmented)
            .onChange(of: selection) { _, newValue in
                switch newValue {
                case .defaultValue: FeatureFlags.setOverride(nil, for: flag.key)
                case .on: FeatureFlags.setOverride(true, for: flag.key)
                case .off: FeatureFlags.setOverride(false, for: flag.key)
                }
                Haptics.selection()
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            switch FeatureFlags.override(for: flag.key) {
            case .some(true): selection = .on
            case .some(false): selection = .off
            case .none: selection = .defaultValue
            }
        }
    }

    /// "Default (On)" / "Default (Off)" so the tester can see what falling back
    /// to the compiled default actually means for this flag.
    private var defaultLabel: String {
        let base = NSLocalizedString("dev.value.default", comment: "Default")
        let hint = flag.defaultValue
            ? NSLocalizedString("dev.value.on", comment: "On")
            : NSLocalizedString("dev.value.off", comment: "Off")
        return "\(base) (\(hint))"
    }
}

#Preview {
    NavigationStack {
        DeveloperOptionsView()
            .environment(UserPreferences())
            .environment(SubscriptionService())
    }
}
