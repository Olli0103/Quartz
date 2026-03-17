import Foundation

/// Zentralisierter, iCloud-sicherer Datei-Schreiber.
///
/// Wraps `NSFileCoordinator` für konfliktfreies Schreiben in iCloud Drive Vaults.
/// Alle Services die Dateien im Vault schreiben MÜSSEN diesen Writer verwenden,
/// um Datenverlust durch Sync-Konflikte zu verhindern.
public struct CoordinatedFileWriter: Sendable {
    public static let shared = CoordinatedFileWriter()

    public init() {}

    /// Schreibt Daten koordiniert an eine URL.
    ///
    /// Nutzt `NSFileCoordinator` um sicherzustellen, dass iCloud Drive
    /// den Schreibvorgang nicht unterbricht oder überschreibt.
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

    /// Erstellt ein Verzeichnis koordiniert.
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

    /// Kopiert eine Datei koordiniert.
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

    /// Löscht eine Datei koordiniert.
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
