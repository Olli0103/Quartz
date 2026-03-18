#if canImport(UIKit) || canImport(AppKit)
import Foundation

/// Sync status of a file in iCloud Drive.
public enum CloudSyncStatus: String, Sendable {
    case current        // Local and cloud are in sync
    case uploading      // Currently uploading
    case downloading    // Currently downloading
    case notDownloaded  // Only in the cloud, not local
    case conflict       // Unresolved sync conflict
    case error          // Sync error
    case notApplicable  // Not an iCloud vault
}

/// Service for iCloud Drive sync monitoring and coordinated writing.
///
/// Uses `NSMetadataQuery` for sync status and `NSFileCoordinator`
/// for conflict-free reading/writing.
public actor CloudSyncService {
    private var metadataQuery: NSMetadataQuery?

    public init() {}

    // MARK: - Sync Status Monitoring

    /// Starts monitoring the sync status for a vault.
    /// Returns an empty stream if iCloud is not available.
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

    /// Stops sync monitoring.
    public func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
    }

    // MARK: - Coordinated File Access

    /// Reads a file using coordination (safe during iCloud sync).
    /// Dispatched off-actor to avoid blocking other actor calls during I/O.
    public func coordinatedRead(at url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var readError: NSError?
                var data: Data?
                var coordinatorError: NSError?

                let coordinator = NSFileCoordinator()
                coordinator.coordinate(
                    readingItemAt: url,
                    options: [],
                    error: &coordinatorError
                ) { actualURL in
                    do {
                        data = try Data(contentsOf: actualURL)
                    } catch {
                        readError = error as NSError
                    }
                }

                if let error = coordinatorError ?? readError {
                    continuation.resume(throwing: error)
                } else if let result = data {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: CloudSyncError.readFailed(url))
                }
            }
        }
    }

    /// Writes a file using coordination (conflict-free during iCloud sync).
    /// Dispatched off-actor to avoid blocking other actor calls during I/O.
    public func coordinatedWrite(data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var writeError: NSError?
                var coordinatorError: NSError?

                let coordinator = NSFileCoordinator()
                coordinator.coordinate(
                    writingItemAt: url,
                    options: .forReplacing,
                    error: &coordinatorError
                ) { actualURL in
                    do {
                        try data.write(to: actualURL, options: .atomic)
                    } catch {
                        writeError = error as NSError
                    }
                }

                if let error = coordinatorError ?? writeError {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Download on Demand

    /// Requests the download of a cloud-only file.
    public func startDownloading(at url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: - Conflict Resolution

    /// Returns conflict versions for a file, if any exist.
    public nonisolated func conflictVersions(for url: URL) -> [NSFileVersion] {
        NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
    }

    /// Resolves a conflict by keeping the current local version.
    /// Removes all conflict versions and marks them as resolved.
    /// Uses file coordination to prevent races with iCloud sync.
    public nonisolated func resolveConflictKeepingCurrent(at url: URL) throws {
        var coordinatorError: NSError?
        var resolveError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &coordinatorError) { actualURL in
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: actualURL) ?? []
            for version in conflicts {
                version.isResolved = true
            }
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

    // MARK: - Ubiquity Container

    /// Returns the iCloud Drive URL for the app (if available).
    public static func ubiquityContainerURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appending(path: "Documents")
    }

    /// Checks whether iCloud Drive is available.
    public static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
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

// MARK: - Errors

public enum CloudSyncError: LocalizedError, Sendable {
    case readFailed(URL)
    case writeFailed(URL)
    case notAvailable

    public var errorDescription: String? {
        switch self {
        case .readFailed(let url):
            String(localized: "Failed to read from iCloud: \(url.lastPathComponent)", bundle: .module)
        case .writeFailed(let url):
            String(localized: "Failed to write to iCloud: \(url.lastPathComponent)", bundle: .module)
        case .notAvailable:
            String(localized: "iCloud Drive is not available", bundle: .module)
        }
    }
}
#endif
