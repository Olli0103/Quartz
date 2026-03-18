import SwiftUI

/// Editor configuration: focus mode, typewriter mode, autosave.
public struct EditorSettingsView: View {
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
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(String(localized: "Editor Font Size", bundle: .module))
                        Spacer()
                        Text("\(Int(appearance.editorFontScale * 100))%")
                            .font(.body.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { appearance.editorFontScale },
                            set: { appearance.editorFontScale = $0 }
                        ),
                        in: 0.8...2.0,
                        step: 0.1
                    ) {
                        Text(String(localized: "Font Size", bundle: .module))
                    }
                    .tint(QuartzColors.accent)
                }
            } header: {
                Text(String(localized: "Typography", bundle: .module))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Editor", bundle: .module))
    }
}
