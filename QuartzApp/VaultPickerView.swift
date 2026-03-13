import SwiftUI
import QuartzKit

/// Vault-Auswahl: Folder-Picker zum Öffnen eines lokalen Ordners als Vault.
struct VaultPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFilePicker = false
    @State private var vaultName = ""

    let onVaultSelected: (VaultConfig) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)

                Text("Open a Vault")
                    .font(.title2.bold())

                Text("Choose a folder on your device. Quartz will use it as your note vault.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    showFilePicker = true
                } label: {
                    Label("Choose Folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 32)
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

                    // Security-scoped bookmark for persistent access
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
