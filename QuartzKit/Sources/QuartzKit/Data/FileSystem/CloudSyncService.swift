#if canImport(UIKit) || canImport(AppKit)
import Foundation

/// Sync-Status einer Datei in iCloud Drive.
public enum CloudSyncStatus: String, Sendable {
    case current        // Lokal und in der Cloud synchron
    case uploading      // Wird hochgeladen
    case downloading    // Wird heruntergeladen
    case notDownloaded  // Nur in der Cloud, nicht lokal
    case error          // Sync-Fehler
    case notApplicable  // Kein iCloud-Vault
}

/// Service für iCloud Drive Sync-Monitoring und koordiniertes Schreiben.
///
/// Nutzt `NSMetadataQuery` für Sync-Status und `NSFileCoordinator`
/// für konfliktfreies Lesen/Schreiben.
public actor CloudSyncService {
    private var metadataQuery: NSMetadataQuery?

    public init() {}

    // MARK: - Sync Status Monitoring

    /// Startet das Monitoring des Sync-Status für einen Vault.
    public func startMonitoring(vaultRoot: URL) -> AsyncStream<(URL, CloudSyncStatus)> {
        AsyncStream { continuation in
            let query = NSMetadataQuery()
            query.searchScopes = [vaultRoot]
            query.predicate = NSPredicate(format: "%K LIKE '*.md'", NSMetadataItemPathKey)

            let center = NotificationCenter.default

            // Initial results
            nonisolated(unsafe) let initialObserver = center.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self] notification in
                guard let query = notification.object as? NSMetadataQuery else { return }
                query.disableUpdates()
                self?.processQueryResults(query, continuation: continuation)
                query.enableUpdates()
            }

            // Updates
            nonisolated(unsafe) let updateObserver = center.addObserver(
                forName: .NSMetadataQueryDidUpdate,
                object: query,
                queue: .main
            ) { [weak self] notification in
                guard let query = notification.object as? NSMetadataQuery else { return }
                query.disableUpdates()
                self?.processQueryResults(query, continuation: continuation)
                query.enableUpdates()
            }

            nonisolated(unsafe) let queryRef = query
            continuation.onTermination = { @Sendable _ in
                queryRef.stop()
                center.removeObserver(initialObserver)
                center.removeObserver(updateObserver)
            }

            self.metadataQuery = query
            query.start()
        }
    }

    /// Stoppt das Sync-Monitoring.
    public func stopMonitoring() {
        metadataQuery?.stop()
        metadataQuery = nil
    }

    // MARK: - Coordinated File Access

    /// Liest eine Datei koordiniert (sicher bei iCloud-Sync).
    public func coordinatedRead(at url: URL) throws -> Data {
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
            throw error
        }

        guard let result = data else {
            throw CloudSyncError.readFailed(url)
        }
        return result
    }

    /// Schreibt eine Datei koordiniert (konfliktfrei bei iCloud-Sync).
    public func coordinatedWrite(data: Data, to url: URL) throws {
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
            throw error
        }
    }

    // MARK: - Download on Demand

    /// Fordert den Download einer Cloud-only Datei an.
    public func startDownloading(at url: URL) throws {
        try FileManager.default.startDownloadingUbiquitousItem(at: url)
    }

    // MARK: - Ubiquity Container

    /// Gibt die iCloud Drive URL für die App zurück (falls verfügbar).
    public static func ubiquityContainerURL() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appending(path: "Documents")
    }

    /// Prüft ob iCloud Drive verfügbar ist.
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
        let hasError = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingErrorKey) != nil ||
            item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) != nil

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
