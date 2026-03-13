import SwiftUI

/// Einstellungen für Erscheinungsbild: Theme, Schriftgröße.
public struct AppearanceSettingsView: View {
    @Environment(\.appearanceManager) private var appearance

    public init() {}

    public var body: some View {
        Form {
            // MARK: - Theme
            Section {
                Picker(
                    String(localized: "Theme", bundle: .module),
                    selection: Binding(
                        get: { appearance.theme },
                        set: { appearance.theme = $0 }
                    )
                ) {
                    ForEach(AppearanceManager.Theme.allCases, id: \.self) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
            } header: {
                Text(String(localized: "Theme", bundle: .module))
            }

            // MARK: - Editor Font Size
            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text(String(localized: "Editor Font Size", bundle: .module))
                        Spacer()
                        Text("\(Int(appearance.editorFontScale * 100))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Slider(
                        value: Binding(
                            get: { appearance.editorFontScale },
                            set: { appearance.editorFontScale = $0 }
                        ),
                        in: 0.8...2.0,
                        step: 0.1
                    )

                    Text(String(localized: "Preview text at current size", bundle: .module))
                        .font(.system(size: 16 * appearance.editorFontScale))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "Editor", bundle: .module))
            }
        }
        .navigationTitle(String(localized: "Appearance", bundle: .module))
    }
}
