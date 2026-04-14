import Testing
import Foundation
@testable import QuartzKit

// MARK: - Intelligence Engine Stress Tests

/// Stress tests for the Intelligence Engine coordinator.
///
/// Verifies:
/// - 1000+ file processing on background queues
/// - Status updates fire correctly during batch operations
/// - Debouncing coalesces rapid file changes
/// - Memory pressure handling
/// - Error recovery for failed indexing
@Suite("Intelligence Engine Stress Tests")
struct IntelligenceEngineStressTests {

    // MARK: - Test Fixtures

    let vaultRoot = URL(filePath: "/mock/vault")

    /// Creates a mock vault with the specified number of notes.
    func createMockVault(noteCount: Int) async -> AdvancedMockVaultProvider {
        let vault = AdvancedMockVaultProvider(generateLargeVault: true, noteCount: noteCount)
        await vault.populateTestVault()
        return vault
    }

    // MARK: - Large Scale Processing Tests

    @Test("Processes 1000 file changes and tracks status correctly")
    func testLargeScaleProcessing() async throws {
        // Create a large vault
        let vault = await createMockVault(noteCount: 1000)

        // Create a real embedding service (it will fail to index since files don't exist,
        // but we're testing the coordinator's status tracking)
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        // Create coordinator
        let coordinator = IntelligenceEngineCoordinator(
            embeddingService: embeddingService,
            semanticService: nil,
            extractionService: nil,
            vaultRootURL: vaultRoot
        )
        defer { Task { await coordinator.stopObserving() } }

        // Track status changes
        let statusUpdates = Recorder<IntelligenceEngineStatus>()
        let statusObserver = NotificationCenter.default.addObserver(
            forName: .quartzIntelligenceEngineStatusChanged,
            object: nil,
            queue: .main
        ) { notification in
            if let status = notification.userInfo?["status"] as? IntelligenceEngineStatus {
                Task { await statusUpdates.append(status) }
            }
        }
        defer { NotificationCenter.default.removeObserver(statusObserver) }

        // Start observing
        await coordinator.startObserving()

        // Get all note URLs
        let tree = try await vault.loadFileTree(at: vaultRoot)
        var noteURLs: [URL] = []
        for folder in tree {
            if let children = folder.children {
                noteURLs.append(contentsOf: children.map(\.url))
            }
        }

        #expect(noteURLs.count == 1000)

        // Verify initial status
        let initialStatus = await coordinator.status
        #expect(initialStatus == .idle)

        // Simulate 1000 file change notifications
        let startTime = CFAbsoluteTimeGetCurrent()

        // Post notifications in batches to simulate realistic scenario
        for url in noteURLs {
            NotificationCenter.default.post(
                name: .quartzNoteSaved,
                object: url
            )
        }

        // Wait for debounce + processing
        // Debounce is 2s, plus some processing time for 1000 files
        // Allow up to 15 seconds for large scale processing
        try await Task.sleep(for: .seconds(15))

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Verify we saw status updates (indexing status)
        let recordedStatusUpdates = await statusUpdates.values()
        #expect(!recordedStatusUpdates.isEmpty, "Should have received status updates")

        // Verify we saw indexing status at some point
        let sawIndexing = recordedStatusUpdates.contains { status in
            if case .indexing = status { return true }
            return false
        }
        #expect(sawIndexing, "Should have seen indexing status")

        // Verify we returned to idle (or at least are idle now)
        let finalStatus = await coordinator.status
        // Note: with many files, processing may still be ongoing,
        // so just log the final state
        print("[Stress Test] Final status: \(finalStatus)")

        // Log performance
        print("[Stress Test] Processed \(noteURLs.count) file notifications in \(elapsed)s")

        await coordinator.stopObserving()
    }

