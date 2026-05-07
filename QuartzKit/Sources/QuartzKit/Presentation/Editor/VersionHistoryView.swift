import SwiftUI

@MainActor
public final class VersionHistoryViewModel {
    public private(set) var versions: [NoteVersion] = []
    public private(set) var lookupStatus: VersionHistoryLookupStatus?
    public private(set) var isLoading = true

    private let noteURL: URL
    private let vaultRoot: URL
    private let lookupProvider: @Sendable (URL, URL) async -> (versions: [NoteVersion], status: VersionHistoryLookupStatus)
    private var lookupGeneration: UInt64 = 0

    public convenience init(noteURL: URL, vaultRoot: URL, service: VersionHistoryService = VersionHistoryService()) {
        self.init(noteURL: noteURL, vaultRoot: vaultRoot) { noteURL, vaultRoot in
            await Task.detached(priority: .userInitiated) {
                service.fetchVersionsWithStatus(for: noteURL, vaultRoot: vaultRoot)
            }.value
        }
    }

    init(
        noteURL: URL,
        vaultRoot: URL,
        lookupProvider: @escaping @Sendable (URL, URL) async -> (versions: [NoteVersion], status: VersionHistoryLookupStatus)
    ) {
        self.noteURL = noteURL
        self.vaultRoot = vaultRoot
        self.lookupProvider = lookupProvider
    }

    @discardableResult
    public func loadVersions() async -> Bool {
        lookupGeneration &+= 1
        let generation = lookupGeneration
        isLoading = true
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "versionUI.lookupStarted",
            reasonCode: "versionUI.lookupStarted",
            noteBasename: noteURL.lastPathComponent,
            generation: generation,
            metadata: [
                "versionUI.currentNoteIdentity": noteURL.lastPathComponent,
                "versionUI.rawIdentityAtOpen": noteURL.lastPathComponent,
                "versionUI.serviceMethod": "fetchVersionsWithStatus"
            ]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "versionUI.lookupGenerationStarted",
            reasonCode: "versionUI.lookupGenerationStarted",
            noteBasename: noteURL.lastPathComponent,
            generation: generation
        )

        var lookup = await lookupProvider(noteURL, vaultRoot)
        guard generation == lookupGeneration else {
            recordStaleLookupIgnored(generation: generation, status: lookup.status)
            return false
        }

