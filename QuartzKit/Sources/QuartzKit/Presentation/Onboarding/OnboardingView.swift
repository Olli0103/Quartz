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
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 72
    @ScaledMetric(relativeTo: .largeTitle) private var brandingFontSize: CGFloat = 40
    @ScaledMetric(relativeTo: .title) private var folderIconSize: CGFloat = 56

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
                    .font(.system(size: heroIconSize, weight: .thin))
                    .foregroundStyle(QuartzColors.accentGradient)
                    .symbolEffect(.breathe, options: .repeating)
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

                Text(String(localized: "Pick a folder where Quartz will store your notes.", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            VStack(spacing: 12) {
                QuartzButton(String(localized: "Choose Folder", bundle: .module), icon: "folder") {
                    showFilePicker = true
                }
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.folder],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        guard url.startAccessingSecurityScopedResource() else { return }
                        vaultURL = url
                        currentStep = .chooseTemplate
                        // Do NOT call stopAccessingSecurityScopedResource() here.
                        // The resource must remain accessible for createVault()
                        // which writes template files to this folder.
                    }
                }

                Button(String(localized: "Back", bundle: .module)) {
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
                await MainActor.run {
                    errorMessage = String(localized: "Could not create vault. Please check folder permissions and try again.", bundle: .module)
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
            TimelineView(.animation(minimumInterval: 1.0 / 10.0)) { timeline in
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let t = timeline.date.timeIntervalSinceReferenceDate

                    let colors: [Color] = [
                        QuartzColors.folderYellow.opacity(0.15),
                        QuartzColors.noteBlue.opacity(0.1),
                        QuartzColors.canvasPurple.opacity(0.12),
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
}
