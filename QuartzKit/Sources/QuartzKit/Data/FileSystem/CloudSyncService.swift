import Foundation

/// Sync status of a file in iCloud Drive.
public enum CloudSyncStatus: String, Sendable {
    case current
    case uploading
    case downloading
    case notDownloaded
    case conflict
    case error
    case notApplicable
}

/// Side-by-side diff state for conflict resolution.
/// Supports visual comparison before choosing a version.
public struct ConflictDiffState: Sendable {
    public let fileURL: URL
    public let localContent: String
    public let cloudContent: String
    public let localModified: Date?
    public let cloudModified: Date?

    public init(fileURL: URL, localContent: String, cloudContent: String, localModified: Date?, cloudModified: Date?) {
        self.fileURL = fileURL
        self.localContent = localContent
        self.cloudContent = cloudContent
        self.localModified = localModified
        self.cloudModified = cloudModified
    }
}

#if canImport(UIKit) || canImport(AppKit)
/// Service for iCloud Drive sync monitoring and coordinated writing.
/// Swift 6 strict concurrency: uses Task.detached for I/O, no blocking DispatchQueue.
public actor CloudSyncService {
    private var metadataQuery: NSMetadataQuery?

    public init() {}

    // MARK: - Sync Status Monitoring

    public func startMonitoring(vaultRoot: URL) -> AsyncStream<(URL, CloudSyncStatus)> {
        guard Self.isAvailable else {
            return AsyncStream { $0.finish() }
        }

        let query = NSMetadataQuery()
        query.searchScopes = [vaultRoot]
        query.predicate = NSPredicate(format: "%K ENDSWITH '.md'", NSMetadataItemFSNameKey)
        self.metadataQuery = query

        return Self.makeMonitoringStream(query: query, service: self)
    }

    private struct UncheckedSendableQuery: @unchecked Sendable {
        let query: NSMetadataQuery
    }

    private nonisolated static func makeMonitoringStream(
        query: NSMetadataQuery,
        service: CloudSyncService
    ) -> AsyncStream<(URL, CloudSyncStatus)> {
        let wrapped = UncheckedSendableQuery(query: query)

        return AsyncStream { continuation in
            let center = NotificationCenter.default

            let gatherTask = Task {
                for await notification in center.notifications(named: .NSMetadataQueryDidFinishGathering, object: wrapped.query) {
                    guard let metaQuery = notification.object as? NSMetadataQuery else { continue }
                    metaQuery.disableUpdates()
                    service.processQueryResults(metaQuery, continuation: continuation)
                    metaQuery.enableUpdates()
                }
            }

            let updateTask = Task {
                for await notification in center.notifications(named: .NSMetadataQueryDidUpdate, object: wrapped.query) {
                    guard let metaQuery = notification.object as? NSMetadataQuery else { continue }
                    metaQuery.disableUpdates()
                    service.processQueryResults(metaQuery, continuation: continuation)
                    metaQuery.enableUpdates()
                }
            }

            continuation.onTermination = { @Sendable _ in
                gatherTask.cancel()
                updateTask.cancel()
                Task { @MainActor in
                    wrapped.query.stop()
                }
            }

            Task { @MainActor in
                wrapped.query.start()
            }
        }
    }

    public func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
    }

    // MARK: - Coordinated File Access (delegates to CoordinatedFileWriter)

    /// Reads a file using NSFileCoordinator via the centralized CoordinatedFileWriter.
    public func coordinatedRead(at url: URL, filePresenter: NSFilePresenter? = nil) async throws -> Data {
        let wrappedPresenter = filePresenter.map { UncheckedSendablePresenter($0) }
        return try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileWriter.shared.read(from: url, filePresenter: wrappedPresenter?.value)
        }.value
    }

    /// Writes a file using NSFileCoordinator via the centralized CoordinatedFileWriter.
    public func coordinatedWrite(data: Data, to url: URL, filePresenter: NSFilePresenter? = nil) async throws {
        let wrappedPresenter = filePresenter.map { UncheckedSendablePresenter($0) }
        try await Task.detached(priority: .userInitiated) {
            try CoordinatedFileWriter.shared.write(data, to: url, filePresenter: wrappedPresenter?.value)
        }.value
    }

    // MARK: - Download on Demand

    public func startDownloading(at url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: - Conflict Resolution & Diff State

    public nonisolated func conflictVersions(for url: URL) -> [NSFileVersion] {
        NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
    }

    /// Builds a side-by-side diff state for the conflict resolver UI.
    public func buildConflictDiffState(for url: URL) async throws -> ConflictDiffState? {
        let conflicts = conflictVersions(for: url)
        guard !conflicts.isEmpty else { return nil }

        let localData = try? await coordinatedRead(at: url)
        let localContent = localData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let localVersion = NSFileVersion.currentVersionOfItem(at: url)
        let localModified = localVersion?.modificationDate

        guard let cloudVersion = conflicts.first else {
            return ConflictDiffState(fileURL: url, localContent: localContent, cloudContent: "", localModified: localModified, cloudModified: nil)
        }

        let cloudURL = cloudVersion.url
        let cloudData = try? await coordinatedRead(at: cloudURL)
        let cloudContent = cloudData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let cloudModified = cloudVersion.modificationDate

        return ConflictDiffState(
            fileURL: url,
            localContent: localContent,
            cloudContent: cloudContent,
            localModified: localModified,
            cloudModified: cloudModified
        )
    }

    // MARK: - Transactional Conflict Resolution

    /// Keeps the local version, marks all conflict versions as resolved.
    /// **Transactional**: coordination + resolve happen in a single coordinator block.
    /// - Parameter filePresenter: The presenter for this file. Passing it prevents
    ///   self-coordination deadlock (Apple TN3151).
    public nonisolated func resolveKeepingLocal(at url: URL, filePresenter: NSFilePresenter? = nil) throws {
        var coordinatorError: NSError?
        var resolveError: Error?

        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { actualURL in
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: actualURL) ?? []
            for v in conflicts { v.isResolved = true }
            do {
                try NSFileVersion.removeOtherVersionsOfItem(at: actualURL)
            } catch {
                resolveError = error
            }
        }

        if let error = coordinatorError ?? resolveError {
            throw error
        }
    }

    /// Replaces local content with the iCloud version, then marks all conflicts resolved.
    /// **Transactional**: write + resolve in a single coordinator block.
    public nonisolated func resolveKeepingCloud(at url: URL, filePresenter: NSFilePresenter? = nil) throws {
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        guard let cloudVersion = conflicts.first else {
            throw CloudSyncError.conflictResolutionFailed
        }

        var coordinatorError: NSError?
        var resolveError: Error?

        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { actualURL in
            do {
                try cloudVersion.replaceItem(at: actualURL, options: [])
                let remaining = NSFileVersion.unresolvedConflictVersionsOfItem(at: actualURL) ?? []
                for v in remaining { v.isResolved = true }
                try NSFileVersion.removeOtherVersionsOfItem(at: actualURL)
            } catch {
                resolveError = error
            }
        }

        if let error = coordinatorError ?? resolveError {
            throw error
        }
    }

    /// Keeps both versions: renames the conflict file to a sibling note so no data is lost.
    /// The conflict version becomes `[Original Title] (iCloud Conflict).md`.
    /// Marks all conflicts as resolved after branching.
    public func resolveKeepingBoth(at url: URL) async throws {
        let conflicts = conflictVersions(for: url)
        guard let cloudVersion = conflicts.first else {
            throw CloudSyncError.conflictResolutionFailed
        }

        // Read the cloud version's content
        let cloudData = try await coordinatedRead(at: cloudVersion.url)

        // Compute the sibling filename
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let parentDir = url.deletingLastPathComponent()
        let conflictName = "\(baseName) (iCloud Conflict).\(ext)"
        var conflictURL = parentDir.appending(path: conflictName)

        // Avoid overwriting existing conflict files
        var counter = 2
        while FileManager.default.fileExists(atPath: conflictURL.path(percentEncoded: false)) {
            let numberedName = "\(baseName) (iCloud Conflict \(counter)).\(ext)"
            conflictURL = parentDir.appending(path: numberedName)
            counter += 1
        }

        // Write the cloud content as a new file
        try await coordinatedWrite(data: cloudData, to: conflictURL)

        // Mark all conflicts resolved
        try resolveKeepingLocal(at: url)

        // Notify the app that a conflict was branched
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzSyncConflictBranched,
                object: nil,
                userInfo: ["originalURL": url, "conflictURL": conflictURL]
            )
        }
    }

    /// Writes merged content, then marks all conflicts resolved.
    /// **Transactional**: write + resolve in a single coordinator block.
    public func resolveWritingMerged(at url: URL, mergedUTF8: String, filePresenter: NSFilePresenter? = nil) async throws {
        let data = Data(mergedUTF8.utf8)
        nonisolated(unsafe) let presenter = filePresenter

        try await Task.detached(priority: .userInitiated) {
            var coordinatorError: NSError?
            var resolveError: Error?

            let coordinator = NSFileCoordinator(filePresenter: presenter)
            coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { actualURL in
                do {
                    try data.write(to: actualURL, options: .atomic)
                    let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: actualURL) ?? []
                    for v in conflicts { v.isResolved = true }
                    try NSFileVersion.removeOtherVersionsOfItem(at: actualURL)
                } catch {
                    resolveError = error
                }
            }

            if let error = coordinatorError ?? resolveError {
                throw error
            }
        }.value
    }

    // MARK: - Legacy Resolution (deprecated, kept for backward compatibility)

    @available(*, deprecated, renamed: "resolveKeepingLocal(at:)")
    public nonisolated func resolveConflictKeepingCurrent(at url: URL) throws {
        try resolveKeepingLocal(at: url)
    }

    @available(*, deprecated, renamed: "resolveKeepingCloud(at:)")
    public nonisolated func resolveConflictKeepingCloud(at url: URL) throws {
        let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        guard let cloudVersion = conflicts.first else {
            throw CloudSyncError.conflictResolutionFailed
        }
        try resolveConflictKeepingVersion(at: url, version: cloudVersion)
    }

    @available(*, deprecated, renamed: "resolveWritingMerged(at:mergedUTF8:)")
    public func resolveConflictWritingMergedContent(at url: URL, mergedUTF8: String) async throws {
        try await resolveWritingMerged(at: url, mergedUTF8: mergedUTF8)
    }

    public nonisolated func resolveConflictKeepingVersion(at url: URL, version: NSFileVersion?, filePresenter: NSFilePresenter? = nil) throws {
        var coordinatorError: NSError?
        var resolveError: Error?

        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { actualURL in
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: actualURL) ?? []
            for v in conflicts {
                v.isResolved = true
            }
            do {
                if let version {
                    try version.replaceItem(at: actualURL, options: [])
                }
                try NSFileVersion.removeOtherVersionsOfItem(at: actualURL)
            } catch {
                resolveError = error
            }
        }

        if let error = coordinatorError ?? resolveError {
            throw error
        }
    }

    // MARK: - Ubiquity Container

    /// The app-owned iCloud ubiquity container identifier.
    public static let containerIdentifier = "iCloud.olli.QuartzNotes"

    /// Returns the Documents directory inside the app's iCloud ubiquity container.
    ///
    /// **Must be called from a background thread.** The first call may block while
    /// the system creates the container directory structure.
    public static func ubiquityContainerURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier)?
            .appending(path: "Documents")
    }

    /// Whether the user is signed in to iCloud (checks identity token).
    /// This is safe to call from the main thread.
    public static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// Resolves the ubiquity container URL on a background thread.
    /// Returns `nil` if iCloud is unavailable or the container can't be created.
    public static func resolveContainerURL() async -> URL? {
        guard isAvailable else { return nil }
        return await Task.detached(priority: .userInitiated) {
            ubiquityContainerURL()
        }.value
    }

    // MARK: - Private

    private nonisolated func processQueryResults(
        _ query: NSMetadataQuery,
        continuation: AsyncStream<(URL, CloudSyncStatus)>.Continuation
    ) {
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            guard let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }

            let url = URL(filePath: path)
            let status = syncStatus(for: item)
            continuation.yield((url, status))
        }
    }

    private nonisolated func syncStatus(for item: NSMetadataItem) -> CloudSyncStatus {
        let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
        let isUploading = item.value(forAttribute: NSMetadataUbiquitousItemIsUploadingKey) as? Bool ?? false
        let isDownloading = item.value(forAttribute: NSMetadataUbiquitousItemIsDownloadingKey) as? Bool ?? false
        let hasConflict = item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool ?? false
        let hasError = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) != nil ||
            item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) != nil

        if hasConflict { return .conflict }
        if hasError { return .error }
        if isUploading { return .uploading }
        if isDownloading { return .downloading }

        switch downloadStatus {
        case NSMetadataUbiquitousItemDownloadingStatusCurrent:
            return .current
        case NSMetadataUbiquitousItemDownloadingStatusNotDownloaded:
            return .notDownloaded
        case NSMetadataUbiquitousItemDownloadingStatusDownloaded:
            return .current
        default:
            return .notApplicable
        }
    }
}

