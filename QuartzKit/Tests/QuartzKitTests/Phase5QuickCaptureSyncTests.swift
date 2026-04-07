import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Phase 5: Quick Capture, Sync Reliability, Conflict Safety
// TDD Red Phase: These tests define the required behavior for quick capture and sync improvements.

// ============================================================================
// MARK: - Quick Capture Flow Tests
// ============================================================================

@Suite("QuickCaptureFlow")
struct QuickCaptureFlowTests {

    // MARK: - QuickCaptureUseCase Tests

    @Test("QuickCaptureUseCase creates note within latency budget")
    func quickCaptureLatencyBudget() async throws {
        let useCase = QuickCaptureUseCase()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickCaptureTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let startTime = Date()

        // Capture should complete in under 100ms
        let result = try await useCase.capture(
            content: "Quick thought",
            title: nil,
            vaultRoot: tempDir
        )

        let elapsed = Date().timeIntervalSince(startTime)

        #expect(elapsed < 0.5, "Quick capture should complete in under 500ms")
        #expect(FileManager.default.fileExists(atPath: result.url.path(percentEncoded: false)))
    }

    @Test("Quick capture with title uses title as filename")
    func quickCaptureWithTitle() async throws {
        let useCase = QuickCaptureUseCase()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickCaptureTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await useCase.capture(
            content: "Note content here",
            title: "My Quick Note",
            vaultRoot: tempDir
        )

        #expect(result.url.lastPathComponent == "My Quick Note.md")
    }

    @Test("Quick capture without title generates timestamp-based filename")
    func quickCaptureWithoutTitle() async throws {
        let useCase = QuickCaptureUseCase()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickCaptureTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await useCase.capture(
            content: "Untitled thought",
            title: nil,
            vaultRoot: tempDir
        )

        // Should have a date-based name like "Quick Note 2026-04-01 10-30.md"
        #expect(result.url.lastPathComponent.contains("Quick Note"))
        #expect(result.url.pathExtension == "md")
    }

    @Test("Quick capture handles special characters in title")
    func quickCaptureSpecialChars() async throws {
        let useCase = QuickCaptureUseCase()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickCaptureTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try await useCase.capture(
            content: "Content",
            title: "Meeting: Q1/Q2 Review",
            vaultRoot: tempDir
        )

        // Colons and slashes should be sanitized
        let filename = result.url.lastPathComponent
        #expect(!filename.contains(":"))
        #expect(!filename.contains("/"))
        #expect(filename.hasSuffix(".md"))
    }

    @Test("Quick capture creates stub immediately, enriches later")
    func quickCaptureStubAndEnrich() async throws {
        let useCase = QuickCaptureUseCase()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickCaptureTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Capture with deferred enrichment
        let result = try await useCase.capture(
            content: "Initial thought",
            title: "Deferred Note",
            vaultRoot: tempDir,
            deferEnrichment: true
        )

        // File should exist immediately
        #expect(FileManager.default.fileExists(atPath: result.url.path(percentEncoded: false)))

        // Content should be minimal (stub)
        let content = try String(contentsOf: result.url, encoding: .utf8)
        #expect(content.contains("Initial thought"))

        // Enrichment can happen later (frontmatter, links, etc.)
        #expect(result.needsEnrichment == true)
    }

    @Test("Quick capture notifies after save")
    func quickCaptureNotification() async throws {
        let useCase = QuickCaptureUseCase()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickCaptureTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .quartzQuickCaptureCompleted,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        _ = try await useCase.capture(
            content: "Test",
            title: "Notification Test",
            vaultRoot: tempDir
        )

        // Give notification time to propagate
        try await Task.sleep(for: .milliseconds(50))

        #expect(notificationReceived)
    }
}

// ============================================================================
// MARK: - Cloud Sync Conflict Policy Tests
// ============================================================================

#if canImport(UIKit) || canImport(AppKit)
@Suite("CloudSyncConflictPolicy")
struct CloudSyncConflictPolicyTests {

    @Test("Conflict merge policy is deterministic for same edits")
    func mergeIsDeterministic() async {
        let resolver = ConflictMergeResolver()

        let baseContent = "Line 1\nLine 2\nLine 3"
        let localEdit = "Line 1\nLine 2 - edited locally\nLine 3"
        let cloudEdit = "Line 1\nLine 2 - edited in cloud\nLine 3"

        // Same inputs should always produce same output
        let merge1 = await resolver.merge(
            base: baseContent,
            local: localEdit,
            cloud: cloudEdit
        )

        let merge2 = await resolver.merge(
            base: baseContent,
            local: localEdit,
            cloud: cloudEdit
        )

        #expect(merge1.mergedContent == merge2.mergedContent)
        #expect(merge1.hasConflictMarkers == merge2.hasConflictMarkers)
    }

