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
}
