import SwiftUI
import QuartzKit
import UniformTypeIdentifiers
import os

/// Vault selection: open an existing folder or create a new vault folder.
struct VaultPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var showCreateSheet = false
    @State private var newVaultName = ""
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .largeTitle) private var folderIconSize: CGFloat = 56

    let onVaultSelected: (VaultConfig) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: folderIconSize, weight: .thin))
                        .foregroundStyle(QuartzColors.folderYellow)

                    Text(String(localized: "Open a Vault"))
                        .font(.title2.bold())

                    Text(String(localized: "Choose an existing folder with your notes\nor create a new vault folder."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                // Previously used vault
                if let lastVaultName = UserDefaults.standard.string(forKey: "quartz.lastVault.name"),
                   UserDefaults.standard.data(forKey: "quartz.lastVault.bookmark") != nil {
                    Button {
                        restoreLastVault()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title3)
                                .foregroundStyle(QuartzColors.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "Reopen Last Vault"))
                                    .font(.body.weight(.medium))
                                Text(lastVaultName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.fill.tertiary)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 32)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }

                Spacer()

                VStack(spacing: 12) {
                    QuartzButton(String(localized: "Open Existing Folder"), icon: "folder") {
                        showFilePicker = true
                    }

                    Button {
                        showCreateSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text(String(localized: "Create New Vault"))
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(QuartzColors.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .padding()
            .navigationTitle(String(localized: "Vault"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .alert(String(localized: "Create New Vault"), isPresented: $showCreateSheet) {
                TextField(String(localized: "Vault name"), text: $newVaultName)
                Button(String(localized: "Create")) {
                    createNewVault()
                }
                Button(String(localized: "Cancel"), role: .cancel) { newVaultName = "" }
            } message: {
                Text(String(localized: "A new folder will be created in your Documents."))
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                #if os(macOS)
                errorMessage = String(localized: "Unable to access the selected folder. Grant Full Disk Access in System Settings.")
                #else
                errorMessage = String(localized: "Unable to access the selected folder. Please re-select from the Files app.")
                #endif
                return
            }

            let vault = VaultConfig(name: url.lastPathComponent, rootURL: url)
            persistBookmark(for: url, vaultName: vault.name)
            onVaultSelected(vault)
            dismiss()

        case .failure:
            #if os(macOS)
            errorMessage = String(localized: "Could not open the selected folder. Check Sandbox permissions in System Settings.")
            #else
            errorMessage = String(localized: "Could not open the selected folder. Please try again from the Files app.")
            #endif
        }
    }

    private func createNewVault() {
        let name = newVaultName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = String(localized: "Please enter a vault name.")
            return
        }
        newVaultName = ""

        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let vaultURL = documentsURL.appending(path: name)

        do {
            try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let vault = VaultConfig(name: name, rootURL: vaultURL)
        persistBookmark(for: vaultURL, vaultName: vault.name)
        onVaultSelected(vault)
        dismiss()
    }

    private func restoreLastVault() {
        guard let bookmarkData = UserDefaults.standard.data(forKey: "quartz.lastVault.bookmark") else {
            errorMessage = String(localized: "Could not find saved vault bookmark.")
            return
        }

        var isStale = false
        do {
            #if os(macOS)
            let url = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, bookmarkDataIsStale: &isStale)
            #else
            let url = try URL(resolvingBookmarkData: bookmarkData, bookmarkDataIsStale: &isStale)
            #endif

            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = String(localized: "Access to the vault folder was revoked. Please re-select it.")
                return
            }

            if isStale {
                persistBookmark(for: url, vaultName: url.lastPathComponent)
            }

            let name = UserDefaults.standard.string(forKey: "quartz.lastVault.name") ?? url.lastPathComponent
            let vault = VaultConfig(name: name, rootURL: url)
            onVaultSelected(vault)
            dismiss()
        } catch {
            errorMessage = String(localized: "Could not restore vault: \(error.localizedDescription)")
        }
    }

    private func persistBookmark(for url: URL, vaultName: String) {
        do {
            #if os(macOS)
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #else
            let bookmarkData = try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #endif
            UserDefaults.standard.set(bookmarkData, forKey: "quartz.lastVault.bookmark")
            UserDefaults.standard.set(vaultName, forKey: "quartz.lastVault.name")
        } catch {
            Logger(subsystem: "com.quartz", category: "VaultPicker")
                .error("Failed to persist vault bookmark: \(error.localizedDescription)")
        }
    }
}
