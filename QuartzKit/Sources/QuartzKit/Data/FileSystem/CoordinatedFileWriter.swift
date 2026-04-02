import Foundation

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
    public func read(from url: URL) throws -> Data {
        var coordinatorError: NSError?
        var readError: NSError?
        var result: Data?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: url,
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
            throw error
        }

        guard let data = result else {
            throw CocoaError(.fileReadUnknown)
        }
        return data
    }

    /// Reads file contents as text (UTF-8 by default) using coordinated access.
    public func readString(from url: URL, encoding: String.Encoding = .utf8) throws -> String {
        let data = try read(from: url)
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
    /// - Important: If the coordination blocks for longer than the timeout,
    ///   the operation is cancelled and an error is thrown. This prevents
    ///   the app from hanging indefinitely when iCloud sync is stuck.
    public func write(_ data: Data, to url: URL, timeout: TimeInterval = defaultTimeout) throws {
        var coordinatorError: NSError?
        var writeError: NSError?
        var didComplete = false

        let coordinator = NSFileCoordinator()

        // Use a semaphore to implement timeout
        let semaphore = DispatchSemaphore(value: 0)

        // Run coordination on a background queue
        DispatchQueue.global(qos: .userInitiated).async {
            coordinator.coordinate(
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinatorError
            ) { actualURL in
                do {
                    try data.write(to: actualURL, options: .atomic)
                    didComplete = true
                } catch {
                    writeError = error as NSError
                }
            }
            semaphore.signal()
        }

        // Wait with timeout
        let result = semaphore.wait(timeout: .now() + timeout)

        if result == .timedOut {
            // Cancel the coordination if it's taking too long
            coordinator.cancel()
            throw CoordinatedFileWriterError.timeout(url: url, timeout: timeout)
        }

        if let error = coordinatorError ?? writeError {
            throw error
        }

        if !didComplete && coordinatorError == nil && writeError == nil {
            throw CoordinatedFileWriterError.unknownFailure(url: url)
        }
    }

    /// Creates a directory in a coordinated manner.
    public func createDirectory(at url: URL, withIntermediateDirectories: Bool = true) throws {
        var coordinatorError: NSError?
        var writeError: NSError?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: url,
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
    public func moveItem(from sourceURL: URL, to destinationURL: URL) throws {
        var coordinatorError: NSError?
        var moveError: NSError?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [],
            writingItemAt: destinationURL,
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
    public func moveItemToTrash(at url: URL) throws {
        var coordinatorError: NSError?
        var opError: NSError?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: url,
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
    public func copyItem(from sourceURL: URL, to destinationURL: URL) throws {
        var coordinatorError: NSError?
        var copyError: NSError?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [],
            writingItemAt: destinationURL,
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
    public func removeItem(at url: URL) throws {
        var coordinatorError: NSError?
        var removeError: NSError?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: url,
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
