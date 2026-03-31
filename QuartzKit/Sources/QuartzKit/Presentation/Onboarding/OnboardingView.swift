import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Onboarding Steps

private enum OnboardingStep: Equatable {
    case welcome
    case chooseStorageMode
    case chooseTemplate
    case creating
}

/// Storage mode selection during onboarding.
private enum StorageMode: Equatable {
    case quartzICloud
    case customFolder
}

// MARK: - Onboarding View

/// Premium first-launch onboarding — feels like setting up a new Apple device.
///
/// Flow: Welcome → Choose Storage → Choose Template → Creating
///
/// **Storage options** (per Master Plan Section 12):
/// - Quartz iCloud: zero-setup sync via native ubiquity container
/// - Custom Folder: full manual control via file picker
///
/// **Design**: Liquid Glass cards, spring-based `.push` transitions,
/// breathing icon animation, accessibility-first.
public struct OnboardingView: View {
    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedStorageMode: StorageMode = .quartzICloud
    @State private var selectedTemplate: VaultTemplate = .para
    @State private var vaultURL: URL?
    @State private var errorMessage: String?
    @State private var iCloudAvailable: Bool = true
    @State private var showFilePicker = false

    @ScaledMetric(relativeTo: .largeTitle) private var heroIconSize: CGFloat = 80
    @ScaledMetric(relativeTo: .largeTitle) private var brandingFontSize: CGFloat = 42
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let onComplete: @Sendable (VaultConfig) -> Void

    public init(onComplete: @escaping @Sendable (VaultConfig) -> Void) {
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            QuartzAmbientMeshBackground(style: .onboarding)
                .ignoresSafeArea()

            ScrollView {
                VStack {
                    Spacer(minLength: 40)

                    Group {
                        switch currentStep {
                        case .welcome:
                            welcomeStep
                        case .chooseStorageMode:
                            chooseStorageStep
                        case .chooseTemplate:
                            chooseTemplateStep
                        case .creating:
                            creatingStep
                        }
                    }
                    .transition(
                        .asymmetric(
                            insertion: .push(from: .trailing),
                            removal: .push(from: .leading)
                        )
                    )

                    Spacer(minLength: 40)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(reduceMotion ? .default : .spring(response: 0.5, dampingFraction: 0.85), value: currentStep)
        .task { checkICloudAvailability() }
    }

    // MARK: - Welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 60)

            VStack(spacing: 28) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: heroIconSize, weight: .thin))
                    .foregroundStyle(QuartzColors.accentGradient)
                    .symbolEffect(.breathe, options: .repeating, isActive: !reduceMotion)
                    .slideUp()

                VStack(spacing: 12) {
                    Text(verbatim: "Quartz")
                        .font(.system(size: brandingFontSize, weight: .bold, design: .rounded))
                        .slideUp(delay: 0.1)

                    Text(String(localized: "Your notes. Your files. Your way.", bundle: .module))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                        .slideUp(delay: 0.15)
                }

