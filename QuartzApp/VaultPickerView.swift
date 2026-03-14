import SwiftUI
import QuartzKit

/// Vault-Auswahl: Folder-Picker zum Öffnen eines lokalen Ordners als Vault.
/// Liquid Glass Design mit animiertem Icon.
struct VaultPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var errorMessage: String?

    let onVaultSelected: (VaultConfig) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 56, weight: .thin))
                        .foregroundStyle(QuartzColors.folderYellow)
                        .symbolEffect(.bounce, options: .nonRepeating)

                    Text(String(localized: "Open a Vault"))
                        .font(.title2.bold())

                    Text(String(localized: "Choose a folder on your device.\nQuartz will use it as your note vault."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
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

                QuartzButton(String(localized: "Choose Folder"), icon: "folder") {
                    showFilePicker = true
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
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = String(localized: "Unable to access the selected folder. Please try again.")
                return
            }

            // Persist bookmark for future access
            do {
                let bookmarkData = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: "quartz.vault.bookmark.\(url.lastPathComponent)")
            } catch {
                // Bookmark persistence is best-effort; vault still works for this session
            }

            let vault = VaultConfig(
                name: url.lastPathComponent,
                rootURL: url
            )
            onVaultSelected(vault)

            // Stop accessing after callback has captured what it needs
            url.stopAccessingSecurityScopedResource()
            dismiss()

        case .failure(let error):
            errorMessage = String(localized: "Could not open folder: \(error.localizedDescription)")
        }
    }
}
