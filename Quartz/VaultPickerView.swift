import SwiftUI
import QuartzKit

/// Vault-Auswahl: Folder-Picker zum Öffnen eines lokalen Ordners als Vault.
/// Liquid Glass Design mit animiertem Icon.
struct VaultPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .largeTitle) private var folderIconSize: CGFloat = 56

    let onVaultSelected: (VaultConfig) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: folderIconSize, weight: .thin))
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
                UserDefaults.standard.set(bookmarkData, forKey: "quartz.vault.bookmark.\(url.lastPathComponent)")
            } catch {
                // Bookmark persistence is best-effort; vault still works for this session
            }

            let vault = VaultConfig(
                name: url.lastPathComponent,
                rootURL: url
            )
            onVaultSelected(vault)

            // Do NOT call stopAccessingSecurityScopedResource() here.
            // The security-scoped resource must remain accessible for the
            // lifetime of the vault session. It will be released when the
            // app terminates or the bookmark is resolved again.
            dismiss()

        case .failure:
            errorMessage = String(localized: "Could not open the selected folder. Please try again.")
        }
    }
}
