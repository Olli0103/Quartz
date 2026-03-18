import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// First-start onboarding – Liquid Glass design.
///
/// "Second brain in 30 seconds" – minimal flow:
/// 1. Welcome screen with gradient animation
/// 2. Choose vault folder
/// 3. Choose structure (PARA / Zettelkasten / Empty)
/// 4. Done
public struct OnboardingView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedTemplate: VaultTemplate = .para
    @State private var vaultURL: URL?
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var brandingFontSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var folderIconSize: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onComplete: @Sendable (VaultConfig) -> Void

    public init(onComplete: @escaping @Sendable (VaultConfig) -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            // Animated background gradient
            backgroundGradient

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
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .animation(reduceMotion ? .default : QuartzAnimation.onboarding, value: currentStep)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        MeshGradientBackground()
            .ignoresSafeArea()
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // App Icon
                Image(systemName: "square.and.pencil")
                    .font(.system(size: heroIconSize, weight: .thin))
                    .foregroundStyle(QuartzColors.accentGradient)
                    .symbolEffect(.breathe, options: .repeating, isActive: !reduceMotion)
                    .slideUp()

                VStack(spacing: 10) {
                    Text(verbatim: "Quartz")
                        .font(.system(size: brandingFontSize, weight: .bold, design: .rounded))
                        .slideUp(delay: 0.1)

                    Text(String(localized: "Your notes. Your files. Your way.", bundle: .module))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .slideUp(delay: 0.15)
                }

                Text(String(localized: "Beautiful Markdown notes stored as plain files – always portable, always yours.", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .slideUp(delay: 0.2)
            }

            Spacer()

            VStack(spacing: 16) {
                QuartzButton(String(localized: "Get Started", bundle: .module), icon: "arrow.right") {
                    currentStep = .chooseFolder
                }

                Text(String(localized: "No account needed", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .slideUp(delay: 0.3)
        }
    }

    // MARK: - Choose Folder

    @State private var showFilePicker = false

    private var chooseFolderStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: folderIconSize, weight: .thin))
                    .foregroundStyle(QuartzColors.folderYellow)

                Text(String(localized: "Choose a Vault Folder", bundle: .module))
                    .font(.title2.bold())

                Text(String(localized: "Pick a folder where Quartz will store your notes, or create a new one.", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 12) {
                #if os(macOS)
                QuartzButton(String(localized: "Choose Folder", bundle: .module), icon: "folder") {
                    pickFolderMacOS()
                }
                #else
                QuartzButton(String(localized: "Choose Folder", bundle: .module), icon: "folder") {
                    showFilePicker = true
                }
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        if let previous = vaultURL, previous != url {
                            previous.stopAccessingSecurityScopedResource()
                        }
                        guard url.startAccessingSecurityScopedResource() else { return }
                        vaultURL = url
                        currentStep = .chooseTemplate
                    }
                }
                #endif

                Button(String(localized: "Back", bundle: .module)) {
                    currentStep = .welcome
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    #if os(macOS)
    private func pickFolderMacOS() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Vault Folder", bundle: .module)
        panel.message = String(localized: "Choose an existing folder or create a new one for your vault.", bundle: .module)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose", bundle: .module)

        panel.begin { response in
            DispatchQueue.main.async {
                guard response == .OK, let url = panel.url else { return }
                if let previous = vaultURL, previous != url {
                    previous.stopAccessingSecurityScopedResource()
                }
                guard url.startAccessingSecurityScopedResource() else { return }
                vaultURL = url
                currentStep = .chooseTemplate
            }
        }
    }
    #endif

    // MARK: - Choose Template

    private var chooseTemplateStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text(String(localized: "Choose a Structure", bundle: .module))
                    .font(.title2.bold())

                Text(String(localized: "Start with a proven system or a blank canvas.", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 48)

            Spacer()

            VStack(spacing: 10) {
                templateCard(
                    template: .para,
                    title: String(localized: "PARA Method", bundle: .module),
                    description: String(localized: "Projects, Areas, Resources, Archive", bundle: .module),
                    icon: "square.grid.2x2.fill",
                    color: QuartzColors.noteBlue
                )
                .slideUp(delay: 0.1)

                templateCard(
                    template: .zettelkasten,
                    title: String(localized: "Zettelkasten", bundle: .module),
                    description: String(localized: "Fleeting, Literature & Permanent Notes", bundle: .module),
                    icon: "brain.head.profile.fill",
                    color: QuartzColors.canvasPurple
                )
                .slideUp(delay: 0.2)

                templateCard(
                    template: .custom,
                    title: String(localized: "Empty Vault", bundle: .module),
                    description: String(localized: "Start with a blank canvas", bundle: .module),
                    icon: "doc",
                    color: .gray
                )
                .slideUp(delay: 0.3)
            }
            .padding(.horizontal, 24)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                QuartzButton(String(localized: "Create Vault", bundle: .module), icon: "checkmark") {
                    currentStep = .creating
                    createVault()
                }

                Button(String(localized: "Back", bundle: .module)) {
                    currentStep = .chooseFolder
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Creating

    private var creatingStep: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                // Pulsing ring
                Circle()
                    .stroke(QuartzColors.accent.opacity(0.2), lineWidth: 3)
                    .frame(width: 80, height: 80)
                    .scaleEffect(1.3)
                    .pulse()

                Circle()
                    .stroke(QuartzColors.accent.opacity(0.1), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(1.7)
                    .pulse()

                ProgressView()
                    .controlSize(.large)
                    .tint(QuartzColors.accent)
            }
            .bounceIn()

            VStack(spacing: 8) {
                Text(String(localized: "Setting up your vault…", bundle: .module))
                    .font(.title3.weight(.medium))
                    .slideUp(delay: 0.2)

                Text(String(localized: "This will only take a moment.", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .slideUp(delay: 0.3)
            }

            Spacer()
        }
    }

    // MARK: - Template Card

    private func templateCard(
        template: VaultTemplate,
        title: String,
        description: String,
        icon: String,
        color: Color
    ) -> some View {
        let isSelected = selectedTemplate == template

        return Button {
            withAnimation(reduceMotion ? .default : QuartzAnimation.content) {
                selectedTemplate = template
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 40)
                    .foregroundStyle(isSelected ? .white : color)
                    .symbolEffect(.bounce, value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                        .spinIn()
                }
            }
            .padding(16)
            .background {
                let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                if isSelected {
                    shape.fill(color.gradient)
                        .shadow(color: color.opacity(0.35), radius: 12, y: 6)
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
            }
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(QuartzCardButtonStyle())
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
        .accessibilityLabel(title)
        .accessibilityHint(isSelected
            ? String(localized: "Selected", bundle: .module)
            : String(localized: "Double tap to select", bundle: .module))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Create Vault

    private func createVault() {
        guard let url = vaultURL else { return }

        Task {
            let templateService = VaultTemplateService()
            do {
                try await templateService.applyTemplate(selectedTemplate, to: url)
            } catch {
                let detail = error.localizedDescription
                url.stopAccessingSecurityScopedResource()
                await MainActor.run {
                    errorMessage = String(localized: "Could not create vault: \(detail)", bundle: .module)
                    currentStep = .chooseTemplate
                }
                return
            }

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

// MARK: - Steps

private enum OnboardingStep: Equatable {
    case welcome
    case chooseFolder
    case chooseTemplate
    case creating
}

// MARK: - Mesh Gradient Background

private struct MeshGradientBackground: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        if reduceMotion {
            LinearGradient(
                colors: [
                    QuartzColors.folderYellow.opacity(0.15),
                    QuartzColors.noteBlue.opacity(0.1),
                    QuartzColors.canvasPurple.opacity(0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(.background)
        } else {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.5, 0.5], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ], colors: [
                .clear,
                QuartzColors.folderYellow.opacity(0.15),
                .clear,
                QuartzColors.noteBlue.opacity(0.1),
                QuartzColors.canvasPurple.opacity(0.12),
                QuartzColors.noteBlue.opacity(0.1),
                .clear,
                QuartzColors.folderYellow.opacity(0.15),
                .clear
            ])
            .background(.background)
        }
    }
}
