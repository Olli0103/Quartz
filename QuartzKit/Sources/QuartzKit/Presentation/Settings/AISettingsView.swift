import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Keys for app-wide settings.
private enum AppSettingsKeys {
    static let semanticAutoLinkingEnabled = "semanticAutoLinkingEnabled"
    static let iCloudSyncEnabled = "iCloudSyncEnabled"
}

/// AI provider configuration: select providers, enter API keys, pick models.
public struct AISettingsView: View {
    @State private var registry = AIProviderRegistry.shared
    @State private var apiKeyInputs: [String: String] = [:]
    @State private var savingKey: String?
    @State private var savedProviders: Set<String> = []
    @State private var keySaveResult: [String: Bool] = [:]
    @State private var customModelInput = ""
    @State private var customModels: [AIModel] = []
    @State private var ollamaURL: String = ""
    @State private var ollamaConnected: Bool?
    @State private var ollamaChecking = false
    @State private var ollamaModels: [AIModel] = []
    @State private var ollamaModelsFetched = false
    @State private var connectionTestResult: Bool?
    @State private var connectionTesting = false
    @AppStorage(AppSettingsKeys.semanticAutoLinkingEnabled) private var semanticAutoLinkingEnabled = true
    @AppStorage(AppSettingsKeys.iCloudSyncEnabled) private var iCloudSyncEnabled = true

    public init() {}

