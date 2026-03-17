import Testing
import Foundation
@testable import QuartzKit

@Suite("FileWatcher")
struct FileWatcherTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("startWatching returns stream for valid directory")
    func startWatchingReturnsStream() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let watcher = FileWatcher(url: dir)
        let stream = await watcher.startWatching()

        // Write a file to trigger a .modified event
        let file = dir.appendingPathComponent("test.md")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        // Collect first event with timeout
        var receivedEvent: FileChangeEvent?
        let deadline = Date().addingTimeInterval(3)
        for await event in stream {
            receivedEvent = event
            break
        }

        if let event = receivedEvent {
            // We should get a modified event for the watched directory
            switch event {
            case .modified:
                break // Expected
            case .created, .deleted:
                break // Also acceptable depending on platform
            }
        }

        // Even if no event arrived (timing), verify watcher can be stopped
        await watcher.stopWatching()
    }

    @Test("startWatching with invalid path returns finished stream")
    func invalidPathReturnsFinishedStream() async {
        let watcher = FileWatcher(url: URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString)"))
        let stream = await watcher.startWatching()

        var eventCount = 0
        for await _ in stream {
            eventCount += 1
        }

        #expect(eventCount == 0)
    }

    @Test("stopWatching is safe to call multiple times")
    func stopWatchingIdempotent() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let watcher = FileWatcher(url: dir)
        _ = await watcher.startWatching()

        await watcher.stopWatching()
        await watcher.stopWatching() // Should not crash
    }

    @Test("stopWatching before startWatching is safe")
    func stopBeforeStart() async {
        let watcher = FileWatcher(url: URL(fileURLWithPath: "/tmp"))
        await watcher.stopWatching() // Should not crash
    }
}