        let postCreateVerified = await hasPostCreateVerification(for: lookup.status.versionLookupKey)
        if lookup.versions.isEmpty, postCreateVerified {
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .versionHistory,
                name: "versionUI.postCreateVerifiedButUIEmpty",
                reasonCode: "versionUI.postCreateVerifiedButUIEmpty",
                noteBasename: noteURL.lastPathComponent,
                generation: generation,
                metadata: [
                    "versionUI.lookupKey": lookup.status.versionLookupKey,
                    "versionUI.emptyStateReason": "postCreateVerifiedButInitialUILookupEmpty"
                ]
            )
        }

        if lookup.versions.isEmpty {
            try? await Task.sleep(for: .milliseconds(75))
            let retry = await lookupProvider(noteURL, vaultRoot)
            guard generation == lookupGeneration else {
                recordStaleLookupIgnored(generation: generation, status: retry.status)
                return false
            }
            if retry.versions.count > lookup.versions.count {
                lookup = retry
                SubsystemDiagnostics.record(
                    level: .info,
                    subsystem: .versionHistory,
                    name: "versionUI.cacheInvalidatedForSnapshotCreated",
                    reasonCode: "versionUI.cacheInvalidatedForSnapshotCreated",
                    noteBasename: noteURL.lastPathComponent,
                    counts: ["versionUI.serviceReturnedCount": retry.versions.count],
                    generation: generation,
                    metadata: ["versionUI.lookupKey": retry.status.versionLookupKey]
                )
            }
        }

        versions = lookup.versions
        lookupStatus = lookup.status
        isLoading = false
        recordLookupCompleted(lookup: lookup, generation: generation)
        return true
    }

    private func recordStaleLookupIgnored(generation: UInt64, status: VersionHistoryLookupStatus) {
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "versionUI.lookupGenerationIgnoredStale",
            reasonCode: "versionUI.lookupGenerationIgnoredStale",
            noteBasename: noteURL.lastPathComponent,
            generation: generation,
            metadata: [
                "versionUI.lookupKey": status.versionLookupKey,
                "latestGeneration": "\(lookupGeneration)"
            ]
        )
    }

    private func recordLookupCompleted(
        lookup: (versions: [NoteVersion], status: VersionHistoryLookupStatus),
        generation: UInt64
    ) {
        let snapshotIDs = lookup.versions.map { "\($0.id)" }.joined(separator: ",")
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "versionUI.usedCanonicalLookupKey",
            reasonCode: "versionUI.usedCanonicalLookupKey",
            noteBasename: noteURL.lastPathComponent,
            generation: generation,
            metadata: [
                "versionUI.rawIdentityAtOpen": noteURL.lastPathComponent,
                "versionUI.canonicalIdentityAtLookup": lookup.status.currentNoteIdentity,
                "versionUI.lookupKey": lookup.status.versionLookupKey
            ]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "versionUI.lookupCompleted",
            reasonCode: "versionUI.lookupCompleted",
            noteBasename: noteURL.lastPathComponent,
            counts: [
                "versionUI.serviceReturnedCount": lookup.versions.count,
                "versionUI.snapshotRowsDisplayed": versions.count,
                "versionUI.rowsAfterFiltering": versions.count
            ],
            generation: generation,
            metadata: [
                "versionUI.currentNoteIdentity": lookup.status.currentNoteIdentity,
                "versionUI.lookupKey": lookup.status.versionLookupKey,
                "versionUI.emptyStateReason": lookup.versions.isEmpty ? "serviceReturnedZeroSnapshots" : "none",
                "versionUI.serviceReturnedSnapshotIDs": snapshotIDs
            ]
        )
        SubsystemDiagnostics.record(
            level: .info,
            subsystem: .versionHistory,
            name: "versionUI.lookupGenerationCompleted",
            reasonCode: "versionUI.lookupGenerationCompleted",
            noteBasename: noteURL.lastPathComponent,
            counts: ["versionUI.snapshotRowsDisplayed": versions.count],
            generation: generation,
            metadata: ["versionUI.lookupKey": lookup.status.versionLookupKey]
        )
        if (lookup.versions.count > 0 || lookup.status.snapshotFilesFound > 0), versions.isEmpty {
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .versionHistory,
                name: "versionUI.serviceUIStateMismatch",
                reasonCode: "versionUI.serviceUIStateMismatch",
                noteBasename: noteURL.lastPathComponent,
                counts: [
                    "versionUI.serviceReturnedCount": lookup.versions.count,
                    "versionUI.snapshotRowsDisplayed": versions.count,
                    "versionUI.snapshotFilesFound": lookup.status.snapshotFilesFound
                ],
                generation: generation,
                metadata: [
                    "versionUI.currentNoteIdentity": lookup.status.currentNoteIdentity,
                    "versionUI.lookupKey": lookup.status.versionLookupKey
                ]
            )
        }
    }

    private func hasPostCreateVerification(for lookupKey: String) async -> Bool {
        let snapshot = await SubsystemDiagnostics.snapshot()
        let events = snapshot.eventsBySubsystem[.versionHistory] ?? []
        return events.contains { event in
            event.name.hasPrefix("version.snapshotLookupPostCreateVerified")
                && event.metadata["versionLookupKey"] == lookupKey
        }
    }
}

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
    @State private var selectedVersionID: Int?
    @State private var previewText: String = ""
    @State private var isLoading = true
    @State private var isRestoring = false
    @State private var errorMessage: String?
    @State private var lookupStatus: VersionHistoryLookupStatus?
    @State private var viewModel: VersionHistoryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedVersion: NoteVersion? {
        guard let id = selectedVersionID else { return nil }
        return versions.first { $0.id == id }
    }

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
        _viewModel = State(initialValue: VersionHistoryViewModel(noteURL: noteURL, vaultRoot: vaultRoot, service: service))
    }

    public var body: some View {
        NavigationStack {
            content
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
                .onReceive(NotificationCenter.default.publisher(for: .quartzVersionHistoryDidChange)) { notification in
                    guard let changedNoteURL = notification.object as? URL,
                          changedNoteURL.standardizedFileURL == noteURL.standardizedFileURL,
                          let changedVaultRoot = notification.userInfo?["vaultRoot"] as? URL,
                          changedVaultRoot.standardizedFileURL == vaultRoot.standardizedFileURL else {
                        return
                    }
                    Task { await loadVersions() }
                }
        }
        #if os(macOS)
        .frame(minWidth: 700, minHeight: 500)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView(String(localized: "Loading versions\u{2026}", bundle: .module))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if versions.isEmpty {
            emptyState
        } else {
            splitContent
        }
    }

    // MARK: - Split Content

    private var splitContent: some View {
        HStack(spacing: 0) {
            timeline
                .frame(width: 240)

            Divider()

            previewPane
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

            List(versions, selection: $selectedVersionID) { version in
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
            .onChange(of: selectedVersionID) { _, newID in
                if let id = newID, let version = versions.first(where: { $0.id == id }) {
                    loadPreview(for: version)
                }
            }
        }
    }

    // MARK: - Preview Pane

    private var previewPane: some View {
        VStack(spacing: 0) {
            previewContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let errorMessage {
                errorBanner(errorMessage)
            }

            if selectedVersion != nil {
                restoreBar
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
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
            if let lookupStatus {
                Text(String(localized: "No versions found for note identity \(lookupStatus.currentNoteIdentity)", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                    .frame(maxWidth: 420)
                Text(lookupStatus.versionLookupKey)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
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
                errorMessage = nil
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

    private func loadVersions() async {
        errorMessage = nil
        isLoading = true
        guard await viewModel.loadVersions() else { return }
        versions = viewModel.versions
        lookupStatus = viewModel.lookupStatus
        isLoading = viewModel.isLoading

        if let first = versions.first {
            selectedVersionID = first.id
            loadPreview(for: first)
        } else {
            selectedVersionID = nil
            previewText = ""
        }
    }

    private func loadPreview(for version: NoteVersion) {
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [service] in
            do {
                let text = try service.readText(from: version)
                await MainActor.run {
                    previewText = text
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func restoreSelectedVersion() {
        guard let version = selectedVersion, !isRestoring else { return }

        let fm = FileManager.default

        guard fm.fileExists(atPath: version.snapshotURL.path(percentEncoded: false)) else {
            errorMessage = String(localized: "Version snapshot no longer exists.", bundle: .module)
            versions.removeAll { $0.id == version.id }
            selectedVersionID = versions.first?.id
            if let newVersion = selectedVersion {
                loadPreview(for: newVersion)
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
