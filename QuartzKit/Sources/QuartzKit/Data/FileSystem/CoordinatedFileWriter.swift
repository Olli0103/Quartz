import Foundation

private final class CoordinatedWriteState: @unchecked Sendable {
    private let lock = NSLock()
    private var timedOut = false
    private var completed = false
    private var coordinatorError: NSError?
    private var writeError: NSError?

    var didComplete: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    var error: NSError? {
        lock.lock()
        defer { lock.unlock() }
        return coordinatorError ?? writeError
    }

    func shouldProceedWithWrite() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !timedOut
    }

    func markCompleted() {
        lock.lock()
        completed = true
        lock.unlock()
    }

    func markTimedOut() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    func recordCoordinatorError(_ error: NSError?) {
        lock.lock()
        coordinatorError = error
        lock.unlock()
    }

    func recordWriteError(_ error: NSError) {
        lock.lock()
        writeError = error
        lock.unlock()
    }
}

private struct SendableFileCoordinator: @unchecked Sendable {
    let value: NSFileCoordinator
}

/// Centralized, iCloud-safe file writer.
///
/// Wraps `NSFileCoordinator` for conflict-free writing to iCloud Drive Vaults.
/// All services that write files to the vault MUST use this writer
/// to prevent data loss from sync conflicts.
public struct CoordinatedFileWriter: Sendable {
    public static let shared = CoordinatedFileWriter()

    /// Default timeout for coordinated operations (10 seconds).
    /// iCloud coordination should not take longer than this in normal conditions.
    public static let defaultTimeout: TimeInterval = 10.0

    public init() {}

