import SwiftUI

/// First-Start Onboarding – Liquid Glass Design.
///
/// "Second brain in 30 seconds" – minimaler Flow:
/// 1. Welcome Screen mit Gradient-Animation
/// 2. Vault-Ordner wählen
/// 3. Struktur wählen (PARA / Zettelkasten / Leer)
/// 4. Fertig
public struct OnboardingView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedTemplate: VaultTemplate = .para
    @State private var vaultURL: URL?

    let onComplete: (VaultConfig) -> Void

    public init(onComplete: @escaping (VaultConfig) -> Void) {
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
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentStep)
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
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(QuartzColors.accentGradient)
                    .symbolEffect(.breathe, options: .repeating)
                    .slideUp()

                VStack(spacing: 10) {
                    Text(verbatim: "Quartz")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .slideUp(delay: 0.1)

                    Text(String(localized: "Your notes. Your files. Your way."))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .slideUp(delay: 0.15)
                }

                Text(String(localized: "Beautiful Markdown notes stored as plain files – always portable, always yours."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .slideUp(delay: 0.2)
            }

            Spacer()

            VStack(spacing: 16) {
                QuartzButton(String(localized: "Get Started"), icon: "arrow.right") {
                    currentStep = .chooseFolder
                }

                Text(String(localized: "No account needed"))
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
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(QuartzColors.folderYellow)

                Text(String(localized: "Choose a Vault Folder"))
                    .font(.title2.bold())

                Text(String(localized: "Pick a folder where Quartz will store your notes."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 12) {
                QuartzButton(String(localized: "Choose Folder"), icon: "folder") {
                    showFilePicker = true
                }
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        _ = url.startAccessingSecurityScopedResource()
                        vaultURL = url
                        currentStep = .chooseTemplate
                    }
                }

                Button(String(localized: "Back")) {
                    currentStep = .welcome
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: - Choose Template

    private var chooseTemplateStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text(String(localized: "Choose a Structure"))
                    .font(.title2.bold())

                Text(String(localized: "Start with a proven system or a blank canvas."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 48)

            Spacer()

            VStack(spacing: 10) {
                templateCard(
                    template: .para,
                    title: "PARA Method",
                    description: "Projects, Areas, Resources, Archive",
                    icon: "square.grid.2x2.fill",
                    color: QuartzColors.noteBlue
                )
                .slideUp(delay: 0.1)

                templateCard(
                    template: .zettelkasten,
                    title: "Zettelkasten",
                    description: "Fleeting, Literature & Permanent Notes",
                    icon: "brain.head.profile.fill",
                    color: QuartzColors.canvasPurple
                )
                .slideUp(delay: 0.2)

                templateCard(
                    template: .custom,
                    title: "Empty Vault",
                    description: "Start with a blank canvas",
                    icon: "doc",
                    color: .gray
                )
                .slideUp(delay: 0.3)
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                QuartzButton(String(localized: "Create Vault"), icon: "checkmark") {
                    currentStep = .creating
                    createVault()
                }

                Button(String(localized: "Back")) {
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
                    .stroke(Color(hex: 0xF2994A).opacity(0.2), lineWidth: 3)
                    .frame(width: 80, height: 80)
                    .scaleEffect(1.3)
                    .pulse()

                Circle()
                    .stroke(Color(hex: 0xF2994A).opacity(0.1), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(1.7)
                    .pulse()

                ProgressView()
                    .controlSize(.large)
                    .tint(Color(hex: 0xF2994A))
            }
            .bounceIn()

            VStack(spacing: 8) {
                Text(String(localized: "Setting up your vault…"))
                    .font(.title3.weight(.medium))
                    .slideUp(delay: 0.2)

                Text(String(localized: "This will only take a moment."))
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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
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
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? color.gradient : AnyShapeStyle(.regularMaterial))
                    .shadow(color: isSelected ? color.opacity(0.35) : .clear, radius: isSelected ? 12 : 0, y: isSelected ? 6 : 0)
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
    }

    // MARK: - Create Vault

    private func createVault() {
        guard let url = vaultURL else { return }

        Task {
            let templateService = VaultTemplateService()
            do {
                try await templateService.applyTemplate(selectedTemplate, to: url)
            } catch {
                await MainActor.run {
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
    @State private var phase: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let t = timeline.date.timeIntervalSinceReferenceDate

                // Soft gradient circles
                let colors: [Color] = [
                    Color(hex: 0xFDCB6E).opacity(0.15),
                    Color(hex: 0x74B9FF).opacity(0.1),
                    Color(hex: 0xA29BFE).opacity(0.12),
                ]

                for (i, color) in colors.enumerated() {
                    let offset = Double(i) * 2.1
                    let x = w * (0.3 + 0.4 * sin(t * 0.3 + offset))
                    let y = h * (0.3 + 0.4 * cos(t * 0.2 + offset))
                    let radius = min(w, h) * 0.4

                    let rect = CGRect(
                        x: x - radius,
                        y: y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )

                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(color)
                    )
                }
            }
        }
        .blur(radius: 60)
        .background(.background)
    }
}
