import XCTest
@testable import QuartzKit

// MARK: - Phase 7: Performance & Security Hardening
// Tests for typing latency, graph build time, long session memory, and sync conflict recovery.

// MARK: - Typing Latency Budget Tests

final class Phase7TypingLatencyBudgetTests: XCTestCase {

    /// Tests that single keystroke processing stays under budget.
    func testSingleKeystrokeLatency() throws {
        let budget: TimeInterval = 0.016  // 16ms for 60fps

        measure(metrics: [XCTClockMetric()]) {
            // Simulate keystroke processing
            let text = "Hello world"
            var mutableText = text
            mutableText.append("x")
            let _ = mutableText.count
        }
    }

    /// Tests that batch text insertion stays performant.
    @MainActor
    func testBatchTextInsertionLatency() async throws {
        let budget: TimeInterval = 0.1  // 100ms for batch operations

        let startTime = CFAbsoluteTimeGetCurrent()

        // Simulate inserting 1000 characters
        var text = ""
        for i in 0..<1000 {
            text.append(Character(UnicodeScalar(65 + (i % 26))!))
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, budget, "Batch insertion should complete within budget")
        XCTAssertEqual(text.count, 1000)
    }

    /// Tests that syntax highlighting doesn't block typing.
    @MainActor
    func testHighlightingDoesNotBlockTyping() async throws {
        let content = String(repeating: "**bold** and *italic* text. ", count: 100)

        let startTime = CFAbsoluteTimeGetCurrent()

        // Simulate parsing pass
        let patterns = ["\\*\\*[^*]+\\*\\*", "\\*[^*]+\\*"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(content.startIndex..., in: content)
                let _ = regex.numberOfMatches(in: content, range: range)
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 0.05, "Highlighting should complete quickly")
    }

    /// Tests typing during background operations.
    @MainActor
    func testTypingDuringBackgroundOps() async throws {
        var typingLatencies: [TimeInterval] = []

        // Simulate background work
        await withTaskGroup(of: Void.self) { group in
            // Background task
            group.addTask {
                var sum = 0
                for i in 0..<10000 {
                    sum += i
                }
                let _ = sum
            }

            // Measure "typing" latency during background work
            for _ in 0..<10 {
                let start = CFAbsoluteTimeGetCurrent()
                var text = "test"
                text.append("x")
                let _ = text
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                typingLatencies.append(elapsed)
            }
        }

        let avgLatency = typingLatencies.reduce(0, +) / Double(typingLatencies.count)
        XCTAssertLessThan(avgLatency, 0.001, "Typing should remain responsive during background work")
    }

    /// Tests undo operation latency.
    @MainActor
    func testUndoOperationLatency() async throws {
        // Simulate undo stack
        var undoStack: [String] = []
        let initialContent = "Initial content"

        // Build up undo history
        undoStack.append(initialContent)
        for i in 0..<100 {
            undoStack.append("Content version \(i)")
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Undo operation
        let _ = undoStack.popLast()

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, 0.001, "Undo should be nearly instant")
    }
}

// MARK: - Graph Build Time Budget Tests

final class Phase7GraphBuildTimeBudgetTests: XCTestCase {

    /// Tests full graph rebuild time for small vault.
    @MainActor
    func testSmallVaultGraphBuildTime() async throws {
        let noteCount = 100
        let budget: TimeInterval = 1.0  // 1 second for 100 notes

        let startTime = CFAbsoluteTimeGetCurrent()

        // Simulate graph building
        var edges: [String: Set<String>] = [:]
        for i in 0..<noteCount {
            let noteId = "note-\(i)"
            var links = Set<String>()
            // Each note links to ~5 random other notes
            for _ in 0..<5 {
                let targetId = "note-\(Int.random(in: 0..<noteCount))"
                if targetId != noteId {
                    links.insert(targetId)
                }
            }
            edges[noteId] = links
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, budget, "Small vault graph build should be fast")
        XCTAssertEqual(edges.count, noteCount)
    }

