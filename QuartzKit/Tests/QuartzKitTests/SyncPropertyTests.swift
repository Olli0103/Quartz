import Testing
import Foundation
@testable import QuartzKit

// MARK: - Sync Property / Coordinated File Writer Tests

@Suite("SyncProperty")
struct SyncPropertyTests {

    @Test("CoordinatedFileWriter round-trip: write then read, and default timeout value")
    func coordinatedWriteReadRoundTrip() throws {
        let writer = CoordinatedFileWriter()

        // Verify default timeout constant
        #expect(CoordinatedFileWriter.defaultTimeout == 10.0)

        // Write content to a temp file
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sync-prop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test.md")
        let content = "# Hello\n\nCoordinated content."
        let data = content.data(using: .utf8)!

        try writer.write(data, to: fileURL)

        // Read it back
        let readData = try writer.read(from: fileURL)
        let readString = String(data: readData, encoding: .utf8)
        #expect(readString == content)

        // readString convenience
        let text = try writer.readString(from: fileURL)
        #expect(text == content)

        // Shared singleton exists
        let shared = CoordinatedFileWriter.shared
        let text2 = try shared.readString(from: fileURL)
        #expect(text2 == content)
    }

    @Test("Concurrent coordinated writes produce no byte loss or corruption")
    func concurrentCoordinatedWritesNoDataLoss() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("concurrent-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let writer = CoordinatedFileWriter.shared
        let iterations = 100

        // Each task writes to its OWN file — tests that NSFileCoordinator does not
        // corrupt data when many coordinated writes happen concurrently.
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                let fileURL = tempDir.appendingPathComponent("note-\(i).md")
                let content = "# Note \(i)\n\nContent for note \(i). " + String(repeating: "x", count: i * 10)
                let data = Data(content.utf8)

                group.addTask {
                    try writer.write(data, to: fileURL)
                }
            }
            try await group.waitForAll()
        }

        // Verify every file has correct content — zero byte loss
        for i in 0..<iterations {
            let fileURL = tempDir.appendingPathComponent("note-\(i).md")
            let expected = "# Note \(i)\n\nContent for note \(i). " + String(repeating: "x", count: i * 10)
            let readData = try writer.read(from: fileURL)
            let readString = String(data: readData, encoding: .utf8)
            #expect(readString == expected,
                "Note \(i) content mismatch — byte loss or corruption detected")
        }
    }

    @Test("Concurrent writes to SAME file produce no corruption")
    func concurrentWritesSameFile() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("same-file-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("shared.md")
        let writer = CoordinatedFileWriter.shared
        let iterations = 50

        // Write initial content
        try writer.write(Data("initial".utf8), to: fileURL)

        // Many concurrent writes to the SAME file — last writer wins, but
        // the file must always contain a complete, valid write (no partial data).
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                let content = "Version \(i): " + String(repeating: "a", count: 200)
                let data = Data(content.utf8)
                group.addTask {
                    try writer.write(data, to: fileURL)
                }
            }
            try await group.waitForAll()
        }

        // The file must contain one of the valid writes — no partial or zero-length content
        let finalData = try writer.read(from: fileURL)
        let finalString = String(data: finalData, encoding: .utf8)
        #expect(finalString != nil, "File must be valid UTF-8")
        #expect(finalString!.hasPrefix("Version "),
            "File must contain a complete write, not partial data")
        #expect(finalString!.count > 200,
            "File must not be truncated (expected > 200 chars, got \(finalString!.count))")
    }
}