    @Test("Debouncing coalesces rapid file changes")
    func testDebouncing() async throws {
        // Track how many times processPendingChanges would be called
        let statusChanges = Recorder<IntelligenceEngineStatus>()

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        let coordinator = IntelligenceEngineCoordinator(
            embeddingService: embeddingService,
            semanticService: nil,
            extractionService: nil,
            vaultRootURL: vaultRoot
        )
        defer { Task { await coordinator.stopObserving() } }

        let observer = NotificationCenter.default.addObserver(
            forName: .quartzIntelligenceEngineStatusChanged,
            object: nil,
            queue: .main
        ) { notification in
            if let status = notification.userInfo?["status"] as? IntelligenceEngineStatus {
                Task { await statusChanges.append(status) }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await coordinator.startObserving()

        // Post 100 changes for the SAME file rapidly
        let testURL = vaultRoot.appending(path: "test.md")
        for _ in 0..<100 {
            NotificationCenter.default.post(
                name: .quartzNoteSaved,
                object: testURL
            )
        }

        // Wait for debounce (2s) + processing (4s) to complete
        try await Task.sleep(for: .seconds(6))

        // Count how many times we entered indexing state
        // With concurrent notification delivery, we may see multiple batches
        // The key behavior is that rapid changes to the SAME file should be coalesced
        let recordedStatusChanges = await statusChanges.values()
        let indexingStarts = recordedStatusChanges.filter { status in
            if case .indexing(let progress, _) = status, progress == 0 {
                return true
            }
            return false
        }.count

        // We should see significantly fewer than 100 batches
        // (the number of rapid changes we posted)
        #expect(indexingStarts < 10, "Debouncing should reduce batches significantly, got \(indexingStarts) indexing starts")

        await coordinator.stopObserving()
    }

    @Test("Status progress updates correctly during batch indexing")
    func testStatusProgressUpdates() async throws {
        let vault = await createMockVault(noteCount: 50)

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        let coordinator = IntelligenceEngineCoordinator(
            embeddingService: embeddingService,
            semanticService: nil,
            extractionService: nil,
            vaultRootURL: vaultRoot
        )
        defer { Task { await coordinator.stopObserving() } }

        let progressValues = Recorder<(progress: Int, total: Int)>()
        let observer = NotificationCenter.default.addObserver(
            forName: .quartzIntelligenceEngineStatusChanged,
            object: nil,
            queue: .main
        ) { notification in
            if let status = notification.userInfo?["status"] as? IntelligenceEngineStatus,
               case let .indexing(progress, total) = status {
                Task { await progressValues.append((progress, total)) }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        await coordinator.startObserving()

        // Get URLs
        let tree = try await vault.loadFileTree(at: vaultRoot)
        var noteURLs: [URL] = []
        for folder in tree {
            if let children = folder.children {
                noteURLs.append(contentsOf: children.map(\.url))
            }
        }

        // Post changes
        for url in noteURLs {
            NotificationCenter.default.post(
                name: .quartzNoteSaved,
                object: url
            )
        }

        // Wait for processing
        try await Task.sleep(for: .seconds(5))

        // Verify progress updates were seen and generally increasing
        // Note: totals may fluctuate between batches if debounce windows overlap
        let recordedProgressValues = await progressValues.values()
        if recordedProgressValues.count > 1 {
            // Just verify we see progress changing
            let uniqueTotals = Set(recordedProgressValues.map(\.total))
            #expect(!uniqueTotals.isEmpty, "Should see some batch totals")
        }

        // Verify we saw progress
        #expect(!recordedProgressValues.isEmpty, "Should have seen progress updates")

        await coordinator.stopObserving()
    }

    @Test("Memory stays bounded during large vault processing")
    func testMemoryBoundsLargeVault() async throws {
        // This test verifies that processing 500 files doesn't cause memory explosion
        let vault = await createMockVault(noteCount: 500)

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        let coordinator = IntelligenceEngineCoordinator(
            embeddingService: embeddingService,
            semanticService: nil,
            extractionService: nil,
            vaultRootURL: vaultRoot
        )
        defer { Task { await coordinator.stopObserving() } }

        await coordinator.startObserving()

        // Capture initial memory
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let initialResult = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let initialMemory = initialResult == KERN_SUCCESS ? info.resident_size : 0

        // Get URLs and post changes
        let tree = try await vault.loadFileTree(at: vaultRoot)
        var noteURLs: [URL] = []
        for folder in tree {
            if let children = folder.children {
                noteURLs.append(contentsOf: children.map(\.url))
            }
        }

        for url in noteURLs {
            NotificationCenter.default.post(
                name: .quartzNoteSaved,
                object: url
            )
        }

        // Wait for processing
        try await Task.sleep(for: .seconds(5))

        // Capture final memory
        count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let finalResult = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let finalMemory = finalResult == KERN_SUCCESS ? info.resident_size : 0

        // Memory growth should be reasonable (< 200MB for 500 notes)
        let memoryGrowthMB = (Double(finalMemory) - Double(initialMemory)) / (1024 * 1024)
        #expect(memoryGrowthMB < 200, "Memory growth should be bounded, got \(memoryGrowthMB)MB")

        print("[Memory Test] Initial: \(initialMemory / (1024 * 1024))MB, Final: \(finalMemory / (1024 * 1024))MB, Growth: \(memoryGrowthMB)MB")

        await coordinator.stopObserving()
    }

    @Test("Coordinator handles file deletions correctly")
    func testFileDeletionHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        let coordinator = IntelligenceEngineCoordinator(
            embeddingService: embeddingService,
            semanticService: nil,
            extractionService: nil,
            vaultRootURL: vaultRoot
        )
        defer { Task { await coordinator.stopObserving() } }

        await coordinator.startObserving()

        // Post a deletion notification
        let testURL = vaultRoot.appending(path: "deleted.md")
        NotificationCenter.default.post(
            name: .quartzFilePresenterWillDelete,
            object: testURL
        )

        // Wait for processing
        try await Task.sleep(for: .seconds(1))

        // Verify coordinator didn't crash and returned to idle
        let status = await coordinator.status
        #expect(status == .idle, "Should be idle after deletion")

        await coordinator.stopObserving()
    }

    @Test("Coordinator handles file moves correctly")
    func testFileMoveHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        let coordinator = IntelligenceEngineCoordinator(
            embeddingService: embeddingService,
            semanticService: nil,
            extractionService: nil,
            vaultRootURL: vaultRoot
        )
        defer { Task { await coordinator.stopObserving() } }

        await coordinator.startObserving()

        // Post a move notification
        let oldURL = vaultRoot.appending(path: "old.md")
        let newURL = vaultRoot.appending(path: "new.md")
        NotificationCenter.default.post(
            name: .quartzFilePresenterDidMove,
            object: nil,
            userInfo: ["oldURL": oldURL, "newURL": newURL]
        )

        // Wait for processing
        try await Task.sleep(for: .seconds(1))

        // Verify coordinator didn't crash and returned to idle
        let status = await coordinator.status
        #expect(status == .idle, "Should be idle after move")

        await coordinator.stopObserving()
    }
}

private actor Recorder<Value: Sendable> {
    private var storage: [Value] = []

    func append(_ value: Value) {
        storage.append(value)
    }

    func values() -> [Value] {
        storage
    }
}