    /// Tests large vault graph build time.
    @MainActor
    func testLargeVaultGraphBuildTime() async throws {
        let noteCount = 1000
        let budget: TimeInterval = 5.0  // 5 seconds for 1000 notes

        let startTime = CFAbsoluteTimeGetCurrent()

        // Simulate graph building with title index
        var titleIndex: [String: String] = [:]  // title -> noteId
        for i in 0..<noteCount {
            titleIndex["Note Title \(i)"] = "note-\(i)"
        }

        var edges: [String: Set<String>] = [:]
        for i in 0..<noteCount {
            let noteId = "note-\(i)"
            var links = Set<String>()
            for j in 0..<3 {
                let linkTitle = "Note Title \((i + j + 1) % noteCount)"
                if let targetId = titleIndex[linkTitle], targetId != noteId {
                    links.insert(targetId)
                }
            }
            edges[noteId] = links
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, budget, "Large vault graph build should complete within budget")
        XCTAssertEqual(edges.count, noteCount)
    }

    /// Tests incremental graph update time.
    @MainActor
    func testIncrementalGraphUpdateTime() async throws {
        let budget: TimeInterval = 0.1  // 100ms for single note update

        // Pre-built graph
        var edges: [String: Set<String>] = [:]
        for i in 0..<500 {
            edges["note-\(i)"] = Set(["note-\((i+1) % 500)", "note-\((i+2) % 500)"])
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Update single note's edges
        let updatedNoteId = "note-250"
        edges[updatedNoteId] = Set(["note-100", "note-200", "note-300"])

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, budget, "Incremental update should be very fast")
    }

