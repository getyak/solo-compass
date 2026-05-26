import SwiftUI

/// In-app AI provider configuration screen.
///
/// Writes directly to `UserDefaults` via `UserPreferences` so that
/// `Secrets.resolvedDeepSeekApiKey`, `resolvedBaseURL`, and `resolvedModel`
/// pick up the values immediately without a restart.
struct AIProviderSettingsView: View {
    @Environment(UserPreferences.self) private var preferences

    var body: some View {
        List {
            providerSection
            apiKeySection
            if preferences.aiProvider == .custom {
                baseURLSection
            }
            modelSection
            statusSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(NSLocalizedString("ai.provider.settings.title", comment: "AI Provider"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: preferences.aiProvider) { _, newProvider in
            autoFillDefaults(for: newProvider)
        }
    }

    // MARK: - Sections

    private var providerSection: some View {
        Section {
            ForEach(AIProvider.allCases) { provider in
                HStack(spacing: 12) {
                    Image(systemName: provider.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(iconColor(for: provider), in: RoundedRectangle(cornerRadius: 7))
                    Text(provider.displayName)
                    Spacer()
                    if preferences.aiProvider == provider {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                            .fontWeight(.semibold)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { preferences.aiProvider = provider }
            }
        } header: {
            Label(
                NSLocalizedString("ai.provider.section.provider", comment: "AI Provider section header"),
                systemImage: "brain"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        } footer: {
            Text(providerDescription)
        }
    }

    private var apiKeySection: some View {
        Section {
            @Bindable var prefs = preferences
            SecureField(
                NSLocalizedString("ai.provider.apiKey.placeholder", comment: "API Key placeholder"),
                text: $prefs.aiApiKey
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .monospaced()
        } header: {
            Label(
                NSLocalizedString("ai.provider.section.apiKey", comment: "API Key section header"),
                systemImage: "key.fill"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        } footer: {
            Text(NSLocalizedString("ai.provider.apiKey.footer", comment: "API key footer — stored locally, never shared"))
        }
    }

    private var baseURLSection: some View {
        Section {
            @Bindable var prefs = preferences
            TextField(
                NSLocalizedString("ai.provider.baseURL.placeholder", comment: "Base URL placeholder"),
                text: $prefs.aiBaseURL
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        } header: {
            Label(
                NSLocalizedString("ai.provider.section.baseURL", comment: "Base URL section header"),
                systemImage: "link"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        } footer: {
            Text(NSLocalizedString("ai.provider.baseURL.footer", comment: "Base URL footer e.g. https://api.openai.com/v1"))
        }
    }

    private var modelSection: some View {
        Section {
            @Bindable var prefs = preferences
            TextField(
                preferences.aiProvider.defaultModel.isEmpty
                    ? NSLocalizedString("ai.provider.model.placeholder.custom", comment: "Model name placeholder for custom")
                    : preferences.aiProvider.defaultModel,
                text: $prefs.aiModelName
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        } header: {
            Label(
                NSLocalizedString("ai.provider.section.model", comment: "Model section header"),
                systemImage: "cpu"
            )
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        } footer: {
            Text(defaultModelHint)
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.system(size: 16, weight: .medium))
                Text(statusText)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Computed helpers

    private var isConfigured: Bool {
        !preferences.aiApiKey.isEmpty
    }

    private var statusIcon: String {
        isConfigured ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
    }

    private var statusColor: Color {
        isConfigured ? .green : .orange
    }

    private var statusText: String {
        isConfigured
            ? String(
                format: NSLocalizedString("ai.provider.status.configured", comment: "Status: configured with provider"),
                preferences.aiProvider.displayName
              )
            : NSLocalizedString("ai.provider.status.unconfigured", comment: "Status: no API key")
    }

    private var providerDescription: String {
        switch preferences.aiProvider {
        case .deepseek:
            return NSLocalizedString("ai.provider.deepseek.description", comment: "DeepSeek provider description")
        case .openai:
            return NSLocalizedString("ai.provider.openai.description", comment: "OpenAI provider description")
        case .custom:
            return NSLocalizedString("ai.provider.custom.description", comment: "Custom provider description")
        }
    }

    private var defaultModelHint: String {
        switch preferences.aiProvider {
        case .deepseek:
            return String(
                format: NSLocalizedString("ai.provider.model.hint", comment: "Default model hint"),
                AIProvider.deepseek.defaultModel
            )
        case .openai:
            return String(
                format: NSLocalizedString("ai.provider.model.hint", comment: "Default model hint"),
                AIProvider.openai.defaultModel
            )
        case .custom:
            return NSLocalizedString("ai.provider.model.hint.custom", comment: "Custom model hint")
        }
    }

    // MARK: - Auto-fill

    private func autoFillDefaults(for provider: AIProvider) {
        // Only auto-fill base URL if it's empty or was a known provider default.
        let knownDefaults = AIProvider.allCases.map(\.defaultBaseURL).filter { !$0.isEmpty }
        let currentURL = preferences.aiBaseURL
        if currentURL.isEmpty || knownDefaults.contains(currentURL) {
            preferences.aiBaseURL = provider.defaultBaseURL
        }
        // Auto-fill model if empty or was a known provider default.
        let knownModels = AIProvider.allCases.map(\.defaultModel).filter { !$0.isEmpty }
        let currentModel = preferences.aiModelName
        if currentModel.isEmpty || knownModels.contains(currentModel) {
            preferences.aiModelName = provider.defaultModel
        }
    }

    private func iconColor(for provider: AIProvider) -> Color {
        switch provider {
        case .deepseek: return .blue
        case .openai: return .green
        case .custom: return .purple
        }
    }
}

#Preview {
    NavigationStack {
        AIProviderSettingsView()
            .environment(UserPreferences())
    }
}
