import SwiftUI

/// Side-by-side comparison when the file changed on disk while the editor has local edits.
@MainActor
public struct ExternalModificationMergeView: View {
    let localText: String
    let diskText: String
    let onMerge: (String) -> Void
    let onReloadDisk: () -> Void
    let onDismissKeepEditing: () -> Void

    @State private var mergedText: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(
        localText: String,
        diskText: String,
        onMerge: @escaping (String) -> Void,
        onReloadDisk: @escaping () -> Void,
        onDismissKeepEditing: @escaping () -> Void
    ) {
        self.localText = localText
        self.diskText = diskText
        self.onMerge = onMerge
        self.onReloadDisk = onReloadDisk
        self.onDismissKeepEditing = onDismissKeepEditing
        _mergedText = State(initialValue: localText)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                comparisonSection
                mergeEditorSection
            }
            .navigationTitle(String(localized: "Compare Changes", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Keep Editing", bundle: .module)) {
                        onDismissKeepEditing()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Merge & Save", bundle: .module)) {
                        onMerge(mergedText)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        #if os(iOS)
        .presentationDragIndicator(.visible)
        #endif
    }

    @ViewBuilder
    private var comparisonSection: some View {
        if horizontalSizeClass == .compact {
            VStack(alignment: .leading, spacing: 12) {
                labeledPane(title: String(localized: "Your Edits", bundle: .module), text: localText, accent: QuartzColors.noteBlue)
                labeledPane(title: String(localized: "On Disk", bundle: .module), text: diskText, accent: QuartzColors.assetOrange)
            }
            .padding()
        } else {
            HStack(alignment: .top, spacing: 12) {
                labeledPane(title: String(localized: "Your Edits", bundle: .module), text: localText, accent: QuartzColors.noteBlue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                labeledPane(title: String(localized: "On Disk", bundle: .module), text: diskText, accent: QuartzColors.assetOrange)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
        }
    }

    private func labeledPane(title: String, text: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 120, maxHeight: 220)
            .padding(12)
            .background {
                ContainerRelativeShape()
                    .fill(.regularMaterial)
            }
            .overlay {
                ContainerRelativeShape()
                    .strokeBorder(accent.opacity(0.35), lineWidth: 1)
            }
        }
    }

    private var mergeEditorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Merged result — copy from above, then save", bundle: .module))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $mergedText)
                .font(.system(.body, design: .monospaced))
                #if os(iOS)
                .scrollContentBackground(.hidden)
                #endif
                .padding(12)
                .frame(minHeight: 160)
                .background {
                    ContainerRelativeShape()
                        .fill(.quaternary.opacity(0.35))
                }
                .overlay {
                    ContainerRelativeShape()
                        .strokeBorder(QuartzColors.accent.opacity(0.4), lineWidth: 1)
                }

            Button(String(localized: "Reload from Disk (discard my edits)", bundle: .module)) {
                onReloadDisk()
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
        }
        .padding()
    }
}
