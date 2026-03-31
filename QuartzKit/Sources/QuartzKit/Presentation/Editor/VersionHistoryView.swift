import SwiftUI

/// Time-machine view for browsing and restoring historical versions of a note.
///
/// Uses Apple's `NSFileVersion` API to fetch auto-saved snapshots.
/// Split layout: timeline on the left, read-only preview on the right.
///
/// Presented as a sheet from the Inspector's "Version History" button.
public struct VersionHistoryView: View {
    let noteURL: URL
    let noteTitle: String
    let vaultRoot: URL
    let onRestored: () -> Void

    @State private var versions: [NoteVersion] = []
    @State private var selectedVersion: NoteVersion?
    @State private var previewText: String = ""
    @State private var isLoading = true
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appearanceManager) private var appearance

    private let service = VersionHistoryService()

    public init(noteURL: URL, noteTitle: String, vaultRoot: URL, onRestored: @escaping () -> Void) {
        self.noteURL = noteURL
        self.noteTitle = noteTitle
        self.vaultRoot = vaultRoot
        self.onRestored = onRestored
    }

    public var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(String(localized: "Loading versions\u{2026}", bundle: .module))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if versions.isEmpty {
                    emptyState
                } else {
                    splitContent
                }
            }
            .navigationTitle(String(localized: "Version History", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                }
            }
            .task { loadVersions() }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 500)
        #endif
    }

    // MARK: - Split Content

    private var splitContent: some View {
        HStack(spacing: 0) {
            // Timeline
            timeline
                .frame(width: 240)

            Divider()

            // Preview
            VStack(spacing: 0) {
                previewArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                }

                if selectedVersion != nil {
                    restoreBar
                }
            }
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(localized: "VERSIONS", bundle: .module))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List(versions, selection: Binding(
                get: { selectedVersion?.id },
                set: { id in
                    selectedVersion = versions.first { $0.id == id }
                    if let version = selectedVersion {
                        loadPreview(for: version)
                    }
                }
            )) { version in
                VStack(alignment: .leading, spacing: 3) {
                    Text(version.date, style: .date)
                        .font(.callout.weight(.medium))
                    Text(version.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(version.id)
                .accessibilityLabel(String(localized: "Version from \(version.date.formatted())", bundle: .module))
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Preview

    private var previewArea: some View {
        Group {
            if selectedVersion == nil {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "Select a version to preview", bundle: .module))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if previewText.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(previewText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: - Restore Bar

    private var restoreBar: some View {
        HStack {
            if let version = selectedVersion {
                Text(String(localized: "Version from \(version.date.formatted(date: .abbreviated, time: .shortened))", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                restoreSelectedVersion()
            } label: {
                HStack(spacing: 6) {
                    if isRestoring {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(String(localized: "Restore This Version", bundle: .module))
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(isRestoring || selectedVersion == nil)
        }
        .padding(12)
        .background(.bar)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(String(localized: "No Previous Versions", bundle: .module))
                .font(.headline)
                .foregroundStyle(.secondary)
            Text(String(localized: "Version history will appear after you save this note multiple times.", bundle: .module))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func loadVersions() {
        isLoading = true
        versions = service.fetchVersions(for: noteURL, vaultRoot: vaultRoot)
        isLoading = false

        if let first = versions.first {
            selectedVersion = first
            loadPreview(for: first)
        }
    }

    private func loadPreview(for version: NoteVersion) {
        previewText = ""
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                let text = try service.readText(from: version)
                await MainActor.run { previewText = text }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func restoreSelectedVersion() {
        guard let version = selectedVersion else { return }
        isRestoring = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) {
            do {
                try service.restore(version: version, to: noteURL)
                await MainActor.run {
                    QuartzFeedback.success()
                    isRestoring = false
                    onRestored()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    QuartzFeedback.warning()
                    isRestoring = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
