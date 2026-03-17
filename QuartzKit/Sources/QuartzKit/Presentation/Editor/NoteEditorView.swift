import SwiftUI

/// WYSIWYG Markdown-Editor – clean, minimal, Apple-Notes-inspiriert.
/// Liquid Glass Statusbar + Formatting Toolbar.
public struct NoteEditorView: View {
    @Bindable var viewModel: NoteEditorViewModel
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.focusModeManager) private var focusMode
    @Environment(\.featureGate) private var featureGate
    @State private var showFocusModeHint = false
    private let formatter = MarkdownFormatter()

    public init(viewModel: NoteEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Formatting Toolbar
            formattingBar
                .hidesInFocusMode()

            // Frontmatter (collapsible)
            if viewModel.note != nil {
                FrontmatterEditorView(
                    frontmatter: Binding(
                        get: { viewModel.note?.frontmatter ?? Frontmatter() },
                        set: { viewModel.updateFrontmatter($0) }
                    )
                )
                .hidesInFocusMode()
            }

            // Editor
            MarkdownTextViewRepresentable(
                text: $viewModel.content,
                editorFontScale: appearance.editorFontScale
            )

            // Status Bar
            statusBar
                .hidesInFocusMode()
        }
        .sensoryFeedback(.success, trigger: viewModel.manualSaveCompleted)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: focusMode.isFocusModeActive)
        .navigationTitle(viewModel.note?.displayName ?? String(localized: "Note", bundle: .module))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                editorToolbar
            }
        }
        .onTapGesture(count: 3) {
            if focusMode.isFocusModeActive {
                focusMode.toggleFocusMode()
            }
        }
        .accessibilityAction(named: String(localized: "Exit focus mode", bundle: .module)) {
            if focusMode.isFocusModeActive {
                focusMode.toggleFocusMode()
            }
        }
        .overlay(alignment: .bottom) {
            if showFocusModeHint {
                Text(String(localized: "Triple-tap to exit focus mode", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: focusMode.isFocusModeActive) { _, isActive in
            if isActive {
                withAnimation(QuartzAnimation.smooth) { showFocusModeHint = true }
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(QuartzAnimation.smooth) { showFocusModeHint = false }
                }
            } else {
                showFocusModeHint = false
            }
        }
    }

    // MARK: - Formatting Bar

    private var formattingBar: some View {
        FormattingToolbar { action in
            let cursorPosition = viewModel.cursorPosition
            let (newText, newSelection) = formatter.apply(
                action,
                to: viewModel.content,
                selectedRange: cursorPosition
            )
            viewModel.content = newText
            viewModel.cursorPosition = newSelection
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                    .scaleEffect(viewModel.isSaving ? 1.3 : 1.0)
                    .shadow(color: statusColor.opacity(viewModel.isSaving ? 0.6 : 0), radius: 4)
                    .animation(
                        viewModel.isSaving
                            ? QuartzAnimation.savePulse.repeatForever(autoreverses: true)
                            : QuartzAnimation.standard,
                        value: viewModel.isSaving
                    )

                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .animation(QuartzAnimation.standard, value: statusText)

            Spacer()

            Text(String(localized: "^[\(viewModel.wordCount) word](inflect: true)", bundle: .module,
                        comment: "Word count in editor status bar. Uses automatic grammar agreement."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var statusColor: Color {
        if viewModel.isSaving { return .orange }
        if viewModel.isDirty { return .yellow }
        return .green
    }

    private var statusText: String {
        if viewModel.isSaving { return String(localized: "Saving…", bundle: .module) }
        if viewModel.isDirty { return String(localized: "Edited", bundle: .module) }
        return String(localized: "Saved", bundle: .module)
    }

    // MARK: - Editor Toolbar

    private var editorToolbar: some View {
        HStack(spacing: 12) {
            if featureGate.isEnabled(.focusMode) {
                Button {
                    focusMode.toggleFocusMode()
                } label: {
                    Image(systemName: focusMode.isFocusModeActive
                          ? "eye.slash.fill" : "eye.fill")
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(focusMode.isFocusModeActive ? String(localized: "Exit focus mode", bundle: .module) : String(localized: "Enter focus mode", bundle: .module))
            }

            if viewModel.isDirty {
                Button {
                    Task { await viewModel.manualSave() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .symbolRenderingMode(.hierarchical)
                }
                .keyboardShortcut("s", modifiers: .command)
                .accessibilityLabel(String(localized: "Save note", bundle: .module))
            }
        }
    }

}
