import SwiftUI

/// Navigations-Hub für alle Einstellungen – Liquid Glass Karten-Design.
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // Appearance
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        SettingsRow(
                            icon: "paintbrush.fill",
                            iconColor: QuartzColors.canvasPurple,
                            title: String(localized: "Appearance", bundle: .module)
                        )
                    }

                    NavigationLink {
                        Text("Editor settings – coming soon")
                    } label: {
                        SettingsRow(
                            icon: "textformat",
                            iconColor: QuartzColors.noteBlue,
                            title: String(localized: "Editor", bundle: .module)
                        )
                    }
                } header: {
                    QuartzSectionHeader("General")
                }

                // Vault
                Section {
                    NavigationLink {
                        Text("Vault settings – coming soon")
                    } label: {
                        SettingsRow(
                            icon: "folder.fill",
                            iconColor: QuartzColors.folderYellow,
                            title: String(localized: "Vault", bundle: .module)
                        )
                    }

                    NavigationLink {
                        Text("iCloud sync – coming soon")
                    } label: {
                        SettingsRow(
                            icon: "icloud.fill",
                            iconColor: .blue,
                            title: "iCloud Sync"
                        )
                    }
                } header: {
                    QuartzSectionHeader("Data")
                }

                // About
                Section {
                    HStack {
                        SettingsRow(
                            icon: "info.circle.fill",
                            iconColor: .gray,
                            title: String(localized: "Version", bundle: .module)
                        )
                        Spacer()
                        Text(QuartzKit.version)
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                } header: {
                    QuartzSectionHeader("About")
                }
            }
            .navigationTitle(String(localized: "Settings", bundle: .module))
            #if os(iOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            #endif
        }
    }
}

// MARK: - Settings Row

private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(iconColor.gradient)
                )

            Text(title)
                .font(.body)
        }
    }
}
