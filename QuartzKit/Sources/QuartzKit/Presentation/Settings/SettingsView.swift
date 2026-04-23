import SwiftUI
import UniformTypeIdentifiers

/// Navigation hub for all settings.
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var diagnosticsExportData: Data?
    @State private var diagnosticsExportFileName = "Quartz-Diagnostics.txt"
    @State private var showDiagnosticsExporter = false
    @State private var isPreparingDiagnostics = false

    public init() {}

    public var body: some View {
        Group {
            #if os(macOS)
            TabView {
                AppearanceSettingsView()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tabItem {
                        Label(String(localized: "Appearance", bundle: .module), systemImage: "paintbrush.fill")
                    }

                EditorSettingsView()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tabItem {
                        Label(String(localized: "Editor", bundle: .module), systemImage: "textformat")
                    }

                AISettingsView()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tabItem {
                        Label(String(localized: "AI", bundle: .module), systemImage: "brain")
                    }

                DataSettingsView()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tabItem {
                        Label(String(localized: "Data & Sync", bundle: .module), systemImage: "arrow.triangle.2.circlepath.icloud")
                    }

                SecuritySettingsView()
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .tabItem {
                        Label(String(localized: "Security", bundle: .module), systemImage: "lock.fill")
                    }

                aboutTab
                    .tabItem {
                        Label(String(localized: "About", bundle: .module), systemImage: "info.circle.fill")
                    }
            }
            .frame(minWidth: 560, idealWidth: 600, minHeight: 420, idealHeight: 500)
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
                            EditorSettingsView()
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
                            AISettingsView()
                        } label: {
                            SettingsRow(
                                icon: "brain",
                                iconColor: QuartzColors.canvasPurple,
                                title: String(localized: "AI", bundle: .module)
                            )
                        }
                    } header: {
                        Text(String(localized: "Intelligence", bundle: .module))
                    }

                    Section {
                        NavigationLink {
                            DataSettingsView()
                        } label: {
                            SettingsRow(
                                icon: "arrow.triangle.2.circlepath.icloud",
                                iconColor: QuartzColors.assetOrange,
                                title: String(localized: "Data & Sync", bundle: .module)
                            )
                        }
                    } header: {
                        Text(String(localized: "Data & Sync", bundle: .module))
                    }

                    Section {
                        NavigationLink {
                            SecuritySettingsView()
                        } label: {
                            SettingsRow(
                                icon: "lock.fill",
                                iconColor: .green,
                                title: String(localized: "Security", bundle: .module)
                            )
                        }
                    } header: {
                        Text(String(localized: "Security", bundle: .module))
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
                        Button(action: exportDiagnostics) {
                            SettingsRow(
                                icon: "stethoscope",
                                iconColor: .orange,
                                title: isPreparingDiagnostics
                                    ? String(localized: "Preparing Diagnostics…", bundle: .module)
                                    : String(localized: "Export Diagnostics", bundle: .module)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isPreparingDiagnostics)

                        NavigationLink {
                            FeedbackView()
                        } label: {
                            SettingsRow(
                                icon: "bubble.left.and.bubble.right",
                                iconColor: .blue,
                                title: String(localized: "Send Feedback", bundle: .module)
                            )
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
        .fileExporter(
            isPresented: $showDiagnosticsExporter,
            document: ExportFileDocument(data: diagnosticsExportData ?? Data(), format: .markdown),
            contentType: .plainText,
            defaultFilename: diagnosticsExportFileName
        ) { _ in
            diagnosticsExportData = nil
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "square.and.pencil")
                .font(.largeTitle.weight(.thin))
                .foregroundStyle(QuartzColors.accentGradient)

            Text("Quartz")
                .font(.title2.bold())

            Text(String(localized: "Version \(QuartzKit.version)", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(String(localized: "A beautiful, open-source note-taking app\nfor Apple platforms.", bundle: .module))
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            UpdateCheckButton()
            exportDiagnosticsButton

            HStack(spacing: 20) {
                Link(destination: URL(string: "https://github.com/Olli0103/Quartz")!) {
                    Label("GitHub", systemImage: "link")
                        .font(.callout)
                }
                FeedbackLink()
                Link(destination: URL(string: "https://github.com/sponsors/Olli0103")!) {
                    Label(String(localized: "Sponsor", bundle: .module), systemImage: "heart.fill")
                        .font(.callout)
                        .foregroundStyle(.pink)
                }
            }
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var exportDiagnosticsButton: some View {
        Button {
            exportDiagnostics()
        } label: {
            Label(
                isPreparingDiagnostics
                    ? String(localized: "Preparing Diagnostics…", bundle: .module)
                    : String(localized: "Export Diagnostics", bundle: .module),
                systemImage: "stethoscope"
            )
            .font(.callout)
        }
        .buttonStyle(.bordered)
        .disabled(isPreparingDiagnostics)
        .help(String(localized: "Exports recent warnings, errors, indexing telemetry, and vault index state.", bundle: .module))
    }

    private func exportDiagnostics() {
        guard !isPreparingDiagnostics else { return }
        isPreparingDiagnostics = true

        Task {
            let report = await DiagnosticExportService.shared.generateReport(
                context: "Settings Export",
                error: nil
            )
            let text = await DiagnosticExportService.shared.exportToText(report)
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")

            await MainActor.run {
                diagnosticsExportData = Data(text.utf8)
                diagnosticsExportFileName = "Quartz-Diagnostics-\(timestamp).txt"
                isPreparingDiagnostics = false
                showDiagnosticsExporter = true
            }
        }
    }
}

// MARK: - Feedback Link

private struct FeedbackLink: View {
    @State private var showFeedback = false

    var body: some View {
        Button {
            showFeedback = true
        } label: {
            Label(String(localized: "Send Feedback", bundle: .module), systemImage: "bubble.left.and.bubble.right")
                .font(.callout)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFeedback) {
            FeedbackView()
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
                .font(.subheadline.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
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
