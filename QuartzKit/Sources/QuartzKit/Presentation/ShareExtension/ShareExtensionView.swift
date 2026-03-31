import SwiftUI

/// SwiftUI view for the Share Extension — Liquid Glass design.
///
/// Receives text, URLs, or images from other iOS apps and captures them
/// into the user's vault. Supports appending to an Inbox note or creating
/// a new note with optional tags and comments.
///
/// **Privacy**: Writes directly to the vault file system via `ShareCaptureUseCase`
/// without needing to launch the full app.
public struct ShareExtensionView: View {
    @State private var noteTitle: String = ""
    @State private var tagText: String = ""
    @State private var comment: String = ""
    @State private var useInbox: Bool = true
    @State private var isSaving: Bool = false
    @State private var showSuccess: Bool = false
    @State private var errorMessage: String?
    @ScaledMetric(relativeTo: .largeTitle) private var successIconSize: CGFloat = 48
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            ScrollView {
                VStack(spacing: 16) {
                    // Preview card
                    previewCard

                    // Destination picker
                    destinationSection

                    // Comment field
                    commentSection

                    // Tag input
                    tagSection

                    // Error
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(16)
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
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text(String(localized: "Save", bundle: .module))
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSaving || (!useInbox && noteTitle.isEmpty))
                }
            }
            .overlay {
                if showSuccess {
                    successOverlay
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    // MARK: - Preview Card

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: sharedItem.previewIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuartzColors.accent)
                Text(String(localized: "SHARED CONTENT", bundle: .module))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }

            Text(sharedItem.markdownContent)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .quartzFloatingUltraThinSurface(cornerRadius: 14)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Destination

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "SAVE TO", bundle: .module))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 10) {
                destinationButton(
                    title: String(localized: "Inbox", bundle: .module),
                    icon: "tray.and.arrow.down",
                    selected: useInbox
                ) {
                    useInbox = true
                }

                destinationButton(
                    title: String(localized: "New Note", bundle: .module),
                    icon: "doc.badge.plus",
                    selected: !useInbox
                ) {
                    useInbox = false
                }
            }

            if !useInbox {
                TextField(String(localized: "Note title", bundle: .module), text: $noteTitle)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.fill.quaternary)
                    )
            }
        }
    }

    private func destinationButton(title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            QuartzFeedback.selection()
            withAnimation(reduceMotion ? .default : QuartzAnimation.standard) {
                action()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.medium))
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? QuartzColors.accent.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? QuartzColors.accent.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
            .foregroundStyle(selected ? QuartzColors.accent : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Comment

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "COMMENT", bundle: .module))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField(String(localized: "Add a quick note\u{2026}", bundle: .module), text: $comment, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.fill.quaternary)
                )
        }
    }

    // MARK: - Tags

    private var tagSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "TAGS", bundle: .module))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            TextField(String(localized: "tag1, tag2, tag3", bundle: .module), text: $tagText)
                .textFieldStyle(.plain)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.fill.quaternary)
                )
                .accessibilityLabel(String(localized: "Tags (comma separated)", bundle: .module))
        }
    }

    // MARK: - Save

    private func save() {
        isSaving = true
        errorMessage = nil

        // Build the content with optional comment prefix
        var enrichedItem = sharedItem
        if !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let commentBlock = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            switch sharedItem {
            case .text(let text):
                enrichedItem = .text(commentBlock + "\n\n" + text)
            case .url(let url, let title):
                enrichedItem = .mixed(text: commentBlock, url: url)
                _ = title // suppress warning
            case .mixed(let text, let url):
                enrichedItem = .mixed(text: commentBlock + "\n\n" + text, url: url)
            case .image:
                enrichedItem = sharedItem // Comment added separately for images
            }
        }

        let useCase = ShareCaptureUseCase()
        let mode: CaptureMode = useInbox ? .inbox : .newNote(title: noteTitle)

        do {
            _ = try useCase.capture(enrichedItem, in: vaultRoot, mode: mode)
            isSaving = false
            withAnimation { showSuccess = true }
            Task {
                try? await Task.sleep(for: .seconds(1))
                onDismiss()
            }
        } catch {
            isSaving = false
            errorMessage = String(localized: "Could not save content. Please try again.", bundle: .module)
        }
    }

    // MARK: - Success

    private var successOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: successIconSize))
                .foregroundStyle(.green)
                .scaleIn()
            Text(String(localized: "Saved!", bundle: .module))
                .font(.headline)
        }
        .padding(32)
        .quartzMaterialBackground(cornerRadius: 20)
    }
}

// MARK: - SharedItem Preview Helper

extension SharedItem {
    /// SF Symbol icon for the share extension preview card.
    var previewIcon: String {
        switch self {
        case .text: return "text.quote"
        case .url: return "link"
        case .image: return "photo"
        case .mixed: return "doc.text"
        }
    }
}
