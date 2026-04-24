import SwiftUI
import QuartzKit
import UniformTypeIdentifiers
import os

/// Vault selection: open an existing folder or create a new vault folder.
struct VaultPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var showCreateNameSheet = false
    @State private var showCreateLocationPicker = false
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

                if let lastVaultName = VaultAccessManager.shared.lastVaultName,
                   VaultAccessManager.shared.hasPersistedBookmark {
                    Button {
                        QuartzFeedback.selection()
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
                    .accessibilityIdentifier("vault-picker-open")

                    Button {
                        QuartzFeedback.selection()
                        showCreateNameSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text(String(localized: "Create New Vault"))
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(QuartzColors.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("vault-picker-create")
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
            .fileImporter(
                isPresented: $showCreateLocationPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleCreateVaultLocation(result)
            }
            .alert(String(localized: "Create New Vault"), isPresented: $showCreateNameSheet) {
                TextField(String(localized: "Vault name"), text: $newVaultName)
                Button(String(localized: "Choose Location…")) {
                    let name = newVaultName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else {
                        errorMessage = String(localized: "Please enter a vault name.")
                        return
                    }
                    showCreateLocationPicker = true
                }
                Button(String(localized: "Cancel"), role: .cancel) { newVaultName = "" }
            } message: {
                Text(String(localized: "Enter a name and then choose where to create it."))
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let vault = try VaultAccessManager.shared.openVault(at: url)
                onVaultSelected(vault)
                dismiss()
            } catch {
                Logger(subsystem: "com.quartz", category: "VaultPicker")
                    .warning("Failed to open selected vault: \(error.localizedDescription)")
                QuartzDiagnostics.error(
                    category: "VaultPicker",
                    "Failed to open selected vault: \(error.localizedDescription)"
                )
                #if os(macOS)
                errorMessage = String(localized: "Unable to access the selected folder. Grant Full Disk Access in System Settings.")
                #else
                errorMessage = String(localized: "Unable to access the selected folder. Please re-select from the Files app.")
                #endif
            }

        case .failure:
            #if os(macOS)
            errorMessage = String(localized: "Could not open the selected folder. Check Sandbox permissions in System Settings.")
            #else
            errorMessage = String(localized: "Could not open the selected folder. Please try again from the Files app.")
            #endif
        }
    }

    private func handleCreateVaultLocation(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let parentURL = urls.first else { return }
            guard parentURL.startAccessingSecurityScopedResource() else {
                errorMessage = String(localized: "Unable to access the selected location.")
                return
            }

            let name = newVaultName.trimmingCharacters(in: .whitespacesAndNewlines)
            newVaultName = ""
            guard !name.isEmpty else {
                errorMessage = String(localized: "Please enter a vault name.")
                parentURL.stopAccessingSecurityScopedResource()
                return
            }

            let vaultURL = parentURL.appending(path: name)
            do {
                try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
            } catch {
                errorMessage = error.localizedDescription
                parentURL.stopAccessingSecurityScopedResource()
                return
            }

            do {
                let vault = try VaultAccessManager.shared.openVault(at: vaultURL, name: name)
                parentURL.stopAccessingSecurityScopedResource()
                onVaultSelected(vault)
                dismiss()
            } catch {
                Logger(subsystem: "com.quartz", category: "VaultPicker")
                    .warning("Failed to register created vault: \(error.localizedDescription)")
                QuartzDiagnostics.error(
                    category: "VaultPicker",
                    "Failed to register created vault: \(error.localizedDescription)"
                )
                parentURL.stopAccessingSecurityScopedResource()
                errorMessage = String(localized: "Could not save vault access: \(error.localizedDescription)")
            }

        case .failure:
            errorMessage = String(localized: "Could not access the selected location.")
        }
    }

    private func restoreLastVault() {
        Task { @MainActor in
            do {
                if let vault = try await VaultAccessManager.shared.restoreLastVaultWithRetry(maxAttempts: 2) {
                    onVaultSelected(vault)
                    dismiss()
                } else {
                    errorMessage = String(localized: "Could not find saved vault bookmark.")
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
