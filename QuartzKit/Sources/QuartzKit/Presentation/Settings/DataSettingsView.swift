import SwiftUI

/// Settings view for data import/export operations.
public struct DataSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var showFilePicker = false
    @State private var importResult: ImportResultInfo?
    @State private var isImporting = false
    @State private var importError: String?

    public init() {}

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "Import Notes", bundle: .module), systemImage: "square.and.arrow.down")
                        .font(.body.weight(.medium))

                    Text(String(localized: "Import HTML, TXT, RTF, PDF, or Markdown files from a folder into your vault.", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    importButton
                }
                .padding(.vertical, 4)
            } header: {
                Text(String(localized: "Import", bundle: .module))
            }

            if let result = importResult {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(String(localized: "\(result.imported) notes imported", bundle: .module))
                                .font(.body.weight(.medium))
                        }

                        if result.foldersCreated > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(.blue)
                                Text(String(localized: "\(result.foldersCreated) folders created", bundle: .module))
                                    .font(.caption)
                            }
                        }

                        if result.skipped > 0 {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.uturn.right.circle")
                                    .foregroundStyle(.orange)
                                Text(String(localized: "\(result.skipped) notes skipped (already exist)", bundle: .module))
                                    .font(.caption)
                            }
                        }

                        if !result.errors.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(result.errors.joined(separator: "\n"))
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text(String(localized: "Last Import", bundle: .module))
                }
            }

            if let error = importError {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "Vault Indexing", bundle: .module), systemImage: "brain.head.profile")
                        .font(.body.weight(.medium))

                    Text(String(localized: "Indexing builds a semantic search index for AI features like \"Chat with Vault\". Indexing runs automatically when you open a vault.", bundle: .module))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        NotificationCenter.default.post(name: .quartzReindexRequested, object: nil)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(String(localized: "Reindex Vault Now", bundle: .module))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .disabled(appState.currentVault == nil)
                    .buttonStyle(.borderedProminent)
                    .tint(QuartzColors.accent)
                }
                .padding(.vertical, 4)
            } header: {
                Text(String(localized: "AI Index", bundle: .module))
            } footer: {
                Text(String(localized: "Progress is shown in the sidebar. Requires a vault to be open.", bundle: .module))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Data", bundle: .module))
        #if os(macOS)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        #else
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        #endif
    }

    @ViewBuilder
    private var importButton: some View {
        if let vault = appState.currentVault {
            Button {
                showFilePicker = true
            } label: {
                HStack {
                    if isImporting {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(localized: "Importing…", bundle: .module))
                    } else {
                        Image(systemName: "folder")
                        Text(String(localized: "Choose Folder…", bundle: .module))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .disabled(isImporting)
            .buttonStyle(.borderedProminent)
            .tint(QuartzColors.accent)

            Text(String(localized: "Importing into: \(vault.name)", bundle: .module))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        } else {
            Text(String(localized: "Open a vault first to import notes.", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let sourceURL = urls.first,
                  let vaultURL = appState.currentVault?.rootURL else { return }

            let gained = sourceURL.startAccessingSecurityScopedResource()

            isImporting = true
            importError = nil

            Task.detached {
                let importer = NotesImporter()
                do {
                    let outcome = try await importer.importNotes(from: sourceURL, into: vaultURL)
                    await MainActor.run {
                        importResult = ImportResultInfo(
                            imported: outcome.imported,
                            skipped: outcome.skipped,
                            foldersCreated: outcome.foldersCreated,
                            errors: outcome.errors
                        )
                        isImporting = false
                        if gained { sourceURL.stopAccessingSecurityScopedResource() }
                    }
                } catch {
                    await MainActor.run {
                        importError = error.localizedDescription
                        isImporting = false
                        if gained { sourceURL.stopAccessingSecurityScopedResource() }
                    }
                }
            }

        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

private struct ImportResultInfo {
    let imported: Int
    let skipped: Int
    let foldersCreated: Int
    let errors: [String]
}
