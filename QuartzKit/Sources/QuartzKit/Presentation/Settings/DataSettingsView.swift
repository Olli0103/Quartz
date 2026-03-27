import SwiftUI

/// Settings view for data, sync, and backup operations.
public struct DataSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appearanceManager) private var appearance
    @State private var showFilePicker = false
    @State private var importResult: ImportResultInfo?
    @State private var isImporting = false
    @State private var importError: String?

    // Self-resolving iCloud & backup state
    @State private var isICloudAvailable = false
    @State private var isVaultInICloud = false
    @State private var isMigrating = false
    @State private var availableBackups: [BackupEntry] = []
    @State private var isBackupInProgress = false
    @State private var backupProgress: Double = 0
    @State private var noteCount: Int = 0

    private let backupService = VaultBackupService()

    public init() {}

    public var body: some View {
        Form {
            SyncSettingsSection(
                syncStatus: .notApplicable,
                lastSyncTimestamp: UserDefaults.standard.object(forKey: "quartzLastSyncTimestamp") as? Date,
                conflictCount: 0,
                isVaultInICloud: isVaultInICloud,
                isICloudAvailable: isICloudAvailable,
                onEnableICloudSync: { migrateToICloud() }
            )

            BackupSettingsSection(
                availableBackups: availableBackups,
                isBackupInProgress: isBackupInProgress,
                backupProgress: backupProgress,
                onExportBackup: { exportBackup() }
            )

            if let vault = appState.currentVault {
                VaultInfoSection(
                    vaultName: vault.name,
                    noteCount: noteCount
                )
            }

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
                    .tint(appearance.accentColor)
                }
                .padding(.vertical, 4)
            } header: {
                Text(String(localized: "AI Index", bundle: .module))
            } footer: {
                Text(String(localized: "Progress is shown in the sidebar. Requires a vault to be open.", bundle: .module))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "Data & Sync", bundle: .module))
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
        .task {
            await resolveState()
        }
    }

    // MARK: - Self-Resolving State

    private func resolveState() async {
        // Resolve iCloud availability on background thread
        let containerURL = await CloudSyncService.resolveContainerURL()
        isICloudAvailable = containerURL != nil

        // Check if current vault is in iCloud
        if let root = appState.currentVault?.rootURL {
            let path = root.path(percentEncoded: false)
            isVaultInICloud = FileManager.default.isUbiquitousItem(at: root)
                || path.contains("com~apple~CloudDocs")
                || path.contains("/Mobile Documents/")

            // Load backups
            let backups = await backupService.listBackups(vaultRoot: root)
            availableBackups = backups

            // Count notes
            noteCount = countNotes(in: root)
        }
    }

    private func countNotes(in root: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension.lowercased() == "md" { count += 1 }
        }
        return count
    }

    // MARK: - Actions

    private func migrateToICloud() {
        guard let localRoot = appState.currentVault?.rootURL else { return }
        isMigrating = true
        Task {
            guard let containerURL = await CloudSyncService.resolveContainerURL() else {
                isMigrating = false
                return
            }
            let fm = FileManager.default
            let vaultName = localRoot.lastPathComponent
            let iCloudVaultURL = containerURL.appending(path: vaultName, directoryHint: .isDirectory)

            do {
                if !fm.fileExists(atPath: containerURL.path(percentEncoded: false)) {
                    try fm.createDirectory(at: containerURL, withIntermediateDirectories: true)
                }
                if !fm.fileExists(atPath: iCloudVaultURL.path(percentEncoded: false)) {
                    try fm.copyItem(at: localRoot, to: iCloudVaultURL)
                }
                // Switch vault to the iCloud copy
                var vault = VaultConfig(name: vaultName, rootURL: iCloudVaultURL, storageType: .iCloudDrive)
                vault.isDefault = true
                appState.switchVault(to: vault)
                isVaultInICloud = true
            } catch {
                print("[iCloud] Migration failed: \(error)")
            }
            isMigrating = false
        }
    }

    private func exportBackup() {
        guard let root = appState.currentVault?.rootURL else { return }
        isBackupInProgress = true
        backupProgress = 0
        Task.detached(priority: .utility) { [backupService] in
            _ = try? await backupService.createBackup(vaultRoot: root) { progress in
                Task { @MainActor in
                    backupProgress = progress.fraction
                }
            }
            await MainActor.run { [weak backupService] in
                isBackupInProgress = false
                backupProgress = 1
                if let root = appState.currentVault?.rootURL, let backupService {
                    Task {
                        availableBackups = await backupService.listBackups(vaultRoot: root)
                    }
                }
            }
        }
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
            .tint(appearance.accentColor)

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