    public var body: some View {
        Form {
            providerSection
            apiKeysSection

            if registry.selectedProviderID == "ollama" {
                ollamaEndpointSection
                if ollamaConnected == true {
                    ollamaModelSection
                }
            }

            modelSection
            connectionTestSection
            customModelSection
            semanticAutoLinkingSection
            iCloudSyncSection
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "AI", bundle: .module))
        .task {
            await loadCustomModels()
            loadOllamaURLFromStorage()
        }
        .onChange(of: registry.selectedProviderID) { _, newValue in
            connectionTestResult = nil
            if newValue == "ollama" {
                loadOllamaURLFromStorage()
            }
            Task { await loadCustomModels() }
        }
    }

    // MARK: - Provider Section

    private var providerSection: some View {
        Section {
            Picker(selection: $registry.selectedProviderID) {
                ForEach(registry.providers, id: \.id) { provider in
                    HStack {
                        Text(provider.displayName)
                        if provider.isConfigured {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }
                    .tag(provider.id)
                }
            } label: {
                Label(String(localized: "Active Provider", bundle: .module), systemImage: "cpu")
            }
        } header: {
            Text(String(localized: "Provider", bundle: .module))
        } footer: {
            Text(String(localized: "Select the AI provider for chat and writing tools.", bundle: .module))
        }
    }

    // MARK: - API Keys Section

    private var apiKeysSection: some View {
        Section {
            ForEach(registry.providers, id: \.id) { provider in
                if provider.id == "ollama" {
                    LabeledContent {
                        Text(String(localized: "Local", bundle: .module))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    } label: {
                        Label(provider.displayName, systemImage: "desktopcomputer")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(provider.displayName)
                                .font(.body.weight(.medium))
                            Spacer()
                            if provider.isConfigured || savedProviders.contains(provider.id) {
                                Label(String(localized: "Configured", bundle: .module), systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }

                        HStack(spacing: 8) {
                            SecureField(
                                String(localized: "sk-...", bundle: .module),
                                text: Binding(
                                    get: { apiKeyInputs[provider.id] ?? "" },
                                    set: { apiKeyInputs[provider.id] = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textContentType(.password)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            #endif

                            Button {
                                saveKey(for: provider)
                            } label: {
                                HStack(spacing: 6) {
                                    if savingKey == provider.id {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else if let result = keySaveResult[provider.id] {
                                        Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundStyle(result ? .green : .red)
                                            .symbolEffect(.bounce, value: result)
                                    }
                                    Text(String(localized: "Save", bundle: .module))
                                }
                            }
                            .disabled((apiKeyInputs[provider.id] ?? "").isEmpty || savingKey == provider.id)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text(String(localized: "API Keys", bundle: .module))
        } footer: {
            Text(String(localized: "Keys are stored in the system Keychain.", bundle: .module))
        }
    }

    // MARK: - Ollama Endpoint Section

    private var ollamaEndpointSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(
                    "http://localhost:11434",
                    text: $ollamaURL
                )
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif

                Button(String(localized: "Save", bundle: .module)) {
                    let trimmed = ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let url = URL(string: trimmed) {
                        OllamaProvider.setBaseURL(url)
                        ollamaURL = url.absoluteString
                        ollamaConnected = nil
                        ollamaModels = []
                        ollamaModelsFetched = false
                    }
                }
                .disabled(ollamaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

        } header: {
            Text(String(localized: "Ollama Endpoint", bundle: .module))
        } footer: {
            Text(String(localized: "The base URL of your Ollama server. Default is http://localhost:11434.", bundle: .module))
        }
    }

    private var ollamaModelSection: some View {
        Section {
            if ollamaModelsFetched && ollamaModels.isEmpty {
                Text(String(localized: "No models found. Pull models with `ollama pull <model>`.", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ollamaModels) { model in
                    Button {
                        registry.selectedModelID = model.id
                    } label: {
                        HStack {
                            Text(model.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer()
                            if registry.selectedModelID == model.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(QuartzColors.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            Text(String(localized: "Ollama Models", bundle: .module))
        } footer: {
            Text(String(localized: "Models detected on your Ollama server. Test connection to refresh.", bundle: .module))
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        Section {
            if let selected = registry.selectedProvider {
                let allModels = selected.availableModels + customModels
                ForEach(allModels) { model in
                    Button {
                        registry.selectedModelID = model.id
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(String(localized: "\(model.contextWindow / 1000)K context window", bundle: .module))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if isModelSelected(model, allModels: allModels) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(QuartzColors.accent)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if customModels.contains(where: { $0.id == model.id }) {
                            Button(role: .destructive) {
                                Task {
                                    await registry.removeCustomModel(id: model.id, forProvider: registry.selectedProviderID)
                                    await loadCustomModels()
                                }
                            } label: {
                                Label(String(localized: "Remove Custom Model", bundle: .module), systemImage: "trash")
                            }
                        }
                    }
                }
            } else {
                Text(String(localized: "Select a provider above to see available models.", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(String(localized: "Model", bundle: .module))
        }
    }

    // MARK: - Connection Test Section

    private var connectionTestSection: some View {
        Section {
            HStack(spacing: 12) {
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 6) {
                        if connectionTesting || (registry.selectedProviderID == "ollama" && ollamaChecking) {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(String(localized: "Test Connection", bundle: .module))
                    }
                }
                .disabled(connectionTesting || (registry.selectedProviderID == "ollama" && ollamaChecking))

                Spacer()

                if registry.selectedProviderID == "ollama", let connected = ollamaConnected {
                    Label(
                        connected
                            ? String(localized: "Connected", bundle: .module)
                            : String(localized: "Not Reachable", bundle: .module),
                        systemImage: connected ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(connected ? .green : .red)
                } else if let result = connectionTestResult {
                    Label(
                        result
                            ? String(localized: "Connected", bundle: .module)
                            : String(localized: "Not Reachable", bundle: .module),
                        systemImage: result ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(result ? .green : .red)
                }
            }
        } header: {
            Text(String(localized: "Connection", bundle: .module))
        } footer: {
            Text(String(localized: "Verify your API key and network connectivity.", bundle: .module))
        }
    }

    // MARK: - Custom Model Section

    private var customModelSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField(
                    String(localized: "e.g. anthropic/claude-sonnet-4", bundle: .module),
                    text: $customModelInput
                )
                .textFieldStyle(.roundedBorder)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif

                Button(String(localized: "Add", bundle: .module)) {
                    addCustomModel()
                }
                .disabled(customModelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text(String(localized: "Custom Model", bundle: .module))
        } footer: {
            Text(String(localized: "Enter any model ID supported by the selected provider. Useful for OpenRouter, Ollama, or newly released models.", bundle: .module))
        }
    }

    // MARK: - Helpers

    private func isModelSelected(_ model: AIModel, allModels: [AIModel]) -> Bool {
        if let selectedID = registry.selectedModelID {
            return model.id == selectedID
        }
        return model.id == allModels.first?.id
    }

    private func loadCustomModels() async {
        customModels = await registry.customModels(for: registry.selectedProviderID)
    }

    private func loadOllamaURLFromStorage() {
        ollamaURL = OllamaProvider.getStoredBaseURLString()
    }

    private func addCustomModel() {
        let modelID = customModelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else { return }
        let providerID = registry.selectedProviderID
        customModelInput = ""
        Task {
            await registry.addCustomModel(
                id: modelID,
                name: modelID,
                contextWindow: 128_000,
                forProvider: providerID
            )
            await loadCustomModels()
            registry.selectedModelID = modelID
        }
    }

    private func testConnection() {
        connectionTestResult = nil
        if registry.selectedProviderID == "ollama" {
            testOllamaConnection()
            return
        }
        connectionTesting = true
        Task {
            let provider = registry.providers.first(where: { $0.id == registry.selectedProviderID })
            let connected = await provider?.checkConnection() ?? false
            await MainActor.run {
                withAnimation {
                    connectionTestResult = connected
                    connectionTesting = false
                }
            }
        }
    }

    private func testOllamaConnection() {
        guard let ollama = registry.providers.first(where: { $0.id == "ollama" }) as? OllamaProvider else { return }
        ollamaChecking = true
        ollamaConnected = nil
        ollamaModels = []
        ollamaModelsFetched = false
        Task {
            let connected = await ollama.checkConnection()
            await MainActor.run {
                withAnimation {
                    ollamaConnected = connected
                    ollamaChecking = false
                }
            }
            if connected {
                do {
                    let models = try await ollama.fetchAvailableModels()
                    await MainActor.run {
                        withAnimation {
                            ollamaModels = models
                            ollamaModelsFetched = true
                        }
                    }
                } catch {
                    await MainActor.run {
                        withAnimation {
                            ollamaModelsFetched = true
                        }
                    }
                }
            }
        }
    }

    private func saveKey(for provider: any AIProvider) {
        guard let key = apiKeyInputs[provider.id], !key.isEmpty else { return }
        let providerID = provider.id
        savingKey = providerID
        keySaveResult[providerID] = nil
        Task {
            do {
                try await KeychainHelper.shared.saveKey(key, for: providerID)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        savedProviders.insert(providerID)
                        apiKeyInputs[providerID] = ""
                        savingKey = nil
                        keySaveResult[providerID] = true
                    }
                    #if os(iOS)
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    #endif
                }
            } catch {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        savingKey = nil
                        keySaveResult[providerID] = false
                    }
                    #if os(iOS)
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                    #endif
                }
            }
        }
    }

    // MARK: - Semantic Auto-Linking Section

    private var semanticAutoLinkingSection: some View {
        Section {
            Toggle(isOn: $semanticAutoLinkingEnabled) {
                Label(String(localized: "Semantic Auto-Linking", bundle: .module), systemImage: "cpu")
            }
            .tint(QuartzColors.accent)
        } header: {
            Text(String(localized: "Knowledge Graph", bundle: .module))
        } footer: {
            Text(String(localized: "When enabled, the graph view uses AI-powered embeddings to show dashed connections between semantically related notes.", bundle: .module))
        }
    }

    // MARK: - iCloud Sync Section

    private var iCloudSyncSection: some View {
        Section {
            Toggle(isOn: $iCloudSyncEnabled) {
                Label(String(localized: "iCloud Sync", bundle: .module), systemImage: "icloud")
            }
            .tint(QuartzColors.accent)
        } header: {
            Text(String(localized: "Sync", bundle: .module))
        } footer: {
            Text(String(localized: "When enabled, Quartz monitors iCloud Drive vaults for sync status and conflicts. Disable when using local-only vaults.", bundle: .module))
        }
    }
}
