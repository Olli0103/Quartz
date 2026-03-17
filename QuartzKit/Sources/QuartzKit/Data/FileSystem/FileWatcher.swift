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

    deinit {
        source?.cancel()
    }

    /// Startet die Beobachtung und gibt einen Stream von Änderungen zurück.
    public func startWatching() -> AsyncStream<FileChangeEvent> {
        let fd = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else {
            return AsyncStream { $0.finish() }
        }
        self.fileDescriptor = fd

        let dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .global(qos: .utility)
        )
        self.source = dispatchSource

        let watchedURL = self.url
        // Use a flag to ensure the file descriptor is closed exactly once,
        // even if both setCancelHandler and onTermination fire.
        let closedFlag = ClosedFlag()
        return AsyncStream { continuation in
            dispatchSource.setEventHandler {
                let event = dispatchSource.data
                if event.contains(.delete) {
                    continuation.yield(.deleted(watchedURL))
                    continuation.finish()
                    return
                }
                if event.contains(.rename) {
                    // Ordner wurde umbenannt oder verschoben – Stream beenden,
                    // damit der Aufrufer einen neuen Watcher erstellen kann.
                    continuation.yield(.deleted(watchedURL))
                    continuation.finish()
                    return
                }
                if event.contains(.write) {
                    continuation.yield(.modified(watchedURL))
                }
            }

            dispatchSource.setCancelHandler {
                closedFlag.closeOnce(fd)
            }

            continuation.onTermination = { @Sendable _ in
                dispatchSource.cancel()
            }

            dispatchSource.resume()
        }
    }

    /// Stoppt die Beobachtung.
    public func stopWatching() {
        source?.cancel()
        source = nil
    }
}

/// Thread-safe guard to ensure a file descriptor is closed exactly once.
private final class ClosedFlag: Sendable {
    private let lock = NSLock()
    private let _closed = UnsafeMutablePointer<Bool>.allocate(capacity: 1)

    init() {
        _closed.initialize(to: false)
    }

    deinit {
        _closed.deallocate()
    }

    func closeOnce(_ fd: Int32) {
        lock.lock()
        defer { lock.unlock() }
        guard !_closed.pointee else { return }
        _closed.pointee = true
        close(fd)
    }
}
