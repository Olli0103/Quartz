import Foundation

/// Centralized, iCloud-safe file writer.
///
/// Wraps `NSFileCoordinator` for conflict-free writing to iCloud Drive Vaults.
/// All services that write files to the vault MUST use this writer
/// to prevent data loss from sync conflicts.
public struct CoordinatedFileWriter: Sendable {
    public static let shared = CoordinatedFileWriter()

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

    /// Writes data to a URL in a coordinated manner.
    ///
    /// Uses `NSFileCoordinator` to ensure that iCloud Drive
    /// does not interrupt or overwrite the write operation.
    public func write(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var writeError: NSError?

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

    /// Creates a directory in a coordinated manner.
    public func createDirectory(at url: URL) throws {
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
                    withIntermediateDirectories: true
                )
            } catch {
                writeError = error as NSError
            }
        }

        if let error = coordinatorError ?? writeError {
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
