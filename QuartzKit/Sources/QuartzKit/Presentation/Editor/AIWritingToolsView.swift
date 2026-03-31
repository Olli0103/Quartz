import SwiftUI

// MARK: - Quick Action Model

/// Predefined inline AI actions displayed as horizontal chips.
private enum InlineAIQuickAction: String, CaseIterable, Identifiable {
    case rewrite = "rewrite"
    case fixGrammar = "fix_grammar"
    case shorter = "shorter"
    case longer = "longer"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rewrite: String(localized: "Rewrite", bundle: .module)
        case .fixGrammar: String(localized: "Fix Grammar", bundle: .module)
        case .shorter: String(localized: "Shorter", bundle: .module)
        case .longer: String(localized: "Longer", bundle: .module)
        }
    }

    var icon: String {
        switch self {
        case .rewrite: "sparkles"
        case .fixGrammar: "wrench"
        case .shorter: "scissors"
        case .longer: "arrow.up.left.and.arrow.down.right"
        }
    }

    var instruction: String {
        switch self {
        case .rewrite: "Rewrite this text to improve clarity and flow while preserving the meaning."
        case .fixGrammar: "Fix all grammar, spelling, and punctuation errors. Return only the corrected text."
        case .shorter: "Make this text more concise while preserving all key information."
        case .longer: "Expand and elaborate on this text with more detail."
        }
    }
}

// MARK: - AI Writing Tools View

/// Popover/sheet for inline AI writing assistance.
///
/// Supports dual-path architecture:
/// - Custom API key → AIProvider
/// - No key → Apple Intelligence (Foundation Models)
/// - Neither → friendly error with Settings link
///
/// Designed for popover presentation from the sparkle toolbar button.
public struct AIWritingToolsView: View {
    let selectedText: String
    let embeddingService: VectorEmbeddingService?
    let currentNoteURL: URL?
    let vaultRootURL: URL?
    let onApply: @Sendable (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private typealias AIAction = OnDeviceWritingToolsService.AIAction
    private typealias Tone = OnDeviceWritingToolsService.Tone
    private typealias AIError = OnDeviceWritingToolsService.AIError

    @State private var result: String?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var isFoundationModelError = false
    @State private var customInstruction: String = ""
    @State private var selectedAction: OnDeviceWritingToolsService.AIAction = .summarize
    @State private var selectedTone: OnDeviceWritingToolsService.Tone = .professional
    @State private var showSettings = false

    /// Legacy mode: when true, shows the original action picker (used from the
    /// existing sheet path). When false, shows the new inline quick-action chips.
    private let useQuickActionLayout: Bool

    private let aiService = OnDeviceWritingToolsService()

    public init(
        selectedText: String,
        embeddingService: VectorEmbeddingService? = nil,
        currentNoteURL: URL? = nil,
        vaultRootURL: URL? = nil,
        onApply: @escaping @Sendable (String) -> Void
    ) {
        self.selectedText = selectedText
        self.embeddingService = embeddingService
        self.currentNoteURL = currentNoteURL
        self.vaultRootURL = vaultRootURL
        self.onApply = onApply
        self.useQuickActionLayout = true
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                quickActionsRow
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                customInstructionField
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                Divider()
                    .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isFoundationModelError {
                            foundationModelErrorView
                        } else if let result {
                            resultSection(result)
                        } else if isProcessing {
                            processingView
                        } else {
                            previewSection
                        }

                        if let errorMessage, !isFoundationModelError {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                                .accessibilityLabel(String(localized: "Error: \(errorMessage)", bundle: .module))
                        }
                    }
                    .padding(16)
                }

                Divider()

