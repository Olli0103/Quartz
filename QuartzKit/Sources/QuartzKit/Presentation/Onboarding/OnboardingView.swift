import SwiftUI

/// First-Start Onboarding: Vault erstellen und optionale Struktur wählen.
///
/// "Second brain in 30 seconds" – minimaler Flow:
/// 1. Welcome Screen
/// 2. Vault-Ordner wählen
/// 3. Struktur wählen (PARA / Zettelkasten / Leer)
/// 4. Fertig
public struct OnboardingView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedTemplate: VaultTemplate = .para
    @State private var vaultURL: URL?
    @State private var isCreating = false

    let onComplete: (VaultConfig) -> Void

    public init(onComplete: @escaping (VaultConfig) -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        Group {
            switch currentStep {
            case .welcome:
                welcomeStep
            case .chooseFolder:
                chooseFolderStep
            case .chooseTemplate:
                chooseTemplateStep
            case .creating:
                creatingStep
            }
        }
        .animation(.easeInOut, value: currentStep)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "square.and.pencil")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("Welcome to Quartz")
                    .font(.largeTitle.bold())
                Text("Your notes. Your files. Your way.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Text("Quartz saves your notes as plain Markdown files – always portable, always yours.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                currentStep = .chooseFolder
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    private var chooseFolderStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("Choose a Vault Folder")
                .font(.title2.bold())

            Text("Pick a folder where Quartz will store your notes.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                // fileImporter wird per sheet geöffnet
            } label: {
                Label("Choose Folder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            .fileImporter(
                isPresented: .constant(true),
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = url.startAccessingSecurityScopedResource()
                    vaultURL = url
                    currentStep = .chooseTemplate
                }
            }

            Button("Back") {
                currentStep = .welcome
            }
            .padding(.bottom, 32)
        }
    }

    private var chooseTemplateStep: some View {
        VStack(spacing: 24) {
            Text("Choose a Structure")
                .font(.title2.bold())
                .padding(.top, 32)

            Text("Start with a proven organization system or start from scratch.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(spacing: 12) {
                templateOption(
                    template: .para,
                    title: "PARA Method",
                    description: "Projects, Areas, Resources, Archive – by Tiago Forte",
                    icon: "square.grid.2x2"
                )

                templateOption(
                    template: .zettelkasten,
                    title: "Zettelkasten",
                    description: "Fleeting, Literature, Permanent Notes – atomic thinking",
                    icon: "brain"
                )

                templateOption(
                    template: .custom,
                    title: "Empty Vault",
                    description: "Start with a blank canvas",
                    icon: "doc"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                currentStep = .creating
                createVault()
            } label: {
                Text("Create Vault")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)

            Button("Back") {
                currentStep = .chooseFolder
            }
            .padding(.bottom, 32)
        }
    }

    private var creatingStep: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Setting up your vault…")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Template Option

    private func templateOption(
        template: VaultTemplate,
        title: String,
        description: String,
        icon: String
    ) -> some View {
        Button {
            selectedTemplate = template
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 44)
                    .foregroundStyle(selectedTemplate == template ? .white : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.bold())
                        .foregroundStyle(selectedTemplate == template ? .white : .primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(selectedTemplate == template ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                if selectedTemplate == template {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedTemplate == template ? Color.accentColor : Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Create Vault

    private func createVault() {
        guard let url = vaultURL else { return }

        Task {
            let templateService = VaultTemplateService()
            try? await templateService.applyTemplate(selectedTemplate, to: url)

            let vault = VaultConfig(
                name: url.lastPathComponent,
                rootURL: url,
                templateStructure: selectedTemplate
            )

            await MainActor.run {
                onComplete(vault)
            }
        }
    }
}

// MARK: - Onboarding Steps

private enum OnboardingStep {
    case welcome
    case chooseFolder
    case chooseTemplate
    case creating
}
