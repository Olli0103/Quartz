import Foundation
import os

/// Watches a vault folder for file changes.
///
/// Uses `DispatchSource` for file system events and
/// delivers changes as an `AsyncStream<FileChangeEvent>`.
public actor FileWatcher {
    // nonisolated(unsafe) so deinit can access them outside actor isolation.
    // These are only mutated from actor-isolated methods.
    nonisolated(unsafe) private var source: (any DispatchSourceFileSystemObject)?
    nonisolated(unsafe) private var fileDescriptor: Int32 = -1
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    deinit {
        source?.cancel()
    }

    /// Starts watching and returns a stream of changes.
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
        // Suppress Sendable diagnostic – DispatchSource is only accessed
        // from its own serial queue and the handlers below.
        nonisolated(unsafe) let sendableSource = dispatchSource
        return AsyncStream { continuation in
            sendableSource.setEventHandler {
                let event = sendableSource.data
                if event.contains(.delete) {
                    continuation.yield(.deleted(watchedURL))
                    continuation.finish()
                    return
                }
                if event.contains(.rename) {
                    // Folder was renamed or moved – end the stream,
                    // so the caller can create a new watcher.
                    continuation.yield(.deleted(watchedURL))
                    continuation.finish()
                    return
                }
                if event.contains(.write) {
                    continuation.yield(.modified(watchedURL))
                }
            }

            sendableSource.setCancelHandler {
                closedFlag.closeOnce(fd)
            }

            continuation.onTermination = { @Sendable _ in
                sendableSource.cancel()
            }

            sendableSource.resume()
        }
    }

    /// Stops watching.
    public func stopWatching() {
        source?.cancel()
        source = nil
    }
}

/// Thread-safe guard to ensure a file descriptor is closed exactly once.
/// Uses `OSAllocatedUnfairLock` for safe, lock-based synchronization
/// instead of raw `UnsafeMutablePointer`.
private final class ClosedFlag: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    func closeOnce(_ fd: Int32) {
        let shouldClose = state.withLock { closed -> Bool in
            guard !closed else { return false }
            closed = true
            return true
        }
        if shouldClose {
            close(fd)
        }
    }
}