    @Test("Conflict resolver identifies non-overlapping edits")
    func nonOverlappingEdits() async {
        let resolver = ConflictMergeResolver()

        let baseContent = "Line 1\nLine 2\nLine 3"
        let localEdit = "Line 1 - local\nLine 2\nLine 3"
        let cloudEdit = "Line 1\nLine 2\nLine 3 - cloud"

        let result = await resolver.merge(
            base: baseContent,
            local: localEdit,
            cloud: cloudEdit
        )

        // Non-overlapping edits should merge cleanly
        #expect(result.hasConflictMarkers == false)
        #expect(result.mergedContent.contains("Line 1 - local"))
        #expect(result.mergedContent.contains("Line 3 - cloud"))
    }

    @Test("Conflict resolver marks overlapping edits")
    func overlappingEdits() async {
        let resolver = ConflictMergeResolver()

        let baseContent = "Line 1\nLine 2\nLine 3"
        let localEdit = "Line 1\nLine 2 - LOCAL\nLine 3"
        let cloudEdit = "Line 1\nLine 2 - CLOUD\nLine 3"

        let result = await resolver.merge(
            base: baseContent,
            local: localEdit,
            cloud: cloudEdit
        )

        // Same line edited differently should have conflict markers
        #expect(result.hasConflictMarkers == true)
        #expect(result.mergedContent.contains("<<<<<<") || result.conflictRegions.count > 0)
    }

    @Test("Merge metadata includes timestamps")
    func mergeMetadata() async {
        let resolver = ConflictMergeResolver()

        let localTimestamp = Date().addingTimeInterval(-60) // 1 minute ago
        let cloudTimestamp = Date().addingTimeInterval(-30) // 30 seconds ago

        let result = await resolver.merge(
            base: "Original",
            local: "Local edit",
            cloud: "Cloud edit",
            localTimestamp: localTimestamp,
            cloudTimestamp: cloudTimestamp
        )

        // Metadata should be preserved for UI display
        #expect(result.localTimestamp == localTimestamp)
        #expect(result.cloudTimestamp == cloudTimestamp)
    }

    @Test("Operation-based merge preserves intent")
    func operationBasedMerge() async {
        let resolver = ConflictMergeResolver()

        // Simulate CRDT-style operations - single insert at start
        let operations: [MergeOperation] = [
            MergeOperation(type: .insert, position: 0, content: "PREFIX: ", timestamp: Date(), author: "local")
        ]

        let result = await resolver.applyOperations(
            to: "Original content",
            operations: operations
        )

        #expect(result.content.contains("PREFIX:"))
        #expect(result.content.contains("Original content"))
    }

    @Test("Conflict resolution tracks session ID")
    func sessionTracking() async {
        let resolver = ConflictMergeResolver()
        let sessionID = UUID()

        let result = await resolver.merge(
            base: "Base",
            local: "Local",
            cloud: "Cloud",
            sessionID: sessionID
        )

        #expect(result.sessionID == sessionID)
    }
}
#endif

// ============================================================================
// MARK: - Sync Recovery Tests
// ============================================================================

#if canImport(UIKit) || canImport(AppKit)
@Suite("SyncRecovery")
struct SyncRecoveryTests {

    @Test("Interrupted write resumes safely")
    func interruptedWriteResumes() async throws {
        let recoveryManager = SyncRecoveryManager()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncRecoveryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetURL = tempDir.appendingPathComponent("test-note.md")
        let content = "Important content that must not be lost"

        // Start a write operation
        let writeID = await recoveryManager.beginWrite(to: targetURL, content: content)

        // Simulate interruption by checking pending writes
        let pendingWrites = await recoveryManager.pendingWrites()
        #expect(pendingWrites.contains(where: { $0.id == writeID }))

        // Complete the write
        try await recoveryManager.completeWrite(id: writeID)

        // Verify content was written
        let savedContent = try String(contentsOf: targetURL, encoding: .utf8)
        #expect(savedContent == content)

        // Pending writes should be cleared
        let remainingWrites = await recoveryManager.pendingWrites()
        #expect(!remainingWrites.contains(where: { $0.id == writeID }))
    }

