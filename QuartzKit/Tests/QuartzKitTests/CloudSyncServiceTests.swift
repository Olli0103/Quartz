#if canImport(UIKit) || canImport(AppKit)
import Testing
import Foundation
@testable import QuartzKit

@Suite("CloudSyncService")
struct CloudSyncServiceTests {
    @Test("CloudSyncStatus has all expected cases")
    func statusCases() {
        let statuses: [CloudSyncStatus] = [
            .current, .uploading, .downloading, .notDownloaded, .error, .notApplicable
        ]
        #expect(statuses.count == 6)
    }

    @Test("CloudSyncError provides localized descriptions")
    func errorDescriptions() {
        let readErr = CloudSyncError.readFailed(URL(fileURLWithPath: "/test.md"))
        let writeErr = CloudSyncError.writeFailed(URL(fileURLWithPath: "/test.md"))
        let notAvail = CloudSyncError.notAvailable

        #expect(readErr.errorDescription != nil)
        #expect(writeErr.errorDescription != nil)
        #expect(notAvail.errorDescription != nil)
        #expect(readErr.errorDescription!.contains("test.md"))
    }

    @Test("coordinatedRead throws for nonexistent file")
    func coordinatedReadNonexistent() async throws {
        let service = CloudSyncService()
        let url = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).md")

        do {
            _ = try await service.coordinatedRead(at: url)
            Issue.record("Should have thrown")
        } catch {
            // Expected — either CloudSyncError or NSError
        }
    }

    @Test("coordinatedWrite and coordinatedRead round-trip")
    func writeReadRoundTrip() async throws {
        let service = CloudSyncService()
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncTest-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let testData = Data("Hello CloudSync".utf8)
        try await service.coordinatedWrite(data: testData, to: tmpFile)

        let readBack = try await service.coordinatedRead(at: tmpFile)
        #expect(readBack == testData)
    }

    @Test("isAvailable returns Bool without crashing")
    func isAvailableCheck() {
        // On CI, iCloud is typically not available
        let available = CloudSyncService.isAvailable
        #expect(available == true || available == false)
    }

    @Test("stopMonitoring is safe to call without starting")
    func stopWithoutStart() async {
        let service = CloudSyncService()
        await service.stopMonitoring() // Should not crash
    }
}
#endif
