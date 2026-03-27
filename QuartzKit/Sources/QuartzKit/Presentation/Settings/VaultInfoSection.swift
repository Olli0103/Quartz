import SwiftUI

/// Vault statistics section for the Data & Sync settings panel.
///
/// Shows vault name, note count, and total size.
///
/// **Ref:** Phase G Spec — Vault Info Section
public struct VaultInfoSection: View {
    let vaultName: String
    let noteCount: Int
    let vaultSizeBytes: Int64?

    public init(vaultName: String, noteCount: Int, vaultSizeBytes: Int64? = nil) {
        self.vaultName = vaultName
        self.noteCount = noteCount
        self.vaultSizeBytes = vaultSizeBytes
    }

    public var body: some View {
        Section {
            HStack {
                Text(String(localized: "Vault", bundle: .module))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(vaultName)
            }
            .font(.callout)

            HStack {
                Text(String(localized: "Notes", bundle: .module))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(noteCount)")
                    .monospacedDigit()
            }
            .font(.callout)

            if let size = vaultSizeBytes {
                HStack {
                    Text(String(localized: "Vault Size", bundle: .module))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedSize(size))
                        .monospacedDigit()
                }
                .font(.callout)
            }
        } header: {
            Text(String(localized: "Vault Info", bundle: .module))
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