                bottomBar
            }
            .quartzLiquidGlass(enabled: true, cornerRadius: 0)
            .navigationTitle(String(localized: "Inline AI", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InlineAIQuickAction.allCases) { action in
                    Button {
                        QuartzFeedback.selection()
                        customInstruction = ""
                        processWithInstruction(action.instruction)
                    } label: {
                        Label(action.label, systemImage: action.icon)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.tertiary.opacity(0.15))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessing || selectedText.isEmpty)
                    .accessibilityLabel(action.label)
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
    }

    // MARK: - Custom Instruction

    private var customInstructionField: some View {
        HStack(spacing: 8) {
            TextField(
                String(localized: "Custom instruction\u{2026}", bundle: .module),
                text: $customInstruction,
                axis: .vertical
            )
            .lineLimit(1...3)
            .textFieldStyle(.plain)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.fill.quaternary)
            )
            .onSubmit {
                guard !customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                processWithInstruction(customInstruction)
            }
            .accessibilityLabel(String(localized: "Custom AI instruction", bundle: .module))
            .accessibilityHint(String(localized: "Type a custom instruction and press Return to send", bundle: .module))

            Button {
                QuartzFeedback.primaryAction()
                processWithInstruction(customInstruction)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.secondary
                            : QuartzColors.accent
                    )
            }
            .buttonStyle(.plain)
            .disabled(customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isProcessing)
            .accessibilityLabel(String(localized: "Send instruction", bundle: .module))
        }
    }

    // MARK: - Content Sections

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Selected Text", bundle: .module))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(selectedText.prefix(500) + (selectedText.count > 500 ? "\u{2026}" : ""))
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.fill.quaternary)
                )
        }
    }

    @ViewBuilder
    private func resultSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Result", bundle: .module))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(text)
                .font(.body)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(QuartzColors.accent.opacity(0.06))
                )
                .textSelection(.enabled)
        }
    }

    private var processingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(String(localized: "Processing\u{2026}", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Processing AI request", bundle: .module))
    }

    // MARK: - Foundation Model Error

    private var foundationModelErrorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)

            Text(String(localized: "AI Unavailable", bundle: .module))
                .font(.headline)

            Text(String(localized: "Apple Intelligence is not available on this device, and no custom AI provider is configured.", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
                // Post notification so the app shell can navigate to settings
                NotificationCenter.default.post(
                    name: .quartzOpenAISettings,
                    object: nil
                )
            } label: {
                Label(String(localized: "Go to AI Settings", bundle: .module), systemImage: "gearshape")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(QuartzColors.accent.gradient)
                    )
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            if result == nil {
                QuartzButton(String(localized: "Process", bundle: .module), icon: "sparkles") {
                    let instruction = customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? InlineAIQuickAction.rewrite.instruction
                        : customInstruction
                    processWithInstruction(instruction)
                }
                .disabled(isProcessing || selectedText.isEmpty)
            } else {
                Button {
                    result = nil
                    isFoundationModelError = false
                    errorMessage = nil
                } label: {
                    Text(String(localized: "Try Again", bundle: .module))
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                QuartzButton(String(localized: "Apply", bundle: .module), icon: "checkmark") {
                    if let result {
                        onApply(result)
                    }
                    dismiss()
                }
            }
        }
        .padding(16)
    }

    // MARK: - Processing

    private func processWithInstruction(_ instruction: String) {
        isProcessing = true
        errorMessage = nil
        isFoundationModelError = false
        result = nil

        Task {
            do {
                let aiResult = try await aiService.invokeInlineAI(
                    instruction: instruction,
                    selectedText: selectedText
                )
                await MainActor.run {
                    withAnimation {
                        result = aiResult
                        isProcessing = false
                    }
                }
            } catch let error as OnDeviceWritingToolsService.AIError {
                await MainActor.run {
                    withAnimation {
                        isProcessing = false
                        switch error {
                        case .foundationModelUnavailable, .noAIProviderConfigured:
                            isFoundationModelError = true
                            errorMessage = error.errorDescription
                        default:
                            errorMessage = error.errorDescription
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation {
                        errorMessage = error.localizedDescription
                        isProcessing = false
                    }
                }
            }
        }
    }
}

// MARK: - Notification Name

public extension Notification.Name {
    /// Posted when the user taps "Go to AI Settings" from the inline AI error state.
    static let quartzOpenAISettings = Notification.Name("quartzOpenAISettings")
}
