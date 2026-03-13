import SwiftUI

/// Navigations-Hub für alle Einstellungen.
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        Label(
                            String(localized: "Appearance", bundle: .module),
                            systemImage: "paintbrush.fill"
                        )
                    }
                }

                Section {
                    NavigationLink {
                        Text("Vault settings – coming soon")
                    } label: {
                        Label(
                            String(localized: "Vault", bundle: .module),
                            systemImage: "folder.fill"
                        )
                    }
                }

                Section {
                    HStack {
                        Text(String(localized: "Version", bundle: .module))
                        Spacer()
                        Text(QuartzKit.version)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(String(localized: "About", bundle: .module))
                }
            }
            .navigationTitle(String(localized: "Settings", bundle: .module))
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) {
                        dismiss()
                    }
                }
            }
            #endif
        }
    }
}