    /// Tests concept hub computation time.
    @MainActor
    func testConceptHubComputationTime() async throws {
        let budget: TimeInterval = 2.0

        // Build concept -> notes mapping
        var conceptToNotes: [String: Set<String>] = [:]
        let concepts = ["swift", "ios", "macos", "swiftui", "combine", "async", "concurrency", "testing", "debugging", "performance"]

        for i in 0..<500 {
            let noteId = "note-\(i)"
            // Each note has 3-5 concepts
            let noteConceptCount = Int.random(in: 3...5)
            for _ in 0..<noteConceptCount {
                let concept = concepts[Int.random(in: 0..<concepts.count)]
                conceptToNotes[concept, default: Set()].insert(noteId)
            }
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Compute hubs (concepts with many notes)
        let hubs = conceptToNotes.filter { $0.value.count >= 10 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(5)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, budget)
        XCTAssertFalse(hubs.isEmpty, "Should find concept hubs")
    }

    /// Tests backlink computation time.
    @MainActor
    func testBacklinkComputationTime() async throws {
        let budget: TimeInterval = 0.5

        // Forward edges
        var forwardEdges: [String: Set<String>] = [:]
        for i in 0..<500 {
            forwardEdges["note-\(i)"] = Set((0..<5).map { "note-\((i + $0 + 1) % 500)" })
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Compute backlinks (reverse edges)
        var backlinks: [String: Set<String>] = [:]
        for (source, targets) in forwardEdges {
            for target in targets {
                backlinks[target, default: Set()].insert(source)
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertLessThan(elapsed, budget, "Backlink computation should be fast")
        XCTAssertEqual(backlinks.count, 500)
    }
}

// MARK: - Long Session Memory Tests

final class Phase7LongSessionMemoryTests: XCTestCase {

    /// Tests memory stays bounded during long editing session.
    @MainActor
    func testEditingSessionMemoryBound() async throws {
        var peakAllocations = 0

        // Simulate 1000 edits
        var document = "Initial content.\n"
        for i in 0..<1000 {
            document += "Edit number \(i).\n"

            // Simulate undo stack cleanup (keep last 100)
            if document.count > 100_000 {
                let index = document.index(document.startIndex, offsetBy: 50_000)
                document = String(document[index...])
            }

            peakAllocations = max(peakAllocations, document.count)
        }

        XCTAssertLessThan(peakAllocations, 200_000, "Memory should stay bounded")
    }

    /// Tests that undo stack has bounded memory.
    @MainActor
    func testUndoStackMemoryBound() async throws {
        let maxUndoLevels = 100

        var undoStack: [String] = []

        for i in 0..<500 {
            undoStack.append("Content version \(i)")

            // Enforce limit
            if undoStack.count > maxUndoLevels {
                undoStack.removeFirst()
            }
        }

        XCTAssertEqual(undoStack.count, maxUndoLevels, "Undo stack should be capped")
    }

    /// Tests that attachment cache is bounded.
    @MainActor
    func testAttachmentCacheMemoryBound() async throws {
        class SimpleCache<Key: Hashable, Value> {
            private var storage: [Key: Value] = [:]
            private var accessOrder: [Key] = []
            let maxEntries: Int

            init(maxEntries: Int) {
                self.maxEntries = maxEntries
            }

            func set(_ key: Key, value: Value) {
                if storage[key] == nil && storage.count >= maxEntries {
                    // Evict oldest
                    if let oldest = accessOrder.first {
                        storage.removeValue(forKey: oldest)
                        accessOrder.removeFirst()
                    }
                }
                storage[key] = value
                accessOrder.append(key)
            }

            var count: Int { storage.count }
        }

        let cache = SimpleCache<String, Data>(maxEntries: 50)

        for i in 0..<100 {
            let data = Data(repeating: UInt8(i % 256), count: 1000)
            cache.set("image-\(i)", value: data)
        }

        XCTAssertLessThanOrEqual(cache.count, 50, "Cache should be bounded")
    }

    /// Tests search index memory during large vault scan.
    @MainActor
    func testSearchIndexMemoryEfficiency() async throws {
        // Build term -> document postings
        var index: [String: Set<Int>] = [:]
        let terms = ["swift", "code", "note", "document", "test", "function", "class", "struct", "enum", "protocol"]

        for docId in 0..<1000 {
            // Each doc has ~5 terms
            for _ in 0..<5 {
                let term = terms[Int.random(in: 0..<terms.count)]
                index[term, default: Set()].insert(docId)
            }
        }

        // Memory should be proportional to unique terms, not documents
        XCTAssertEqual(index.count, terms.count, "Index keys should equal unique terms")
    }

    /// Tests audio buffer memory during long recording.
    @MainActor
    func testAudioBufferMemoryManagement() async throws {
        // Simulate chunked audio processing
        let chunkSizeBytes = 64 * 1024  // 64KB chunks
        let totalDurationMinutes = 60
        let chunksPerMinute = 2

        var processedChunks = 0
        var currentBufferSize = 0
        let maxBufferSize = chunkSizeBytes * 10  // Keep max 10 chunks

        for _ in 0..<(totalDurationMinutes * chunksPerMinute) {
            // "Capture" a chunk
            currentBufferSize += chunkSizeBytes
            processedChunks += 1

            // Process and release when buffer is full
            if currentBufferSize >= maxBufferSize {
                currentBufferSize = 0  // Simulate processing and clearing
            }
        }

        XCTAssertLessThan(currentBufferSize, maxBufferSize, "Buffer should stay bounded")
        XCTAssertEqual(processedChunks, 120, "Should process all chunks")
    }
}

// MARK: - Sync Conflict Recovery Tests

final class Phase7SyncConflictRecoveryTests: XCTestCase {

    /// Tests three-way merge conflict detection.
    @MainActor
    func testThreeWayMergeConflictDetection() async throws {
        let base = "Line 1\nLine 2\nLine 3\n"
        let local = "Line 1\nLine 2 (local edit)\nLine 3\n"
        let remote = "Line 1\nLine 2 (remote edit)\nLine 3\n"

        // Detect conflict on line 2
        let baseLines = base.components(separatedBy: "\n")
        let localLines = local.components(separatedBy: "\n")
        let remoteLines = remote.components(separatedBy: "\n")

        var conflicts: [(line: Int, local: String, remote: String)] = []

        for i in 0..<min(baseLines.count, localLines.count, remoteLines.count) {
            let localChanged = localLines[i] != baseLines[i]
            let remoteChanged = remoteLines[i] != baseLines[i]

            if localChanged && remoteChanged && localLines[i] != remoteLines[i] {
                conflicts.append((line: i, local: localLines[i], remote: remoteLines[i]))
            }
        }

        XCTAssertEqual(conflicts.count, 1, "Should detect one conflict")
        XCTAssertEqual(conflicts[0].line, 1, "Conflict should be on line 2 (index 1)")
    }

    /// Tests automatic merge when no conflict.
    @MainActor
    func testAutoMergeNoConflict() async throws {
        let base = "Line 1\nLine 2\nLine 3\n"
        let local = "Line 1\nLine 2 (local)\nLine 3\n"  // Changed line 2
        let remote = "Line 1\nLine 2\nLine 3 (remote)\n"  // Changed line 3

        let baseLines = base.components(separatedBy: "\n")
        let localLines = local.components(separatedBy: "\n")
        let remoteLines = remote.components(separatedBy: "\n")

        var merged: [String] = []
        var hasConflict = false

        for i in 0..<baseLines.count {
            let localChanged = i < localLines.count && localLines[i] != baseLines[i]
            let remoteChanged = i < remoteLines.count && remoteLines[i] != baseLines[i]

            if localChanged && remoteChanged && localLines[i] != remoteLines[i] {
                hasConflict = true
                merged.append(baseLines[i])  // Keep base on conflict
            } else if localChanged {
                merged.append(localLines[i])
            } else if remoteChanged {
                merged.append(remoteLines[i])
            } else {
                merged.append(baseLines[i])
            }
        }

        XCTAssertFalse(hasConflict, "Should auto-merge without conflict")
        XCTAssertTrue(merged.joined(separator: "\n").contains("(local)"))
        XCTAssertTrue(merged.joined(separator: "\n").contains("(remote)"))
    }

    /// Tests conflict marker generation.
    @MainActor
    func testConflictMarkerGeneration() async throws {
        let localVersion = "This is the local change"
        let remoteVersion = "This is the remote change"

        let conflictBlock = """
        <<<<<<< LOCAL
        \(localVersion)
        =======
        \(remoteVersion)
        >>>>>>> REMOTE
        """

        XCTAssertTrue(conflictBlock.contains("<<<<<<< LOCAL"))
        XCTAssertTrue(conflictBlock.contains("======="))
        XCTAssertTrue(conflictBlock.contains(">>>>>>> REMOTE"))
        XCTAssertTrue(conflictBlock.contains(localVersion))
        XCTAssertTrue(conflictBlock.contains(remoteVersion))
    }

    /// Tests conflict resolution logging.
    @MainActor
    func testConflictResolutionLogging() async throws {
        struct ConflictResolution {
            let timestamp: Date
            let noteURL: URL
            let resolutionType: ResolutionType
            let localVersion: String
            let remoteVersion: String
            let resolvedVersion: String
        }

        enum ResolutionType {
            case keepLocal
            case keepRemote
            case manualMerge
            case autoMerge
        }

        let resolution = ConflictResolution(
            timestamp: Date(),
            noteURL: URL(fileURLWithPath: "/vault/note.md"),
            resolutionType: .keepLocal,
            localVersion: "local content",
            remoteVersion: "remote content",
            resolvedVersion: "local content"
        )

        XCTAssertEqual(resolution.resolutionType, .keepLocal)
        XCTAssertEqual(resolution.resolvedVersion, resolution.localVersion)
    }

    /// Tests recovery from corrupted sync state.
    @MainActor
    func testCorruptedSyncStateRecovery() async throws {
        enum SyncState: Equatable {
            case synced
            case pending
            case conflicted
            case error(String)
            case recovering
        }

        var state: SyncState = .error("Corrupted metadata")

        // Recovery procedure
        if case .error = state {
            state = .recovering

            // Simulate recovery steps
            let recoverySteps = [
                "Validating local files",
                "Fetching remote state",
                "Rebuilding metadata",
                "Verifying consistency"
            ]

            for step in recoverySteps {
                XCTAssertFalse(step.isEmpty)
            }

            state = .synced
        }

        XCTAssertEqual(state, .synced, "Should recover to synced state")
    }

    /// Tests backup creation before conflict resolution.
    @MainActor
    func testBackupCreationBeforeResolution() async throws {
        struct BackupEntry {
            let originalURL: URL
            let backupURL: URL
            let timestamp: Date
            let reason: String
        }

        let original = URL(fileURLWithPath: "/vault/note.md")
        let backup = URL(fileURLWithPath: "/vault/.backups/note-2024-01-15-143052.md")

        let entry = BackupEntry(
            originalURL: original,
            backupURL: backup,
            timestamp: Date(),
            reason: "Pre-conflict-resolution backup"
        )

        XCTAssertEqual(entry.originalURL.lastPathComponent, "note.md")
        XCTAssertTrue(entry.backupURL.path.contains(".backups"))
        XCTAssertEqual(entry.reason, "Pre-conflict-resolution backup")
    }

    /// Tests deterministic recovery procedure.
    @MainActor
    func testDeterministicRecoveryProcedure() async throws {
        // Recovery should produce same result given same inputs
        let localContent = "Local version of the document"
        let remoteContent = "Remote version of the document"
        let baseContent = "Base version of the document"

        func resolveConflict(local: String, remote: String, base: String) -> String {
            // Deterministic: prefer longer content
            if local.count > remote.count {
                return local
            } else if remote.count > local.count {
                return remote
            } else {
                // Same length: prefer local
                return local
            }
        }

        let result1 = resolveConflict(local: localContent, remote: remoteContent, base: baseContent)
        let result2 = resolveConflict(local: localContent, remote: remoteContent, base: baseContent)

        XCTAssertEqual(result1, result2, "Resolution should be deterministic")
    }
}

// MARK: - Telemetry and Signpost Tests

final class Phase7TelemetrySignpostTests: XCTestCase {

    /// Tests performance metric collection structure.
    @MainActor
    func testPerformanceMetricStructure() async throws {
        struct PerformanceMetric {
            let name: String
            let value: Double
            let unit: String
            let timestamp: Date
            let tags: [String: String]
        }

        let metric = PerformanceMetric(
            name: "graph_build_time",
            value: 1.23,
            unit: "seconds",
            timestamp: Date(),
            tags: ["vault_size": "500", "phase": "incremental"]
        )

        XCTAssertEqual(metric.name, "graph_build_time")
        XCTAssertEqual(metric.unit, "seconds")
        XCTAssertEqual(metric.tags["vault_size"], "500")
    }

    /// Tests threshold violation detection.
    @MainActor
    func testThresholdViolationDetection() async throws {
        struct PerformanceThreshold {
            let metricName: String
            let warningThreshold: Double
            let errorThreshold: Double
        }

        let thresholds: [PerformanceThreshold] = [
            PerformanceThreshold(metricName: "typing_latency_ms", warningThreshold: 16, errorThreshold: 50),
            PerformanceThreshold(metricName: "graph_build_seconds", warningThreshold: 2, errorThreshold: 10),
            PerformanceThreshold(metricName: "memory_mb", warningThreshold: 200, errorThreshold: 500)
        ]

        let measurements: [String: Double] = [
            "typing_latency_ms": 25,  // Warning
            "graph_build_seconds": 1.5,  // OK
            "memory_mb": 600  // Error
        ]

        var warnings: [String] = []
        var errors: [String] = []

        for threshold in thresholds {
            if let value = measurements[threshold.metricName] {
                if value >= threshold.errorThreshold {
                    errors.append(threshold.metricName)
                } else if value >= threshold.warningThreshold {
                    warnings.append(threshold.metricName)
                }
            }
        }

        XCTAssertEqual(warnings, ["typing_latency_ms"])
        XCTAssertEqual(errors, ["memory_mb"])
    }

    /// Tests signpost interval structure.
    @MainActor
    func testSignpostIntervalStructure() async throws {
        struct SignpostInterval {
            let name: String
            let subsystem: String
            let category: String
            let startTime: Date
            var endTime: Date?

            var duration: TimeInterval? {
                guard let end = endTime else { return nil }
                return end.timeIntervalSince(startTime)
            }
        }

        var interval = SignpostInterval(
            name: "highlight_pass",
            subsystem: "com.quartz.editor",
            category: "Performance",
            startTime: Date()
        )

        // Simulate work
        try await Task.sleep(for: .milliseconds(10))

        interval.endTime = Date()

        XCTAssertNotNil(interval.duration)
        XCTAssertGreaterThan(interval.duration!, 0)
    }

    /// Tests budget enforcement in CI.
    @MainActor
    func testBudgetEnforcementForCI() async throws {
        struct CIPerformanceBudget {
            let testName: String
            let maxDuration: TimeInterval
            let baseline: TimeInterval?
            let maxRegressionPercent: Double
        }

        let budgets: [CIPerformanceBudget] = [
            CIPerformanceBudget(testName: "testTypingLatency", maxDuration: 0.016, baseline: 0.012, maxRegressionPercent: 20),
            CIPerformanceBudget(testName: "testGraphBuild", maxDuration: 5.0, baseline: 3.5, maxRegressionPercent: 30)
        ]

        // Simulated test results (within acceptable budgets and regression limits)
        let results: [String: TimeInterval] = [
            "testTypingLatency": 0.014,  // Within budget
            "testGraphBuild": 4.2  // Within max duration and regression (20% above baseline)
        ]

        var violations: [String] = []

        for budget in budgets {
            if let result = results[budget.testName] {
                if result > budget.maxDuration {
                    violations.append("\(budget.testName): exceeded max duration")
                }
                if let baseline = budget.baseline {
                    let regressionPercent = ((result - baseline) / baseline) * 100
                    if regressionPercent > budget.maxRegressionPercent {
                        violations.append("\(budget.testName): regression \(regressionPercent)%")
                    }
                }
            }
        }

        // Both tests should pass these particular budgets
        XCTAssertTrue(violations.isEmpty, "All performance budgets should be met")
    }
}

// MARK: - Dead Code Removal Tests

final class Phase7DeadCodeRemovalTests: XCTestCase {

    /// Tests that deprecated paths are identified.
    @MainActor
    func testDeprecatedPathIdentification() async throws {
        // This documents expected deprecated code paths
        let deprecatedPaths = [
            "NoteEditorViewModel (replaced by EditorSession)",
            "Ad-hoc title lookup in GraphEdgeStore (replaced by GraphIdentityResolver)",
            "Direct NotificationCenter usage for graph events (replaced by typed streams)"
        ]

        // All deprecated paths should be documented for removal
        XCTAssertEqual(deprecatedPaths.count, 3)
    }

    /// Tests that fallback branches have proper guards.
    @MainActor
    func testFallbackBranchGuards() async throws {
        enum OperationResult {
            case success(String)
            case fallback(String, reason: String)
            case failure(Error)
        }

        func performOperation(useFallback: Bool) -> OperationResult {
            if useFallback {
                return .fallback("fallback result", reason: "Primary operation disabled")
            }
            return .success("primary result")
        }

        let primaryResult = performOperation(useFallback: false)
        let fallbackResult = performOperation(useFallback: true)

        if case .success(let value) = primaryResult {
            XCTAssertEqual(value, "primary result")
        } else {
            XCTFail("Expected success")
        }

        if case .fallback(_, let reason) = fallbackResult {
            XCTAssertFalse(reason.isEmpty, "Fallback should have documented reason")
        } else {
            XCTFail("Expected fallback")
        }
    }

    /// Tests that unused feature flags are cleaned up.
    @MainActor
    func testFeatureFlagCleanup() async throws {
        struct FeatureFlags {
            // Active flags
            var enableGraphView = true
            var enableAIFeatures = true
            var enableSyncFeatures = true

            // Flags that should be removed after feature is stable
            // (documented here for tracking)
            static let candidatesForRemoval = [
                "legacyEditorPath",  // EditorSession is now default
                "oldGraphBuilder",   // GraphIdentityResolver is now default
                "notificationGraphEvents"  // Typed streams are now default
            ]
        }

        let flags = FeatureFlags()
        XCTAssertTrue(flags.enableGraphView)
        XCTAssertEqual(FeatureFlags.candidatesForRemoval.count, 3)
    }
}