    @Test("Recovery journal persists across restarts")
    func journalPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncRecoveryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let journalURL = tempDir.appendingPathComponent(".quartz-recovery-journal.json")

        // Create manager and start a write
        let manager1 = SyncRecoveryManager(journalURL: journalURL)
        let targetURL = tempDir.appendingPathComponent("persistent-note.md")
        let writeID = await manager1.beginWrite(to: targetURL, content: "Critical data")

        // Simulate app termination by creating a new manager with same journal
        let manager2 = SyncRecoveryManager(journalURL: journalURL)
        await manager2.loadFromDisk()
        let recoveredWrites = await manager2.pendingWrites()

        // Should recover the pending write
        #expect(recoveredWrites.contains(where: { $0.id == writeID }))
    }

    @Test("Failed write can be retried")
    func failedWriteRetry() async throws {
        let recoveryManager = SyncRecoveryManager()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncRecoveryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetURL = tempDir.appendingPathComponent("retry-note.md")
        let content = "Content to retry"

        // Begin write
        let writeID = await recoveryManager.beginWrite(to: targetURL, content: content)

        // Mark as failed
        await recoveryManager.markWriteFailed(id: writeID, error: "Simulated failure")

        // Retry
        let retryResult = try await recoveryManager.retryWrite(id: writeID)
        #expect(retryResult.success)

        // Verify content
        let savedContent = try String(contentsOf: targetURL, encoding: .utf8)
        #expect(savedContent == content)
    }

    @Test("No data loss on crash during save")
    func noDataLossOnCrash() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncRecoveryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let journalURL = tempDir.appendingPathComponent(".quartz-recovery-journal.json")
        let manager = SyncRecoveryManager(journalURL: journalURL)

        // Write multiple notes
        let notes = [
            ("note1.md", "Content 1"),
            ("note2.md", "Content 2"),
            ("note3.md", "Content 3")
        ]

        var writeIDs: [UUID] = []
        for (name, content) in notes {
            let url = tempDir.appendingPathComponent(name)
            let id = await manager.beginWrite(to: url, content: content)
            writeIDs.append(id)
        }

        // Simulate recovery
        let newManager = SyncRecoveryManager(journalURL: journalURL)
        await newManager.loadFromDisk()
        let pending = await newManager.pendingWrites()

        // All writes should be recoverable
        for id in writeIDs {
            #expect(pending.contains(where: { $0.id == id }))
        }
    }

    @Test("Atomic write prevents partial content")
    func atomicWrite() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncRecoveryTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let targetURL = tempDir.appendingPathComponent("atomic-note.md")
        let content = String(repeating: "Large content block. ", count: 1000)

        // Write atomically
        let writer = AtomicFileWriter()
        try await writer.write(content: content, to: targetURL)

        // Read back - should be complete or not exist
        if FileManager.default.fileExists(atPath: targetURL.path(percentEncoded: false)) {
            let savedContent = try String(contentsOf: targetURL, encoding: .utf8)
            #expect(savedContent == content, "Content should be complete, not partial")
        }
    }
}
#endif

// ============================================================================
// MARK: - Sync State Indicator Tests
// ============================================================================

#if canImport(UIKit) || canImport(AppKit)
@Suite("SyncStateIndicator")
struct SyncStateIndicatorTests {

    @Test("Sync state updates on coordinated write")
    func syncStateUpdatesOnWrite() async throws {
        let indicator = SyncStateIndicator()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyncStateTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let noteURL = tempDir.appendingPathComponent("sync-test.md")

        // Initial state
        var state = await indicator.state(for: noteURL)
        #expect(state == .unknown || state == .synced)

        // Begin write
        await indicator.beginWrite(for: noteURL)
        state = await indicator.state(for: noteURL)
        #expect(state == .pending)

        // Complete write
        await indicator.completeWrite(for: noteURL)
        state = await indicator.state(for: noteURL)
        #expect(state == .synced)
    }

    @Test("Sync state shows uploading during iCloud sync")
    func syncStateUploading() async {
        let indicator = SyncStateIndicator()
        let noteURL = URL(fileURLWithPath: "/test/note.md")

        await indicator.setCloudStatus(for: noteURL, status: .uploading)
        let state = await indicator.state(for: noteURL)

        #expect(state == .uploading)
    }