                Text(String(localized: "Beautiful Markdown notes stored as plain files — always portable, always yours.", bundle: .module))
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .slideUp(delay: 0.2)
            }

            Spacer(minLength: 60)

            VStack(spacing: 14) {
                QuartzButton(String(localized: "Get Started", bundle: .module), icon: "arrow.right") {
                    currentStep = .chooseStorageMode
                }

                Text(String(localized: "No account needed", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 32)
            .slideUp(delay: 0.3)

            Spacer(minLength: 48)
        }
    }

    // MARK: - Choose Storage Mode

    private var chooseStorageStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(QuartzColors.noteBlue)
                    .slideUp()

                Text(String(localized: "Where should Quartz store your notes?", bundle: .module))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .slideUp(delay: 0.05)

                Text(String(localized: "You can change this later in Settings.", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .slideUp(delay: 0.1)
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)

            Spacer(minLength: 32)

            VStack(spacing: 12) {
                // Option A: Quartz iCloud
                storageCard(
                    mode: .quartzICloud,
                    icon: "icloud.fill",
                    title: String(localized: "Quartz iCloud", bundle: .module),
                    subtitle: String(localized: "Seamless, zero-setup sync across your Mac, iPad, and iPhone.", bundle: .module),
                    badge: String(localized: "Recommended", bundle: .module),
                    color: QuartzColors.noteBlue,
                    disabled: !iCloudAvailable
                )
                .slideUp(delay: 0.15)

                // Option B: Custom Folder
                storageCard(
                    mode: .customFolder,
                    icon: "folder.fill",
                    title: String(localized: "Custom Folder", bundle: .module),
                    subtitle: String(localized: "Full manual control over your markdown files.", bundle: .module),
                    badge: nil,
                    color: QuartzColors.folderYellow,
                    disabled: false
                )
                .slideUp(delay: 0.25)

                if !iCloudAvailable {
                    Text(String(localized: "iCloud is not available. Sign in to iCloud in System Settings to enable sync.", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 32)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }

            VStack(spacing: 12) {
                QuartzButton(String(localized: "Continue", bundle: .module), icon: "arrow.right") {
                    continueFromStorage()
                }

                Button(String(localized: "Back", bundle: .module)) {
                    QuartzFeedback.selection()
                    currentStep = .welcome
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 48)
        }
        #if !os(macOS)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                vaultURL?.stopAccessingSecurityScopedResource()
                guard url.startAccessingSecurityScopedResource() else { return }
                vaultURL = url
                currentStep = .chooseTemplate
            }
        }
        #endif
    }

    // MARK: - Storage Card

    private func storageCard(
        mode: StorageMode,
        icon: String,
        title: String,
        subtitle: String,
        badge: String?,
        color: Color,
        disabled: Bool
    ) -> some View {
        let isSelected = selectedStorageMode == mode && !disabled

        return Button {
            guard !disabled else { return }
            QuartzFeedback.selection()
            withAnimation(reduceMotion ? .default : QuartzAnimation.content) {
                selectedStorageMode = mode
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 44)
                    .foregroundStyle(isSelected ? .white : color)
                    .symbolEffect(.bounce, value: isSelected)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(isSelected ? .white : .primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(isSelected ? .white.opacity(0.9) : color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(isSelected ? Color.white.opacity(0.2) : color.opacity(0.15))
                                )
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(16)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(color.gradient)
                        .shadow(color: color.opacity(0.35), radius: 12, y: 6)
                }
            }
            .quartzLiquidGlass(enabled: !isSelected, cornerRadius: 16)
            .overlay {
                if !isSelected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                }
            }
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .opacity(disabled ? 0.5 : 1.0)
        }
        .buttonStyle(QuartzCardButtonStyle())
        #if os(iOS)
        .sensoryFeedback(.selection, trigger: isSelected)
        #endif
        .accessibilityLabel(title)
        .accessibilityValue(subtitle)
        .accessibilityHint(disabled
            ? String(localized: "Not available", bundle: .module)
            : isSelected
                ? String(localized: "Selected", bundle: .module)
                : String(localized: "Double tap to select", bundle: .module))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .disabled(disabled)
    }

    // MARK: - Choose Template

    private var chooseTemplateStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 44, weight: .thin))
                    .foregroundStyle(QuartzColors.canvasPurple)
                    .slideUp()

                Text(String(localized: "Choose a Structure", bundle: .module))
                    .font(.title2.bold())
                    .slideUp(delay: 0.05)

                Text(String(localized: "Start with a proven system or a blank canvas.", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .slideUp(delay: 0.1)
            }
            .padding(.top, 32)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                templateCard(
                    template: .para,
                    title: String(localized: "PARA Method", bundle: .module),
                    description: String(localized: "Projects, Areas, Resources, Archive", bundle: .module),
                    icon: "square.grid.2x2.fill",
                    color: QuartzColors.noteBlue
                )
                .slideUp(delay: 0.15)

                templateCard(
                    template: .zettelkasten,
                    title: String(localized: "Zettelkasten", bundle: .module),
                    description: String(localized: "Fleeting, Literature & Permanent Notes", bundle: .module),
                    icon: "brain.head.profile.fill",
                    color: QuartzColors.canvasPurple
                )
                .slideUp(delay: 0.25)

                templateCard(
                    template: .custom,
                    title: String(localized: "Empty Vault", bundle: .module),
                    description: String(localized: "Start with a blank canvas", bundle: .module),
                    icon: "doc",
                    color: .gray
                )
                .slideUp(delay: 0.35)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

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
                    QuartzFeedback.selection()
                    currentStep = .chooseStorageMode
                }
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 48)
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
            QuartzFeedback.selection()
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
                }
            }
            .padding(16)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.gradient)
                        .shadow(color: color.opacity(0.35), radius: 12, y: 6)
                }
            }
            .quartzLiquidGlass(enabled: !isSelected, cornerRadius: 14)
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
        .sensoryFeedback(.selection, trigger: isSelected)
        #endif
        .accessibilityLabel(title)
        .accessibilityValue(description)
        .accessibilityHint(isSelected
            ? String(localized: "Selected", bundle: .module)
            : String(localized: "Double tap to select", bundle: .module))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Creating

    private var creatingStep: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 80)

            ZStack {
                Circle()
                    .stroke(QuartzColors.accent.opacity(0.15), lineWidth: 3)
                    .frame(width: 80, height: 80)
                    .scaleEffect(1.3)
                    .pulse()

                Circle()
                    .stroke(QuartzColors.accent.opacity(0.08), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(1.7)
                    .pulse()

                ProgressView()
                    .controlSize(.large)
                    .tint(QuartzColors.accent)
            }
            .bounceIn()

            VStack(spacing: 8) {
                Text(String(localized: "Setting up your vault\u{2026}", bundle: .module))
                    .font(.title3.weight(.medium))
                    .slideUp(delay: 0.2)

                Text(String(localized: "This will only take a moment.", bundle: .module))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .slideUp(delay: 0.3)
            }

            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Creating your vault", bundle: .module))
    }

    // MARK: - iCloud Availability

    private func checkICloudAvailability() {
        iCloudAvailable = CloudSyncService.isAvailable
        if !iCloudAvailable {
            selectedStorageMode = .customFolder
        }
    }

    // MARK: - Storage Flow

    private func continueFromStorage() {
        errorMessage = nil

        switch selectedStorageMode {
        case .quartzICloud:
            // Resolve the native iCloud ubiquity container
            Task {
                guard let containerURL = await CloudSyncService.resolveContainerURL() else {
                    await MainActor.run {
                        errorMessage = String(localized: "Could not access iCloud Drive. Please check your iCloud settings.", bundle: .module)
                    }
                    return
                }

                // Ensure the Documents directory exists
                let fm = FileManager.default
                if !fm.fileExists(atPath: containerURL.path(percentEncoded: false)) {
                    try? fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
                }

                await MainActor.run {
                    vaultURL = containerURL
                    currentStep = .chooseTemplate
                }
            }

        case .customFolder:
            #if os(macOS)
            pickFolderMacOS()
            #else
            showFilePicker = true
            #endif
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
            Task { @MainActor in
                guard response == .OK, let url = panel.url else { return }
                vaultURL?.stopAccessingSecurityScopedResource()
                guard url.startAccessingSecurityScopedResource() else { return }
                vaultURL = url
                currentStep = .chooseTemplate
            }
        }
    }
    #endif

    // MARK: - Create Vault

    private func createVault() {
        guard let url = vaultURL else {
            errorMessage = String(localized: "No storage location selected.", bundle: .module)
            currentStep = .chooseStorageMode
            return
        }

        let storageType: StorageType = selectedStorageMode == .quartzICloud ? .iCloudDrive : .local

        Task {
            let templateService = VaultTemplateService()
            do {
                try await templateService.applyTemplate(selectedTemplate, to: url)
            } catch {
                let detail = error.localizedDescription
                if storageType == .local {
                    url.stopAccessingSecurityScopedResource()
                }
                await MainActor.run {
                    errorMessage = String(localized: "Could not create vault: \(detail)", bundle: .module)
                    currentStep = .chooseTemplate
                }
                return
            }

            let vault = VaultConfig(
                name: selectedStorageMode == .quartzICloud
                    ? "Quartz Notes"
                    : url.lastPathComponent,
                rootURL: url,
                storageType: storageType,
                templateStructure: selectedTemplate
            )

            await MainActor.run {
                onComplete(vault)
            }
        }
    }
}
