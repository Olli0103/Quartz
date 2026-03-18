import SwiftUI

/// Sheet/popover that provides AI writing tools (summarize, rewrite, proofread).
/// Uses on-device AppleIntelligenceService.
public struct AIWritingToolsView: View {
    let selectedText: String
    let onApply: @Sendable (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private typealias AIAction = AppleIntelligenceService.AIAction
    private typealias Tone = AppleIntelligenceService.Tone

    @State private var result: String?
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var selectedAction: AppleIntelligenceService.AIAction = .summarize
    @State private var selectedTone: AppleIntelligenceService.Tone = .professional

    private let aiService = AppleIntelligenceService()

    public init(selectedText: String, onApply: @escaping @Sendable (String) -> Void) {
        self.selectedText = selectedText
        self.onApply = onApply
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                actionPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if selectedAction == .rewrite {
                    tonePicker
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                Divider()
                    .padding(.top, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let result {
                            resultSection(result)
                        } else if isProcessing {
                            processingView
                        } else {
                            previewSection
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.callout)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(16)
                }

                Divider()

                bottomBar
            }
            .navigationTitle(String(localized: "Apple Intelligence Writing Tools", bundle: .module))
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
        .frame(minWidth: 420, minHeight: 340)
        #endif
    }

    private var actionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AIAction.allCases, id: \.self) { action in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedAction = action
                            result = nil
                            errorMessage = nil
                        }
                    } label: {
                        Label(action.displayName, systemImage: action.systemImage)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selectedAction == action
                                          ? AnyShapeStyle(QuartzColors.accent.opacity(0.15))
                                          : AnyShapeStyle(.tertiary.opacity(0.15)))
                            )
                            .foregroundStyle(selectedAction == action ? QuartzColors.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tonePicker: some View {
        HStack(spacing: 8) {
            Text(String(localized: "Tone:", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("", selection: $selectedTone) {
                ForEach(Tone.allCases, id: \.self) { tone in
                    Text(tone.displayName).tag(tone)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Selected Text", bundle: .module))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(selectedText.prefix(500) + (selectedText.count > 500 ? "…" : ""))
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
            Text(String(localized: "Processing…", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var bottomBar: some View {
        HStack {
            if result == nil {
                QuartzButton(String(localized: "Process", bundle: .module), icon: "sparkles") {
                    processText()
                }
                .disabled(isProcessing || selectedText.isEmpty)
            } else {
                Button {
                    result = nil
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

    private func processText() {
        isProcessing = true
        errorMessage = nil
        Task {
            do {
                let aiResult = try await aiService.process(
                    action: selectedAction,
                    text: selectedText,
                    tone: selectedTone
                )
                withAnimation {
                    result = aiResult.processedText
                    isProcessing = false
                }
            } catch {
                withAnimation {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}
