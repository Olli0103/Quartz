import Testing
import Foundation
@testable import QuartzKit

// MARK: - iCloud Timeout & File System Error Tests

@Suite("iCloudTimeout")
struct iCloudTimeoutTests {

    @Test("FileSystemError cases have localized descriptions and correct associated values")
    func fileSystemErrorCoverage() {
        let testURL = URL(fileURLWithPath: "/vault/note.md")

        // iCloudTimeout
        let timeout = FileSystemError.iCloudTimeout(testURL)
        #expect(timeout.errorDescription?.contains("iCloud") == true)
        #expect(timeout.errorDescription?.contains("note.md") == true)

        // fileNotFound
        let notFound = FileSystemError.fileNotFound(testURL)
        #expect(notFound.errorDescription?.contains("not found") == true)
        #expect(notFound.errorDescription?.contains("note.md") == true)

        // fileAlreadyExists
        let exists = FileSystemError.fileAlreadyExists(testURL)
        #expect(exists.errorDescription?.contains("already exists") == true)

        // encodingFailed
        let encoding = FileSystemError.encodingFailed(testURL)
        #expect(encoding.errorDescription?.contains("note.md") == true)

        // invalidName
        let invalid = FileSystemError.invalidName("bad/name")
        #expect(invalid.errorDescription?.contains("bad/name") == true)
    }
}