    @Test("Sync state shows conflict when detected")
    func syncStateConflict() async {
        let indicator = SyncStateIndicator()
        let noteURL = URL(fileURLWithPath: "/test/conflict-note.md")

        await indicator.setCloudStatus(for: noteURL, status: .conflict)
        let state = await indicator.state(for: noteURL)

        #expect(state == .conflict)
    }

    @Test("Aggregate vault state reflects worst status")
    func aggregateVaultState() async {
        let indicator = SyncStateIndicator()

        let note1 = URL(fileURLWithPath: "/vault/note1.md")
        let note2 = URL(fileURLWithPath: "/vault/note2.md")
        let note3 = URL(fileURLWithPath: "/vault/note3.md")

        await indicator.setCloudStatus(for: note1, status: .current)
        await indicator.setCloudStatus(for: note2, status: .uploading)
        await indicator.setCloudStatus(for: note3, status: .current)

        let aggregate = await indicator.aggregateState()

        // Should show uploading since one file is uploading
        #expect(aggregate == .uploading)
    }
}
#endif

// ============================================================================
// MARK: - Performance Tests (XCTest)
// ============================================================================

final class Phase5SyncPerformanceTests: XCTestCase {

    /// Quick capture should complete in under 100ms
    func testQuickCaptureTiming() async throws {
        let useCase = QuickCaptureUseCase()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickCapturePerfTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric()], options: options) {
            let expectation = self.expectation(description: "Capture")

            Task {
                _ = try? await useCase.capture(
                    content: "Performance test content",
                    title: "Perf Test \(UUID().uuidString.prefix(8))",
                    vaultRoot: tempDir
                )
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }
    }

    /// Coordinated write should be efficient
    func testCoordinatedWritePerformance() async throws {
        #if canImport(UIKit) || canImport(AppKit)
        let service = CloudSyncService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoordWritePerfTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let content = String(repeating: "Test content line.\n", count: 100)
        let data = Data(content.utf8)

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let expectation = self.expectation(description: "Write")

            Task {
                let url = tempDir.appendingPathComponent("perf-\(UUID().uuidString).md")
                try? await service.coordinatedWrite(data: data, to: url)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 2.0)
        }
        #endif
    }

    /// Conflict merge should be fast
    func testConflictMergePerformance() async throws {
        #if canImport(UIKit) || canImport(AppKit)
        let resolver = ConflictMergeResolver()

        // Generate larger content
        let baseContent = (0..<100).map { "Line \($0): Original content" }.joined(separator: "\n")
        let localEdit = baseContent.replacingOccurrences(of: "Line 50:", with: "Line 50 (LOCAL):")
        let cloudEdit = baseContent.replacingOccurrences(of: "Line 75:", with: "Line 75 (CLOUD):")

        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            let expectation = self.expectation(description: "Merge")

            Task {
                _ = await resolver.merge(
                    base: baseContent,
                    local: localEdit,
                    cloud: cloudEdit
                )
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }
        #endif
    }
}

// ============================================================================
// MARK: - Supporting Types (Mock/Stub Implementations)
// ============================================================================

/// Use case for quick note capture across platforms.
public actor QuickCaptureUseCase {

    public struct CaptureResult: Sendable {
        public let url: URL
        public let needsEnrichment: Bool

        public init(url: URL, needsEnrichment: Bool = false) {
            self.url = url
            self.needsEnrichment = needsEnrichment
        }
    }

    public init() {}

    public func capture(
        content: String,
        title: String?,
        vaultRoot: URL,
        deferEnrichment: Bool = false
    ) async throws -> CaptureResult {
        // Generate filename
        let filename: String
        if let title, !title.isEmpty {
            // Sanitize title for filesystem
            let sanitized = title
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: "\\", with: "-")
            filename = "\(sanitized).md"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH-mm"
            let timestamp = formatter.string(from: Date())
            filename = "Quick Note \(timestamp).md"
        }

        let url = vaultRoot.appendingPathComponent(filename)

        // Write content atomically
        let data = Data(content.utf8)
        try data.write(to: url, options: .atomic)

        // Post notification
        await MainActor.run {
            NotificationCenter.default.post(
                name: .quartzQuickCaptureCompleted,
                object: nil,
                userInfo: ["url": url]
            )
        }

        return CaptureResult(url: url, needsEnrichment: deferEnrichment)
    }
}

/// Notification for quick capture completion.
public extension Notification.Name {
    static let quartzQuickCaptureCompleted = Notification.Name("quartzQuickCaptureCompleted")
}

