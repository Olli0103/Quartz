import SwiftUI

/// SwiftUI view for the Quick Note panel.
///
/// Compact editor with title, body, and save button.
/// Supports ⌘+Return for quick saving.
public struct QuickNoteView: View {
    @State private var noteTitle: String = ""
    @State private var noteBody: String = ""
    @State private var isSaving: Bool = false
    @State private var savedSuccessfully: Bool = false
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .title) private var successIconSize: CGFloat = 36
    @FocusState private var focusedField: Field?

    let vaultRoot: URL
    let onDismiss: () -> Void

    private enum Field {
        case title, body
    }

    public init(vaultRoot: URL, onDismiss: @escaping () -> Void) {
        self.vaultRoot = vaultRoot
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Title
            TextField(String(localized: "Title", bundle: .module), text: $noteTitle)
                .textFieldStyle(.plain)
                .font(.title3.bold())
                .focused($focusedField, equals: .title)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .onSubmit { focusedField = .body }

            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 4)

            // Body
            TextEditor(text: $noteBody)
                .font(.body)
                .focused($focusedField, equals: .body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)

            Divider()

            // Error
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            // Actions
            HStack {
                Text(String(localized: "⌘↩ to save", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(String(localized: "Cancel", bundle: .module)) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(String(localized: "Save", bundle: .module)) {
                    save()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(noteTitle.isEmpty || isSaving)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 350, minHeight: 200)
        .onAppear {
            focusedField = .title
        }
        .overlay {
            if savedSuccessfully {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: successIconSize))
                        .foregroundStyle(.green)
                    Text(String(localized: "Saved", bundle: .module))
                        .font(.caption.bold())
                }
                .padding(24)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func save() {
        guard !noteTitle.isEmpty else { return }
        isSaving = true

        let useCase = ShareCaptureUseCase()
        let item: SharedItem = .text(noteBody)

        do {
            _ = try useCase.capture(item, in: vaultRoot, mode: .newNote(title: noteTitle))
            isSaving = false
            withAnimation {
                savedSuccessfully = true
            }
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                onDismiss()
            }
        } catch {
            isSaving = false
            errorMessage = String(localized: "Could not save note. Please try again.", bundle: .module)
        }
    }
}