/// Wrapper to pass NSFilePresenter across Sendable boundaries safely.
/// NSFilePresenter is an @objc protocol and not Sendable, but we only
/// pass it to NSFileCoordinator(filePresenter:) which is thread-safe.
private struct UncheckedSendablePresenter: @unchecked Sendable {
    let value: NSFilePresenter
    init(_ value: NSFilePresenter) { self.value = value }
}

// MARK: - Errors

public enum CloudSyncError: LocalizedError, Sendable {
    case readFailed(URL)
    case writeFailed(URL)
    case notAvailable
    case conflictResolutionFailed

    public var errorDescription: String? {
        switch self {
        case .readFailed(let url):
            String(localized: "Failed to read from iCloud: \(url.lastPathComponent)", bundle: .module)
        case .writeFailed(let url):
            String(localized: "Failed to write to iCloud: \(url.lastPathComponent)", bundle: .module)
        case .notAvailable:
            String(localized: "iCloud Drive is not available", bundle: .module)
        case .conflictResolutionFailed:
            String(localized: "Could not resolve sync conflict.", bundle: .module)
        }
    }
}
#endif

// MARK: - Conflict Notifications

public extension Notification.Name {
    /// Posted when a sync conflict is resolved by branching (Keep Both).
    /// `userInfo` contains `"originalURL": URL` and `"conflictURL": URL`.
    static let quartzSyncConflictBranched = Notification.Name("quartzSyncConflictBranched")

    /// Posted when a sync conflict is detected during monitoring.
    /// `object` is the conflicted file URL.
    static let quartzSyncConflictDetected = Notification.Name("quartzSyncConflictDetected")
}