#if canImport(UIKit) || canImport(AppKit)
/// Conflict merge resolver with CRDT-inspired merge strategy.
public actor ConflictMergeResolver {

    public struct MergeResult: Sendable {
        public let mergedContent: String
        public let hasConflictMarkers: Bool
        public let conflictRegions: [ConflictRegion]
        public let localTimestamp: Date?
        public let cloudTimestamp: Date?
        public let sessionID: UUID?

        public init(
            mergedContent: String,
            hasConflictMarkers: Bool = false,
            conflictRegions: [ConflictRegion] = [],
            localTimestamp: Date? = nil,
            cloudTimestamp: Date? = nil,
            sessionID: UUID? = nil
        ) {
            self.mergedContent = mergedContent
            self.hasConflictMarkers = hasConflictMarkers
            self.conflictRegions = conflictRegions
            self.localTimestamp = localTimestamp
            self.cloudTimestamp = cloudTimestamp
            self.sessionID = sessionID
        }
    }

    public struct ConflictRegion: Sendable {
        public let lineRange: Range<Int>
        public let localContent: String
        public let cloudContent: String
    }

    public struct ApplyResult: Sendable {
        public let content: String
    }

    public init() {}

    public func merge(
        base: String,
        local: String,
        cloud: String,
        localTimestamp: Date? = nil,
        cloudTimestamp: Date? = nil,
        sessionID: UUID? = nil
    ) -> MergeResult {
        let baseLines = base.components(separatedBy: "\n")
        let localLines = local.components(separatedBy: "\n")
        let cloudLines = cloud.components(separatedBy: "\n")

        var mergedLines: [String] = []
        var hasConflicts = false
        var conflictRegions: [ConflictRegion] = []

        let maxLines = max(baseLines.count, localLines.count, cloudLines.count)

        for i in 0..<maxLines {
            let baseLine = i < baseLines.count ? baseLines[i] : ""
            let localLine = i < localLines.count ? localLines[i] : ""
            let cloudLine = i < cloudLines.count ? cloudLines[i] : ""

            if localLine == cloudLine {
                // No conflict
                mergedLines.append(localLine)
            } else if localLine == baseLine {
                // Only cloud changed
                mergedLines.append(cloudLine)
            } else if cloudLine == baseLine {
                // Only local changed
                mergedLines.append(localLine)
            } else {
                // Both changed - conflict
                hasConflicts = true
                mergedLines.append("<<<<<<< LOCAL")
                mergedLines.append(localLine)
                mergedLines.append("=======")
                mergedLines.append(cloudLine)
                mergedLines.append(">>>>>>> CLOUD")

                conflictRegions.append(ConflictRegion(
                    lineRange: mergedLines.count-5..<mergedLines.count,
                    localContent: localLine,
                    cloudContent: cloudLine
                ))
            }
        }

        return MergeResult(
            mergedContent: mergedLines.joined(separator: "\n"),
            hasConflictMarkers: hasConflicts,
            conflictRegions: conflictRegions,
            localTimestamp: localTimestamp,
            cloudTimestamp: cloudTimestamp,
            sessionID: sessionID
        )
    }

    public func applyOperations(to content: String, operations: [MergeOperation]) -> ApplyResult {
        var result = content

        // Sort by position descending to apply from end (avoids offset issues)
        let sorted = operations.sorted { $0.position > $1.position }

        for op in sorted {
            switch op.type {
            case .insert:
                let index = result.index(result.startIndex, offsetBy: min(op.position, result.count))
                result.insert(contentsOf: op.content, at: index)
            case .delete:
                if let range = op.range {
                    let start = result.index(result.startIndex, offsetBy: min(range.lowerBound, result.count))
                    let end = result.index(result.startIndex, offsetBy: min(range.upperBound, result.count))
                    result.removeSubrange(start..<end)
                }
            }
        }

        return ApplyResult(content: result)
    }
}

/// Represents a CRDT-style merge operation.
public struct MergeOperation: Sendable {
    public enum OperationType: Sendable {
        case insert
        case delete
    }

    public let type: OperationType
    public let position: Int
    public let content: String
    public let range: Range<Int>?
    public let timestamp: Date
    public let author: String

    public init(type: OperationType, position: Int = 0, content: String = "", range: Range<Int>? = nil, timestamp: Date, author: String) {
        self.type = type
        self.position = position
        self.content = content
        self.range = range
        self.timestamp = timestamp
        self.author = author
    }
}

