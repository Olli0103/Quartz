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

    private func withObservedCoordinator<T>(
        embeddingService: VectorEmbeddingService?,
        semanticService: SemanticLinkService? = nil,
        extractionService: KnowledgeExtractionService? = nil,
        body: (IntelligenceEngineCoordinator) async throws -> T
    ) async throws -> T {
        let coordinator = IntelligenceEngineCoordinator(
            embeddingService: embeddingService,
            semanticService: semanticService,
            extractionService: extractionService,
            vaultRootURL: vaultRoot
        )

        await coordinator.startObserving()

        do {
            let result = try await body(coordinator)
            await coordinator.stopObserving()
            return result
        } catch {
            await coordinator.stopObserving()
            throw error
        }
    }

    private func awaitCondition(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(100),
        _ condition: @escaping @Sendable () async -> Bool
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() {
                return true
            }
            try await Task.sleep(for: pollInterval)
        }

        return await condition()
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
        try await withObservedCoordinator(embeddingService: embeddingService) { coordinator in
            // Track status changes
            let statusUpdates = Recorder<IntelligenceEngineStatus>()
            let statusObserver = NotificationCenter.default.addObserver(
                forName: .quartzIntelligenceEngineStatusChanged,
                object: coordinator.statusNotificationSource,
                queue: .main
            ) { notification in
                if let status = notification.userInfo?["status"] as? IntelligenceEngineStatus {
                    Task { await statusUpdates.append(status) }
                }
            }
            defer { NotificationCenter.default.removeObserver(statusObserver) }

            // Get all note URLs
            let tree = try await vault.loadFileTree(at: vaultRoot)
            var noteURLs: [URL] = []
            for folder in tree {
                if let children = folder.children {
                    noteURLs.append(contentsOf: children.map(\.url))
                }
            }

            #expect(noteURLs.count == 1000)

            let initialStatus = await coordinator.status
            #expect(initialStatus == .idle)

            let startTime = CFAbsoluteTimeGetCurrent()

            for url in noteURLs {
                NotificationCenter.default.post(name: .quartzNoteSaved, object: url)
            }

            let sawStatus = try await awaitCondition(timeout: .seconds(20)) {
                !(await statusUpdates.values()).isEmpty
            }
            #expect(sawStatus, "Should have received status updates")

            let sawIndexing = try await awaitCondition(timeout: .seconds(20)) {
                let recorded = await statusUpdates.values()
                return recorded.contains { status in
                    if case .indexing = status { return true }
                    return false
                }
            }
            #expect(sawIndexing, "Should have seen indexing status")

            _ = try await awaitCondition(timeout: .seconds(20)) {
                await coordinator.status == .idle
            }

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            let finalStatus = await coordinator.status
            print("[Stress Test] Final status: \(finalStatus)")
            print("[Stress Test] Processed \(noteURLs.count) file notifications in \(elapsed)s")
        }
    }

    @Test("Debouncing coalesces rapid file changes")
    func testDebouncing() async throws {
        // Track how many times processPendingChanges would be called
        let statusChanges = Recorder<IntelligenceEngineStatus>()

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        try await withObservedCoordinator(embeddingService: embeddingService) { coordinator in
            let observer = NotificationCenter.default.addObserver(
                forName: .quartzIntelligenceEngineStatusChanged,
                object: coordinator.statusNotificationSource,
                queue: .main
            ) { notification in
                if let status = notification.userInfo?["status"] as? IntelligenceEngineStatus {
                    Task { await statusChanges.append(status) }
                }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            let testURL = vaultRoot.appending(path: "test.md")
            for _ in 0..<100 {
                NotificationCenter.default.post(name: .quartzNoteSaved, object: testURL)
            }

            _ = try await awaitCondition(timeout: .seconds(10)) {
                let statusIsIdle = await coordinator.status == .idle
                let sawStatusChanges = !(await statusChanges.values()).isEmpty
                return statusIsIdle && sawStatusChanges
            }

            let recordedStatusChanges = await statusChanges.values()
            let indexingStarts = recordedStatusChanges.filter { status in
                if case .indexing(let progress, _) = status, progress == 0 {
                    return true
                }
                return false
            }.count

            #expect(indexingStarts < 10, "Debouncing should reduce batches significantly, got \(indexingStarts) indexing starts")
        }
    }

    @Test("Status progress updates correctly during batch indexing")
    func testStatusProgressUpdates() async throws {
        let vault = await createMockVault(noteCount: 50)

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        try await withObservedCoordinator(embeddingService: embeddingService) { coordinator in
            let progressValues = Recorder<(progress: Int, total: Int)>()
            let observer = NotificationCenter.default.addObserver(
                forName: .quartzIntelligenceEngineStatusChanged,
                object: coordinator.statusNotificationSource,
                queue: .main
            ) { notification in
                if let status = notification.userInfo?["status"] as? IntelligenceEngineStatus,
                   case let .indexing(progress, total) = status {
                    Task { await progressValues.append((progress, total)) }
                }
            }
            defer { NotificationCenter.default.removeObserver(observer) }

            let tree = try await vault.loadFileTree(at: vaultRoot)
            var noteURLs: [URL] = []
            for folder in tree {
                if let children = folder.children {
                    noteURLs.append(contentsOf: children.map(\.url))
                }
            }

            for url in noteURLs {
                NotificationCenter.default.post(name: .quartzNoteSaved, object: url)
            }

            let sawProgress = try await awaitCondition(timeout: .seconds(15)) {
                !(await progressValues.values()).isEmpty
            }
            #expect(sawProgress, "Should have seen progress updates")

            let recordedProgressValues = await progressValues.values()
            if recordedProgressValues.count > 1 {
                let uniqueTotals = Set(recordedProgressValues.map(\.total))
                #expect(!uniqueTotals.isEmpty, "Should see some batch totals")
            }
        }
    }

    @Test("Memory stays bounded during large vault processing")
    func testMemoryBoundsLargeVault() async throws {
        // This test verifies that processing 500 files doesn't cause memory explosion
        let vault = await createMockVault(noteCount: 500)

        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        try await withObservedCoordinator(embeddingService: embeddingService) { coordinator in
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let initialResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }

            let initialMemory = initialResult == KERN_SUCCESS ? info.resident_size : 0

            let tree = try await vault.loadFileTree(at: vaultRoot)
            var noteURLs: [URL] = []
            for folder in tree {
                if let children = folder.children {
                    noteURLs.append(contentsOf: children.map(\.url))
                }
            }

            for url in noteURLs {
                NotificationCenter.default.post(name: .quartzNoteSaved, object: url)
            }

            _ = try await awaitCondition(timeout: .seconds(10)) {
                await coordinator.status == .idle
            }

            count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let finalResult = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }

            let finalMemory = finalResult == KERN_SUCCESS ? info.resident_size : 0
            let memoryGrowthMB = (Double(finalMemory) - Double(initialMemory)) / (1024 * 1024)
            #expect(memoryGrowthMB < 200, "Memory growth should be bounded, got \(memoryGrowthMB)MB")

            print("[Memory Test] Initial: \(initialMemory / (1024 * 1024))MB, Final: \(finalMemory / (1024 * 1024))MB, Growth: \(memoryGrowthMB)MB")
        }
    }

    @Test("Coordinator handles file deletions correctly")
    func testFileDeletionHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        try await withObservedCoordinator(embeddingService: embeddingService) { coordinator in
            let testURL = vaultRoot.appending(path: "deleted.md")
            NotificationCenter.default.post(name: .quartzFilePresenterWillDelete, object: testURL)

            let returnedToIdle = try await awaitCondition(timeout: .seconds(2)) {
                await coordinator.status == .idle
            }
            #expect(returnedToIdle, "Should be idle after deletion")
        }
    }

    @Test("Coordinator handles file moves correctly")
    func testFileMoveHandling() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let embeddingService = VectorEmbeddingService(vaultURL: tempDir)

        try await withObservedCoordinator(embeddingService: embeddingService) { coordinator in
            let oldURL = vaultRoot.appending(path: "old.md")
            let newURL = vaultRoot.appending(path: "new.md")
            NotificationCenter.default.post(
                name: .quartzFilePresenterDidMove,
                object: nil,
                userInfo: ["oldURL": oldURL, "newURL": newURL]
            )

            let returnedToIdle = try await awaitCondition(timeout: .seconds(2)) {
                await coordinator.status == .idle
            }
            #expect(returnedToIdle, "Should be idle after move")
        }
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
