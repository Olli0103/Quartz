import SwiftUI
import QuartzKit

/// Vault-Auswahl: Folder-Picker zum Öffnen eines lokalen Ordners als Vault.
/// Liquid Glass Design mit animiertem Icon.
struct VaultPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false

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

                    Text("Open a Vault")
                        .font(.title2.bold())

                    Text("Choose a folder on your device.\nQuartz will use it as your note vault.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                Spacer()

                QuartzButton("Choose Folder", icon: "folder") {
                    showFilePicker = true
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .padding()
            .navigationTitle("Vault")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    guard url.startAccessingSecurityScopedResource() else { return }
                    defer { url.stopAccessingSecurityScopedResource() }

                    let vault = VaultConfig(
                        name: url.lastPathComponent,
                        rootURL: url
                    )
                    onVaultSelected(vault)
                    dismiss()

                case .failure:
                    break
                }
            }
        }
    }
}
