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
    @State private var errorMessage: String?

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
                Section(String(localized: "Preview", bundle: .module)) {
                    Text(sharedItem.markdownContent)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                }

                // Capture Mode
                Section(String(localized: "Save to", bundle: .module)) {
                    Toggle(String(localized: "Append to Inbox", bundle: .module), isOn: $useInbox)

                    if !useInbox {
                        TextField(String(localized: "Note title", bundle: .module), text: $noteTitle)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "Save to Quartz", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: .module)) { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", bundle: .module)) { save() }
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
        errorMessage = nil

        let useCase = ShareCaptureUseCase()
        let mode: CaptureMode = useInbox ? .inbox : .newNote(title: noteTitle)

        do {
            _ = try useCase.capture(sharedItem, in: vaultRoot, mode: mode)
            withAnimation {
                showSuccess = true
            }
            Task {
                try? await Task.sleep(for: .seconds(1))
                onDismiss()
            }
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }

    private var successOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text(String(localized: "Saved!", bundle: .module))
                .font(.headline)
        }
        .padding(32)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
