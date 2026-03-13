import SwiftUI

/// SwiftUI View für die Share Extension.
///
/// Zeigt eine kompakte UI zum Speichern geteilter Inhalte:
/// - Preview des geteilten Inhalts
/// - Vault-Auswahl
/// - Inbox oder neue Notiz
public struct ShareExtensionView: View {
    @State private var noteTitle: String = ""
    @State private var useInbox: Bool = true
    @State private var isSaving: Bool = false
    @State private var showSuccess: Bool = false

    let sharedItem: SharedItem
    let vaultRoot: URL
    let onDismiss: () -> Void

    public init(
        sharedItem: SharedItem,
        vaultRoot: URL,
        onDismiss: @escaping () -> Void
    ) {
        self.sharedItem = sharedItem
        self.vaultRoot = vaultRoot
        self.onDismiss = onDismiss
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Preview
                Section("Preview") {
                    Text(sharedItem.markdownContent)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }

                // Capture Mode
                Section("Save to") {
                    Toggle("Append to Inbox", isOn: $useInbox)

                    if !useInbox {
                        TextField("Note title", text: $noteTitle)
                    }
                }
            }
            .navigationTitle("Save to Quartz")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || (!useInbox && noteTitle.isEmpty))
                }
            }
            .overlay {
                if showSuccess {
                    successOverlay
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true

        let useCase = ShareCaptureUseCase()
        let mode: CaptureMode = useInbox ? .inbox : .newNote(title: noteTitle)

        do {
            _ = try useCase.capture(sharedItem, in: vaultRoot, mode: mode)
            withAnimation {
                showSuccess = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onDismiss()
            }
        } catch {
            isSaving = false
        }
    }

    private var successOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Saved!")
                .font(.headline)
        }
        .padding(32)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
