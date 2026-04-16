import SwiftUI

/// Editor configuration for currently shipped writing controls.
public struct EditorSettingsView: View {
    static let showsTypewriterModeControl = FocusModeManager.exposesTypewriterModeSetting

    @Environment(\.focusModeManager) private var focusMode
    @Environment(\.appearanceManager) private var appearance

    @AppStorage("quartz.editor.autosaveEnabled") private var autosaveEnabled = true
    @AppStorage("quartz.editor.spellCheckEnabled") private var spellCheckEnabled = true

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { focusMode.isFocusModeActive },
                    set: { _ in focusMode.toggleFocusMode() }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Focus Mode", bundle: .module))
                        Text(String(localized: "Hides toolbar and status bar for distraction-free writing.", bundle: .module))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if Self.showsTypewriterModeControl {
                    Toggle(isOn: Binding(
                        get: { focusMode.isTypewriterModeActive },
                        set: { _ in focusMode.toggleTypewriterMode() }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Typewriter Mode", bundle: .module))
                            Text(String(localized: "Keeps the active line centered vertically.", bundle: .module))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(String(localized: "Writing", bundle: .module))
            }

            Section {
                Toggle(String(localized: "Autosave", bundle: .module), isOn: $autosaveEnabled)
                Toggle(String(localized: "Spell Check", bundle: .module), isOn: $spellCheckEnabled)
            } header: {
                Text(String(localized: "Behavior", bundle: .module))
            }

            Section {
                // Font Family
                Picker(String(localized: "Font", bundle: .module), selection: Binding(
                    get: { appearance.editorFontFamily },
                    set: { appearance.editorFontFamily = $0 }
                )) {
                    ForEach(AppearanceManager.EditorFontFamily.allCases, id: \.self) { family in
                        Text(family.displayName).tag(family)
                    }
                }

                // Font Size
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "Size", bundle: .module))
                        Spacer()
                        Text("\(Int(appearance.editorFontSize))pt")
                            .font(.body.weight(.medium).monospacedDigit())
                            .foregroundStyle(appearance.accentColor)
                    }
                    Slider(
                        value: Binding(
                            get: { appearance.editorFontSize },
                            set: { appearance.editorFontSize = $0 }
                        ),
                        in: 12...24,
                        step: 1
                    )
                    .tint(appearance.accentColor)
                }

                // Line Spacing
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "Line Spacing", bundle: .module))
                        Spacer()
                        Text(String(format: "%.1fx", appearance.editorLineSpacing))
                            .font(.body.weight(.medium).monospacedDigit())
                            .foregroundStyle(appearance.accentColor)
                    }
                    Slider(
                        value: Binding(
                            get: { appearance.editorLineSpacing },
                            set: { appearance.editorLineSpacing = $0 }
                        ),
                        in: 1.0...2.5,
                        step: 0.1
                    )
                    .tint(appearance.accentColor)
                }

                // Max Width
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(localized: "Text Width", bundle: .module))
                        Spacer()
                        Text("\(Int(appearance.editorMaxWidth))pt")
                            .font(.body.weight(.medium).monospacedDigit())
                            .foregroundStyle(appearance.accentColor)
                    }
                    Slider(
                        value: Binding(
                            get: { appearance.editorMaxWidth },
                            set: { appearance.editorMaxWidth = $0 }
                        ),
                        in: 400...1200,
                        step: 10
                    )
                    .tint(appearance.accentColor)
                }

                // Live Preview
                typographyPreview
            } header: {
                Text(String(localized: "Typography", bundle: .module))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Editor", bundle: .module))
    }

    // MARK: - Typography Preview

    private var typographyPreview: some View {
        Text("The quick brown fox jumps over the lazy dog. Here is a sample of your current typography settings — headings, body text, and code.")
            .font(previewFont)
            .lineSpacing((appearance.editorLineSpacing - 1.0) * appearance.editorFontSize)
            .foregroundStyle(.secondary)
            .frame(maxWidth: min(appearance.editorMaxWidth, .infinity), alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.fill.quaternary)
            )
            .animation(.smooth(duration: 0.2), value: appearance.editorFontSize)
            .animation(.smooth(duration: 0.2), value: appearance.editorFontFamily)
            .animation(.smooth(duration: 0.2), value: appearance.editorLineSpacing)
    }

    private var previewFont: Font {
        switch appearance.editorFontFamily {
        case .system:     .system(size: appearance.editorFontSize)
        case .serif:      .system(size: appearance.editorFontSize, design: .serif)
        case .monospaced: .system(size: appearance.editorFontSize, design: .monospaced)
        case .rounded:    .system(size: appearance.editorFontSize, design: .rounded)
        }
    }
}