    /// Reads data from a URL in a coordinated manner.
    ///
    /// - Parameters:
    ///   - url: The file URL to read from.
    ///   - filePresenter: The NSFilePresenter presenting this file, if any.
    ///     Passing the presenter prevents the coordinator from sending
    ///     callbacks to our own presenter, which could cause a deadlock.
    public func read(from url: URL, filePresenter: NSFilePresenter? = nil) throws -> Data {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        let started = Date()
        SubsystemDiagnostics.record(
            level: .debug,
            subsystem: .fileCoordination,
            name: "coordinatedReadStarted",
            noteBasename: canonicalURL.lastPathComponent,
            metadata: ["url": canonicalURL.path(percentEncoded: false)],
            verbose: true
        )
        var coordinatorError: NSError?
        var readError: NSError?
        var result: Data?

        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(
            readingItemAt: canonicalURL,
            options: [],
            error: &coordinatorError
        ) { actualURL in
            do {
                result = try Data(contentsOf: actualURL)
            } catch {
                readError = error as NSError
            }
        }

        if let error = coordinatorError ?? readError {
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .fileCoordination,
                name: "coordinatedReadFailed",
                reasonCode: "fileCoordination.readFailed",
                noteBasename: canonicalURL.lastPathComponent,
                durationMs: Date().timeIntervalSince(started) * 1_000,
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }

        guard let data = result else {
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .fileCoordination,
                name: "coordinatedReadFailed",
                reasonCode: "fileCoordination.emptyResult",
                noteBasename: canonicalURL.lastPathComponent,
                durationMs: Date().timeIntervalSince(started) * 1_000
            )
            throw CocoaError(.fileReadUnknown)
        }
        SubsystemDiagnostics.record(
            level: .debug,
            subsystem: .fileCoordination,
            name: "coordinatedReadFinished",
            noteBasename: canonicalURL.lastPathComponent,
            durationMs: Date().timeIntervalSince(started) * 1_000,
            counts: ["bytes": data.count],
            verbose: true
        )
        return data
    }

    /// Reads file contents as text (UTF-8 by default) using coordinated access.
    public func readString(from url: URL, encoding: String.Encoding = .utf8, filePresenter: NSFilePresenter? = nil) throws -> String {
        let data = try read(from: url, filePresenter: filePresenter)
        guard let text = String(data: data, encoding: encoding) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return text
    }

    /// Writes data to a URL in a coordinated manner with timeout protection.
    ///
    /// Uses `NSFileCoordinator` to ensure that iCloud Drive
    /// does not interrupt or overwrite the write operation.
    ///
    /// - Parameters:
    ///   - data: The data to write.
    ///   - url: The destination URL.
    ///   - timeout: Maximum wait time for coordination (default 10s).
    ///   - filePresenter: The NSFilePresenter presenting this file, if any.
    ///     **Critical for iCloud**: passing the presenter prevents the coordinator
    ///     from calling `savePresentedItemChanges` back on our own presenter,
    ///     which would cause a self-coordination deadlock (Apple TN3151).
    public func write(_ data: Data, to url: URL, timeout: TimeInterval = defaultTimeout,
                      filePresenter: NSFilePresenter? = nil) throws {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        let state = CoordinatedWriteState()
        let started = Date()
        SubsystemDiagnostics.record(
            level: .debug,
            subsystem: .fileCoordination,
            name: "coordinatedWriteStarted",
            noteBasename: canonicalURL.lastPathComponent,
            counts: ["bytes": data.count],
            metadata: ["url": canonicalURL.path(percentEncoded: false)],
            verbose: true
        )

        let coordinator = SendableFileCoordinator(value: NSFileCoordinator(filePresenter: filePresenter))

        // Use a semaphore to implement timeout
        let semaphore = DispatchSemaphore(value: 0)

        // Run coordination on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            var coordinatorError: NSError?
            coordinator.value.coordinate(
                writingItemAt: canonicalURL,
                options: .forReplacing,
                error: &coordinatorError
            ) { actualURL in
                guard state.shouldProceedWithWrite() else {
                    return
                }
                do {
                    try data.write(to: actualURL, options: .atomic)
                    state.markCompleted()
                } catch {
                    state.recordWriteError(error as NSError)
                }
            }
            state.recordCoordinatorError(coordinatorError)
            semaphore.signal()
        }

        // Wait with timeout
        let result = semaphore.wait(timeout: .now() + timeout)

        if result == .timedOut {
            // Cancel the coordination if it's taking too long
            state.markTimedOut()
            coordinator.value.cancel()
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .fileCoordination,
                name: "coordinatedWriteTimeout",
                reasonCode: "save.coordinationTimeout",
                noteBasename: canonicalURL.lastPathComponent,
                durationMs: Date().timeIntervalSince(started) * 1_000,
                metadata: [
                    "timeoutSeconds": String(timeout),
                    "recoveryAction": "coordinationCancelled"
                ]
            )
            throw CoordinatedFileWriterError.timeout(url: canonicalURL, timeout: timeout)
        }

        if let error = state.error {
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .fileCoordination,
                name: "coordinatedWriteFailed",
                reasonCode: "fileCoordination.writeFailed",
                noteBasename: canonicalURL.lastPathComponent,
                durationMs: Date().timeIntervalSince(started) * 1_000,
                metadata: ["error": error.localizedDescription]
            )
            throw error
        }

        if !state.didComplete {
            SubsystemDiagnostics.record(
                level: .error,
                subsystem: .fileCoordination,
                name: "coordinatedWriteFailed",
                reasonCode: "fileCoordination.unknownFailure",
                noteBasename: canonicalURL.lastPathComponent,
                durationMs: Date().timeIntervalSince(started) * 1_000
            )
            throw CoordinatedFileWriterError.unknownFailure(url: canonicalURL)
        }
        SubsystemDiagnostics.record(
            level: .debug,
            subsystem: .fileCoordination,
            name: "coordinatedWriteFinished",
            noteBasename: canonicalURL.lastPathComponent,
            durationMs: Date().timeIntervalSince(started) * 1_000,
            counts: ["bytes": data.count],
            verbose: true
        )
    }

    /// Creates a directory in a coordinated manner.
    public func createDirectory(at url: URL, withIntermediateDirectories: Bool = true,
                                filePresenter: NSFilePresenter? = nil) throws {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        var coordinatorError: NSError?
        var writeError: NSError?

        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(
            writingItemAt: canonicalURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { actualURL in
            do {
                try FileManager.default.createDirectory(
                    at: actualURL,
                    withIntermediateDirectories: withIntermediateDirectories
                )
            } catch {
                writeError = error as NSError
            }
        }

        if let error = coordinatorError ?? writeError {
            throw error
        }
    }

    /// Moves a file or directory using coordinated access (iCloud-safe rename / trash moves).
    public func moveItem(from sourceURL: URL, to destinationURL: URL,
                         filePresenter: NSFilePresenter? = nil) throws {
        let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)
        let canonicalDestinationURL = CanonicalNoteIdentity.canonicalFileURL(for: destinationURL)
        var coordinatorError: NSError?
        var moveError: NSError?

        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(
            readingItemAt: canonicalSourceURL,
            options: [],
            writingItemAt: canonicalDestinationURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { actualSource, actualDestination in
            do {
                try FileManager.default.moveItem(at: actualSource, to: actualDestination)
            } catch {
                moveError = error as NSError
            }
        }

        if let error = coordinatorError ?? moveError {
            throw error
        }
    }

    /// Moves an item to the system Trash using coordinated access (macOS / supported platforms).
    public func moveItemToTrash(at url: URL, filePresenter: NSFilePresenter? = nil) throws {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        var coordinatorError: NSError?
        var opError: NSError?

        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(
            writingItemAt: canonicalURL,
            options: [],
            error: &coordinatorError
        ) { actualURL in
            do {
                try FileManager.default.trashItem(at: actualURL, resultingItemURL: nil)
            } catch {
                opError = error as NSError
            }
        }

        if let error = coordinatorError ?? opError {
            throw error
        }
    }

    /// Copies a file in a coordinated manner.
    public func copyItem(from sourceURL: URL, to destinationURL: URL,
                         filePresenter: NSFilePresenter? = nil) throws {
        let canonicalSourceURL = CanonicalNoteIdentity.canonicalFileURL(for: sourceURL)
        let canonicalDestinationURL = CanonicalNoteIdentity.canonicalFileURL(for: destinationURL)
        var coordinatorError: NSError?
        var copyError: NSError?

        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(
            readingItemAt: canonicalSourceURL,
            options: [],
            writingItemAt: canonicalDestinationURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { actualSource, actualDestination in
            do {
                try FileManager.default.copyItem(at: actualSource, to: actualDestination)
            } catch {
                copyError = error as NSError
            }
        }

        if let error = coordinatorError ?? copyError {
            throw error
        }
    }

    /// Deletes a file in a coordinated manner.
    public func removeItem(at url: URL, filePresenter: NSFilePresenter? = nil) throws {
        let canonicalURL = CanonicalNoteIdentity.canonicalFileURL(for: url)
        var coordinatorError: NSError?
        var removeError: NSError?

        let coordinator = NSFileCoordinator(filePresenter: filePresenter)
        coordinator.coordinate(
            writingItemAt: canonicalURL,
            options: .forDeleting,
            error: &coordinatorError
        ) { actualURL in
            do {
                try FileManager.default.removeItem(at: actualURL)
            } catch {
                removeError = error as NSError
            }
        }

        if let error = coordinatorError ?? removeError {
            throw error
        }
    }
}

// MARK: - Errors

/// Errors specific to coordinated file operations.
public enum CoordinatedFileWriterError: LocalizedError {
    case timeout(url: URL, timeout: TimeInterval)
    case unknownFailure(url: URL)

    public var errorDescription: String? {
        switch self {
        case .timeout(let url, let timeout):
            return "File coordination timed out after \(Int(timeout))s for: \(url.lastPathComponent). iCloud may be unavailable."
        case .unknownFailure(let url):
            return "Unknown error writing to: \(url.lastPathComponent)"
        }
    }
}
