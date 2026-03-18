import SwiftUI

/// Navigation hub for all settings.
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        #if os(macOS)
        TabView {
            AppearanceSettingsView()
                .tabItem {
                    Label(String(localized: "Appearance", bundle: .module), systemImage: "paintbrush.fill")
                }

            editorPlaceholder
                .tabItem {
                    Label(String(localized: "Editor", bundle: .module), systemImage: "textformat")
                }

            vaultPlaceholder
                .tabItem {
                    Label(String(localized: "Vault", bundle: .module), systemImage: "folder.fill")
                }

            aboutTab
                .tabItem {
                    Label(String(localized: "About", bundle: .module), systemImage: "info.circle.fill")
                }
        }
        .frame(minWidth: 480, minHeight: 300)
        #else
        NavigationStack {
            List {
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
                        editorPlaceholder
                    } label: {
                        SettingsRow(
                            icon: "textformat",
                            iconColor: QuartzColors.noteBlue,
                            title: String(localized: "Editor", bundle: .module)
                        )
                    }
                } header: {
                    Text(String(localized: "General", bundle: .module))
                }

                Section {
                    NavigationLink {
                        vaultPlaceholder
                    } label: {
                        SettingsRow(
                            icon: "folder.fill",
                            iconColor: QuartzColors.folderYellow,
                            title: String(localized: "Vault", bundle: .module)
                        )
                    }
                } header: {
                    Text(String(localized: "Data", bundle: .module))
                }

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
                    Text(String(localized: "About", bundle: .module))
                }
            }
            .navigationTitle(String(localized: "Settings", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", bundle: .module)) {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        #endif
    }

    private var editorPlaceholder: some View {
        VStack {
            Spacer()
            Text(String(localized: "Editor settings – coming soon", bundle: .module))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var vaultPlaceholder: some View {
        VStack {
            Spacer()
            Text(String(localized: "Vault settings – coming soon", bundle: .module))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.and.pencil")
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(QuartzColors.accentGradient)

            Text("Quartz")
                .font(.title2.bold())

            Text(String(localized: "Version \(QuartzKit.version)", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Settings Row (iOS only)

private struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
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
