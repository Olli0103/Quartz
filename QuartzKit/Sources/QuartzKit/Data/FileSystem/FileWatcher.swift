import Foundation

/// Beobachtet einen Vault-Ordner auf Dateiänderungen.
///
/// Nutzt `DispatchSource` für Dateisystem-Events und
/// liefert Änderungen als `AsyncStream<FileChangeEvent>`.
public actor FileWatcher {
    private var source: (any DispatchSourceFileSystemObject)?
    private var fileDescriptor: Int32 = -1
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Startet die Beobachtung und gibt einen Stream von Änderungen zurück.
    public func startWatching() -> AsyncStream<FileChangeEvent> {
        AsyncStream { continuation in
            let fd = open(url.path(percentEncoded: false), O_EVTONLY)
            guard fd >= 0 else {
                continuation.finish()
                return
            }
            self.fileDescriptor = fd

            let dispatchSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename],
                queue: .global(qos: .utility)
            )

            dispatchSource.setEventHandler {
                let event = dispatchSource.data
                if event.contains(.delete) {
                    continuation.yield(.deleted(self.url))
                    continuation.finish()
                    return
                }
                if event.contains(.rename) {
                    // Ordner wurde umbenannt oder verschoben – Stream beenden,
                    // damit der Aufrufer einen neuen Watcher erstellen kann.
                    continuation.yield(.deleted(self.url))
                    continuation.finish()
                    return
                }
                if event.contains(.write) {
                    continuation.yield(.modified(self.url))
                }
            }

            dispatchSource.setCancelHandler {
                close(fd)
            }

            continuation.onTermination = { @Sendable _ in
                dispatchSource.cancel()
            }

            self.source = dispatchSource
            dispatchSource.resume()
        }
    }

    /// Stoppt die Beobachtung.
    public func stopWatching() {
        source?.cancel()
        source = nil
    }
}