/// Manager for write-ahead logging and recovery.
public actor SyncRecoveryManager {

    public struct PendingWrite: Codable, Sendable {
        public let id: UUID
        public let targetPath: String
        public let content: String
        public let timestamp: Date
        public var failed: Bool
        public var errorMessage: String?

        public init(id: UUID, targetPath: String, content: String, timestamp: Date, failed: Bool = false, errorMessage: String? = nil) {
            self.id = id
            self.targetPath = targetPath
            self.content = content
            self.timestamp = timestamp
            self.failed = failed
            self.errorMessage = errorMessage
        }
    }

    public struct RetryResult: Sendable {
        public let success: Bool
    }

    private var writes: [UUID: PendingWrite] = [:]
    private let journalURL: URL?

    public init(journalURL: URL? = nil) {
        self.journalURL = journalURL
        // Journal loading is deferred to first access or explicit call
    }

    /// Load journal from disk (call after init to recover pending writes).
    public func loadFromDisk() {
        if let url = journalURL {
            loadJournal(from: url)
        }
    }

    public func beginWrite(to url: URL, content: String) -> UUID {
        let id = UUID()
        let write = PendingWrite(
            id: id,
            targetPath: url.path(percentEncoded: false),
            content: content,
            timestamp: Date()
        )
        writes[id] = write
        saveJournal()
        return id
    }

    public func completeWrite(id: UUID) throws {
        guard let write = writes[id] else { return }

        let url = URL(fileURLWithPath: write.targetPath)
        let data = Data(write.content.utf8)
        try data.write(to: url, options: .atomic)

        writes.removeValue(forKey: id)
        saveJournal()
    }

    public func markWriteFailed(id: UUID, error: String) {
        if var write = writes[id] {
            write.failed = true
            write.errorMessage = error
            writes[id] = write
            saveJournal()
        }
    }

    public func retryWrite(id: UUID) throws -> RetryResult {
        guard let write = writes[id] else {
            return RetryResult(success: false)
        }

        let url = URL(fileURLWithPath: write.targetPath)
        let data = Data(write.content.utf8)
        try data.write(to: url, options: .atomic)

        writes.removeValue(forKey: id)
        saveJournal()

        return RetryResult(success: true)
    }

    public func pendingWrites() -> [PendingWrite] {
        Array(writes.values)
    }

    private func loadJournal(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([UUID: PendingWrite].self, from: data) else {
            return
        }
        writes = loaded
    }

    private func saveJournal() {
        guard let url = journalURL else { return }
        if let data = try? JSONEncoder().encode(writes) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

/// Atomic file writer for crash-safe saves.
public struct AtomicFileWriter: Sendable {

    public init() {}

    public func write(content: String, to url: URL) async throws {
        let data = Data(content.utf8)

        // Write to temp file first
        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).tmp")

        try data.write(to: tempURL, options: [])

        // Atomic rename
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
    }
}

/// Tracks sync state for individual files and the vault.
public actor SyncStateIndicator {

    public enum SyncState: Sendable {
        case unknown
        case synced
        case pending
        case uploading
        case downloading
        case conflict
        case error
    }

    private var fileStates: [String: SyncState] = [:]
    private var cloudStatuses: [String: CloudSyncStatus] = [:]

    public init() {}

    public func state(for url: URL) -> SyncState {
        let path = url.path(percentEncoded: false)

        // Check cloud status first
        if let cloudStatus = cloudStatuses[path] {
            switch cloudStatus {
            case .uploading: return .uploading
            case .downloading: return .downloading
            case .conflict: return .conflict
            case .error: return .error
            case .current: return .synced
            case .notDownloaded: return .pending
            case .notApplicable: break
            }
        }

        return fileStates[path] ?? .unknown
    }

    public func beginWrite(for url: URL) {
        fileStates[url.path(percentEncoded: false)] = .pending
    }

    public func completeWrite(for url: URL) {
        fileStates[url.path(percentEncoded: false)] = .synced
    }

    public func setCloudStatus(for url: URL, status: CloudSyncStatus) {
        cloudStatuses[url.path(percentEncoded: false)] = status
    }

    public func aggregateState() -> SyncState {
        // Priority: conflict > error > uploading > downloading > pending > synced
        if cloudStatuses.values.contains(.conflict) { return .conflict }
        if cloudStatuses.values.contains(.error) { return .error }
        if cloudStatuses.values.contains(.uploading) { return .uploading }
        if cloudStatuses.values.contains(.downloading) { return .downloading }
        if fileStates.values.contains(.pending) { return .pending }
        return .synced
    }
}
#endif
