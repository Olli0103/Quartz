import SwiftUI

/// Time-machine view for browsing and restoring historical versions of a note.
///
/// Uses Quartz's self-managed snapshot system to fetch saved versions.
/// Split layout: timeline on the left, read-only preview on the right.
///
/// **Thread Safety**: All file I/O runs off the main thread to prevent frame drops.
///
/// Presented as a sheet from the Inspector's "Version History" button.
public struct VersionHistoryView: View {
    let noteURL: URL
    let noteTitle: String
    let vaultRoot: URL
    let onRestored: () -> Void
    let service: VersionHistoryService

    @State private var versions: [NoteVersion] = []
    @State private var selectedVersion: NoteVersion?
    @State private var previewText: String = ""
    @State private var isLoading = true
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appearanceManager) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a version history view.
    ///
    /// - Parameters:
    ///   - noteURL: URL of the note to show history for.
    ///   - noteTitle: Display title of the note.
    ///   - vaultRoot: Root URL of the vault.
    ///   - service: Version history service (defaults to shared instance for production).
    ///   - onRestored: Callback invoked after successful restore.
    public init(
        noteURL: URL,
        noteTitle: String,
        vaultRoot: URL,
        service: VersionHistoryService = VersionHistoryService(),
        onRestored: @escaping () -> Void
    ) {
        self.noteURL = noteURL
        self.noteTitle = noteTitle
        self.vaultRoot = vaultRoot
        self.service = service
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
            .animation(contentAnimation, value: isLoading)
            .animation(contentAnimation, value: versions.isEmpty)
            .navigationTitle(String(localized: "Version History", bundle: .module))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done", bundle: .module)) { dismiss() }
                }
            }
            .task { await loadVersions() }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 500)
        #endif
    }

    // MARK: - Animation Helpers

    /// Content transition animation — respects Reduce Motion preference.
    private var contentAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.2)
    }

    /// Status/error animation — respects Reduce Motion preference.
    private var statusAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)
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
                    .animation(contentAnimation, value: previewText.isEmpty)

                if let errorMessage {
                    errorBanner(errorMessage)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }

                if selectedVersion != nil {
                    restoreBar
                }
            }
            .animation(statusAnimation, value: errorMessage != nil)
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
            } else if previewText.isEmpty && errorMessage == nil {
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

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                withAnimation(statusAnimation) {
                    errorMessage = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss error", bundle: .module))
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.yellow.opacity(0.1))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "Error: \(message)", bundle: .module))
    }

    // MARK: - Actions

    /// Loads versions off the main thread to prevent frame drops.
    private func loadVersions() async {
        isLoading = true
        errorMessage = nil

        // Move file I/O off main thread
        let loadedVersions = await Task.detached(priority: .userInitiated) { [service, noteURL, vaultRoot] in
            service.fetchVersions(for: noteURL, vaultRoot: vaultRoot)
        }.value

        versions = loadedVersions
        isLoading = false

        if let first = loadedVersions.first {
            selectedVersion = first
            loadPreview(for: first)
        }
    }

    /// Loads preview text off the main thread with bounded size.
    private func loadPreview(for version: NoteVersion) {
        previewText = ""
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [service] in
            do {
                // Uses bounded read (512KB max) to prevent OOM on large files
                let text = try service.readText(from: version)
                await MainActor.run { previewText = text }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Restores the selected version with full validation.
    private func restoreSelectedVersion() {
        guard let version = selectedVersion, !isRestoring else { return }

        // Pre-validate files exist before starting restore
        let fm = FileManager.default

        guard fm.fileExists(atPath: version.snapshotURL.path(percentEncoded: false)) else {
            errorMessage = String(localized: "Version snapshot no longer exists.", bundle: .module)
            // Remove stale version from list
            versions.removeAll { $0.id == version.id }
            selectedVersion = versions.first
            if let newSelection = selectedVersion {
                loadPreview(for: newSelection)
            }
            return
        }

        guard fm.fileExists(atPath: noteURL.path(percentEncoded: false)) else {
            errorMessage = String(localized: "Original note was deleted.", bundle: .module)
            return
        }

        isRestoring = true
        errorMessage = nil

        Task {
            do {
                try await service.restore(version: version, to: noteURL)
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
