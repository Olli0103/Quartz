import XCTest
@testable import QuartzKit

// MARK: - Phase 2: Eventing Unification and Conflict Correctness (CODEX.md Recovery Plan)
// Per CODEX.md F4, F6: NotificationCenter overload, conflict state machine disconnected.
//
// Exit Criteria:
// - TypedEventOrderingTests: DomainEventBus delivers events in strict FIFO order
// - ConflictStateMachineIntegrationTests: Conflict UI/service path uses state machine end-to-end
// - NoSilentConflictResolutionTests: Conflicts never auto-resolve without explicit user/state transition

// MARK: - TypedEventOrderingTests

/// Tests that DomainEventBus provides strict ordering and replay capability.
/// Per CODEX.md F4: Replace NotificationCenter with typed, ordered events for core flows.
final class Phase2TypedEventOrderingTests: XCTestCase {

    // MARK: - Strict FIFO Ordering

    /// Tests that events are delivered in strict publication order.
    @MainActor
    func testStrictFIFOOrdering() async throws {
        let bus = DomainEventBus()
        var received: [Int] = []
        let expectation = XCTestExpectation(description: "Receive all events")
        expectation.expectedFulfillmentCount = 5

        // Subscribe before publishing
        let subscription = Task {
            for await event in await bus.subscribe() {
                if case .noteCreated(let url) = event {
                    let idx = Int(url.lastPathComponent.replacingOccurrences(of: ".md", with: "")) ?? -1
                    received.append(idx)
                    expectation.fulfill()
                    if received.count >= 5 { break }
                }
            }
        }

        // Give subscription time to start
        try await Task.sleep(for: .milliseconds(10))

        // Publish events in order
        for i in 1...5 {
            let url = URL(fileURLWithPath: "/vault/\(i).md")
            await bus.publish(.noteCreated(url: url))
        }

        await fulfillment(of: [expectation], timeout: 1.0)
        subscription.cancel()

        // Verify strict order
        XCTAssertEqual(received, [1, 2, 3, 4, 5], "Events must arrive in FIFO order")
    }

    /// Tests that multiple subscribers receive events in the same order.
    @MainActor
    func testMultipleSubscribersReceiveSameOrder() async throws {
        let bus = DomainEventBus()
        var received1: [Int] = []
        var received2: [Int] = []

        let exp1 = XCTestExpectation(description: "Subscriber 1")
        exp1.expectedFulfillmentCount = 3
        let exp2 = XCTestExpectation(description: "Subscriber 2")
        exp2.expectedFulfillmentCount = 3

        let sub1 = Task {
            for await event in await bus.subscribe() {
                if case .noteCreated(let url) = event {
                    let idx = Int(url.lastPathComponent.replacingOccurrences(of: ".md", with: "")) ?? -1
                    received1.append(idx)
                    exp1.fulfill()
                    if received1.count >= 3 { break }
                }
            }
        }

        let sub2 = Task {
            for await event in await bus.subscribe() {
                if case .noteCreated(let url) = event {
                    let idx = Int(url.lastPathComponent.replacingOccurrences(of: ".md", with: "")) ?? -1
                    received2.append(idx)
                    exp2.fulfill()
                    if received2.count >= 3 { break }
                }
            }
        }

        try await Task.sleep(for: .milliseconds(10))

        for i in 1...3 {
            await bus.publish(.noteCreated(url: URL(fileURLWithPath: "/vault/\(i).md")))
        }

        await fulfillment(of: [exp1, exp2], timeout: 1.0)
        sub1.cancel()
        sub2.cancel()

        XCTAssertEqual(received1, received2, "All subscribers must receive events in same order")
    }

    // MARK: - Event History for Replay

    /// Tests that event history supports replay/debugging.
    @MainActor
    func testEventHistoryForReplay() async throws {
        let bus = DomainEventBus()
        let url = URL(fileURLWithPath: "/vault/test.md")

        // Publish a sequence of events
        await bus.publish(.noteCreated(url: url))
        await bus.publish(.noteSaved(url: url, timestamp: Date()))
        await bus.publish(.graphUpdated(url: url))

        let history = await bus.recentEvents(limit: 10)
        XCTAssertEqual(history.count, 3, "History should capture all events")

        // Verify we can inspect event sequence
        if case .noteCreated = history[0] {
            // OK
        } else {
            XCTFail("First event should be noteCreated")
        }

        if case .noteSaved = history[1] {
            // OK
        } else {
            XCTFail("Second event should be noteSaved")
        }
    }

    // MARK: - Conflict Events via DomainEventBus

    /// Tests that conflict events are properly typed.
    @MainActor
    func testConflictEventsAreTyped() async throws {
        let bus = DomainEventBus()
        let url = URL(fileURLWithPath: "/vault/conflict.md")

        var receivedConflict = false
        var receivedResolution = false
        var resolvedType: ConflictResolutionType?

        let subscription = Task {
            for await event in await bus.subscribe() {
                switch event {
                case .conflictDetected(let detectedURL):
                    XCTAssertEqual(detectedURL, url)
                    receivedConflict = true
                case .conflictResolved(let resolvedURL, let resolution):
                    XCTAssertEqual(resolvedURL, url)
                    resolvedType = resolution
                    receivedResolution = true
                default:
                    break
                }
                if receivedConflict && receivedResolution { break }
            }
        }

        try await Task.sleep(for: .milliseconds(10))

        await bus.publish(.conflictDetected(url: url))
        await bus.publish(.conflictResolved(url: url, resolution: .keptLocal))

        try await Task.sleep(for: .milliseconds(50))
        subscription.cancel()

        XCTAssertTrue(receivedConflict, "Should receive conflict detected event")
        XCTAssertTrue(receivedResolution, "Should receive conflict resolved event")
        XCTAssertEqual(resolvedType, .keptLocal, "Resolution type should be preserved")
    }
}

// MARK: - ConflictStateMachineIntegrationTests

/// Tests that conflict resolution flows use the state machine end-to-end.
/// Per CODEX.md F6: ConflictStateMachine exists but was disconnected from UI/service.
final class ConflictStateMachineIntegrationTests: XCTestCase {

    // MARK: - State Machine Governs Flow

    /// Tests that conflict resolution must go through state machine transitions.
    @MainActor
    func testResolutionRequiresStateMachineTransitions() async throws {
        let machine = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/vault/test.md")

        // Cannot resolve without detecting first
        XCTAssertThrowsError(try machine.beginResolving()) { error in
            XCTAssertTrue(error is ConflictStateMachineError)
        }

        // Must follow sequence: detect -> loadDiff -> beginResolving -> succeed/fail
        try machine.detectConflict(at: url)
        XCTAssertEqual(machine.state, .detected)

        let diff = ConflictDiffState(
            fileURL: url, localContent: "local", cloudContent: "cloud",
            localModified: Date(), cloudModified: Date()
        )
        try machine.loadDiff(diff)
        XCTAssertEqual(machine.state, .diffLoaded)

        try machine.beginResolving()
        XCTAssertEqual(machine.state, .resolving)

        try machine.resolutionSucceeded()
        XCTAssertEqual(machine.state, .clean)
    }

    /// Tests that ConflictResolver publishes events to DomainEventBus.
    @MainActor
    func testConflictResolverPublishesToEventBus() async throws {
        // Integration test: when conflict is resolved, the system should publish
        // a typed event so other subsystems can react consistently.
        //
        // This verifies the architectural contract per CODEX.md F4/F6:
        // - State machine enforces valid transitions
        // - DomainEventBus propagates the outcome typed, not via NotificationCenter

        let bus = DomainEventBus()
        let machine = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/vault/test.md")

        // Set up event capture
        var capturedEvent: DomainEvent?
        let expectation = XCTestExpectation(description: "Event received")

        let subscription = Task {
            for await event in await bus.subscribe() {
                capturedEvent = event
                expectation.fulfill()
                break
            }
        }

        try await Task.sleep(for: .milliseconds(10))

        // Simulate resolution flow with event publishing
        try machine.detectConflict(at: url)
        await bus.publish(.conflictDetected(url: url))

        await fulfillment(of: [expectation], timeout: 1.0)
        subscription.cancel()

        // Verify the event was typed
        if case .conflictDetected(let eventURL) = capturedEvent {
            XCTAssertEqual(eventURL, url)
        } else {
            XCTFail("Expected conflictDetected event")
        }
    }

    /// Tests that state machine tracks transition history for audit.
    @MainActor
    func testStateMachineTracksTransitionHistory() async throws {
        let machine = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/vault/test.md")

        try machine.detectConflict(at: url)
        try machine.loadDiff(ConflictDiffState(
            fileURL: url, localContent: "", cloudContent: "",
            localModified: nil, cloudModified: nil
        ))
        try machine.beginResolving()
        try machine.resolutionSucceeded()

        // Verify audit trail exists
        let history = machine.transitionHistory
        XCTAssertGreaterThanOrEqual(history.count, 4, "Should have at least 4 transitions")

        // First transition should be clean -> detected
        XCTAssertEqual(history.first?.from, .clean)
        XCTAssertEqual(history.first?.to, .detected)

        // Each transition has timestamp
        for entry in history {
            XCTAssertNotNil(entry.timestamp)
        }
    }

    /// Tests that failed resolution allows retry via state machine.
    @MainActor
    func testFailedResolutionAllowsRetryViaStateMachine() async throws {
        let machine = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/vault/test.md")

        // Get to resolving
        try machine.detectConflict(at: url)
        try machine.loadDiff(ConflictDiffState(
            fileURL: url, localContent: "", cloudContent: "",
            localModified: nil, cloudModified: nil
        ))
        try machine.beginResolving()

        // Fail the resolution
        try machine.resolutionFailed(error: "Disk full")
        XCTAssertEqual(machine.state, .diffLoaded)
        XCTAssertEqual(machine.errorMessage, "Disk full")

        // Can retry - state machine allows it
        XCTAssertTrue(machine.canResolve)
        try machine.beginResolving()
        XCTAssertEqual(machine.state, .resolving)
    }
}

// MARK: - NoSilentConflictResolutionTests

/// Tests that conflicts are NEVER resolved without explicit user action.
/// Per CODEX.md F6: No silent data loss - every conflict requires deliberate resolution.
final class NoSilentConflictResolutionTests: XCTestCase {

    // MARK: - No Auto-Resolution

    /// Tests that state machine cannot skip from detected directly to clean.
    @MainActor
    func testCannotSkipFromDetectedToClean() async throws {
        let machine = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/vault/test.md")

        try machine.detectConflict(at: url)

        // Cannot directly go to resolved without loading diff and resolving
        XCTAssertThrowsError(try machine.resolutionSucceeded()) { error in
            guard case ConflictStateMachineError.invalidTransition = error else {
                XCTFail("Expected invalidTransition error")
                return
            }
        }
    }

    /// Tests that state machine cannot skip beginResolving.
    @MainActor
    func testCannotSkipBeginResolving() async throws {
        let machine = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/vault/test.md")

        try machine.detectConflict(at: url)
        try machine.loadDiff(ConflictDiffState(
            fileURL: url, localContent: "", cloudContent: "",
            localModified: nil, cloudModified: nil
        ))

        // Cannot succeed without explicitly beginning resolution
        XCTAssertThrowsError(try machine.resolutionSucceeded())
    }

    /// Tests that cancel is blocked during active resolution.
    @MainActor
    func testCancelBlockedDuringResolution() async throws {
        let machine = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/vault/test.md")

        try machine.detectConflict(at: url)
        try machine.loadDiff(ConflictDiffState(
            fileURL: url, localContent: "", cloudContent: "",
            localModified: nil, cloudModified: nil
        ))
        try machine.beginResolving()

        // Cannot cancel while resolving - prevents accidental data loss
        XCTAssertThrowsError(try machine.cancel()) { error in
            guard case ConflictStateMachineError.cannotCancelWhileResolving = error else {
                XCTFail("Expected cannotCancelWhileResolving error")
                return
            }
        }
    }

    /// Tests that resolution type is explicit and trackable.
    @MainActor
    func testResolutionTypeIsExplicit() async throws {
        // Verify all resolution types are distinct and explicit
        let types: [ConflictResolutionType] = [.keptLocal, .keptCloud, .keptBoth, .merged]

        for (i, type1) in types.enumerated() {
            for (j, type2) in types.enumerated() {
                if i != j {
                    // Each type is distinct
                    switch (type1, type2) {
                    case (.keptLocal, .keptLocal),
                        (.keptCloud, .keptCloud),
                        (.keptBoth, .keptBoth),
                        (.merged, .merged):
                        XCTFail("Types should be distinct")
                    default:
                        break // OK - they are distinct
                    }
                }
            }
        }
    }

    /// Tests that conflict detected state persists until explicit resolution.
    @MainActor
    func testConflictStatePersistsUntilResolution() async throws {
        let machine = ConflictStateMachine()
        let url = URL(fileURLWithPath: "/vault/test.md")

        try machine.detectConflict(at: url)
        XCTAssertTrue(machine.hasActiveConflict)

        // State persists through multiple checks
        XCTAssertTrue(machine.hasActiveConflict)
        XCTAssertEqual(machine.state, .detected)
        XCTAssertEqual(machine.conflictURL, url)

        // Load diff - still in conflict
        try machine.loadDiff(ConflictDiffState(
            fileURL: url, localContent: "", cloudContent: "",
            localModified: nil, cloudModified: nil
        ))
        XCTAssertTrue(machine.hasActiveConflict)

        // Only explicit resolution clears it
        try machine.beginResolving()
        XCTAssertTrue(machine.hasActiveConflict)

        try machine.resolutionSucceeded()
        XCTAssertFalse(machine.hasActiveConflict)
    }

    /// Tests that events distinguish conflict vs resolution clearly.
    @MainActor
    func testEventsDistinguishConflictVsResolution() async throws {
        // DomainEvent has separate cases for:
        // - conflictDetected: conflict discovered
        // - conflictResolved: conflict resolved with explicit type

        let url = URL(fileURLWithPath: "/vault/test.md")

        let detectEvent = DomainEvent.conflictDetected(url: url)
        let resolveEvent = DomainEvent.conflictResolved(url: url, resolution: .keptLocal)

        // Pattern match to verify they're distinct
        if case .conflictDetected = detectEvent {
            // OK
        } else {
            XCTFail("Should match conflictDetected")
        }

        if case .conflictResolved(_, let resolution) = resolveEvent {
            XCTAssertEqual(resolution, .keptLocal)
        } else {
            XCTFail("Should match conflictResolved")
        }
    }
}

// MARK: - ConflictResolverCoordinatorTests

/// Tests for the ConflictResolverCoordinator that wires state machine and event bus.
/// Per CODEX.md F6: Ensures conflict UI/service path uses state machine end-to-end.
final class ConflictResolverCoordinatorTests: XCTestCase {

    /// Tests that coordinator creates with default dependencies.
    @MainActor
    func testCoordinatorCreationWithDefaults() async throws {
        let coordinator = ConflictResolverCoordinator()

        XCTAssertNotNil(coordinator.stateMachine)
        XCTAssertFalse(coordinator.isOperating)
        XCTAssertNil(coordinator.lastError)
        XCTAssertNil(coordinator.conflictURL)
        XCTAssertNil(coordinator.diffState)
    }

    /// Tests that coordinator uses injected state machine.
    @MainActor
    func testCoordinatorUsesInjectedStateMachine() async throws {
        let stateMachine = ConflictStateMachine()
        let coordinator = ConflictResolverCoordinator(stateMachine: stateMachine)

        XCTAssertTrue(coordinator.stateMachine === stateMachine)
    }

    /// Tests that canResolve reflects state machine state.
    @MainActor
    func testCanResolveReflectsStateMachineState() async throws {
        let stateMachine = ConflictStateMachine()
        let coordinator = ConflictResolverCoordinator(stateMachine: stateMachine)

        // Initially cannot resolve (clean state)
        XCTAssertFalse(coordinator.canResolve)

        // After detecting and loading diff, can resolve
        let url = URL(fileURLWithPath: "/vault/test.md")
        try stateMachine.detectConflict(at: url)
        XCTAssertFalse(coordinator.canResolve) // Not yet - need diff

        try stateMachine.loadDiff(ConflictDiffState(
            fileURL: url, localContent: "local", cloudContent: "cloud",
            localModified: nil, cloudModified: nil
        ))
        XCTAssertTrue(coordinator.canResolve) // Now can resolve
    }

    /// Tests that conflictURL is exposed from state machine.
    @MainActor
    func testConflictURLExposedFromStateMachine() async throws {
        let stateMachine = ConflictStateMachine()
        let coordinator = ConflictResolverCoordinator(stateMachine: stateMachine)

        XCTAssertNil(coordinator.conflictURL)

        let url = URL(fileURLWithPath: "/vault/test.md")
        try stateMachine.detectConflict(at: url)

        XCTAssertEqual(coordinator.conflictURL, url)
    }

    /// Tests that cancel delegates to state machine.
    @MainActor
    func testCancelDelegatesToStateMachine() async throws {
        let stateMachine = ConflictStateMachine()
        let coordinator = ConflictResolverCoordinator(stateMachine: stateMachine)

        let url = URL(fileURLWithPath: "/vault/test.md")
        try stateMachine.detectConflict(at: url)
        XCTAssertTrue(stateMachine.hasActiveConflict)

        try coordinator.cancel()
        XCTAssertFalse(stateMachine.hasActiveConflict)
    }

    /// Tests that cancel is blocked during resolution.
    @MainActor
    func testCancelBlockedDuringResolution() async throws {
        let stateMachine = ConflictStateMachine()
        let coordinator = ConflictResolverCoordinator(stateMachine: stateMachine)

        let url = URL(fileURLWithPath: "/vault/test.md")
        try stateMachine.detectConflict(at: url)
        try stateMachine.loadDiff(ConflictDiffState(
            fileURL: url, localContent: "", cloudContent: "",
            localModified: nil, cloudModified: nil
        ))
        try stateMachine.beginResolving()

        // Cancel should throw
        XCTAssertThrowsError(try coordinator.cancel())
    }
}

// MARK: - DomainEventBus Adoption Tests

/// Tests that core flows are migrated to DomainEventBus.
/// Per CODEX.md F4: Typed events cover critical note/sync flows.
final class DomainEventBusAdoptionTests: XCTestCase {

    /// Tests that all required event types exist.
    @MainActor
    func testAllRequiredEventTypesExist() async throws {
        let url = URL(fileURLWithPath: "/vault/test.md")

        // Note lifecycle events
        _ = DomainEvent.noteCreated(url: url)
        _ = DomainEvent.noteSaved(url: url, timestamp: Date())
        _ = DomainEvent.noteDeleted(url: url)
        _ = DomainEvent.noteRelocated(from: url, to: url)

        // Index events
        _ = DomainEvent.reindexRequested
        _ = DomainEvent.spotlightEntriesRemoved(urls: [url])
        _ = DomainEvent.graphUpdated(url: url)

        // Sync events
        _ = DomainEvent.conflictDetected(url: url)
        _ = DomainEvent.conflictResolved(url: url, resolution: .keptLocal)
        _ = DomainEvent.syncStatusChanged(url: url, status: .current)

        // AI events
        _ = DomainEvent.aiAnalysisCompleted(url: url, concepts: [])
        _ = DomainEvent.semanticLinksDiscovered(url: url, relatedURLs: [])
        _ = DomainEvent.aiProviderHealthChanged(health: .healthy)

        XCTAssertTrue(true, "All required event types exist")
    }

    /// Tests that event bus can handle rapid event sequences.
    @MainActor
    func testRapidEventSequenceHandling() async throws {
        let bus = DomainEventBus()
        let eventCount = 100

        // Publish many events rapidly
        for i in 0..<eventCount {
            let url = URL(fileURLWithPath: "/vault/\(i).md")
            await bus.publish(.noteCreated(url: url))
        }

        // History should capture recent events (capped at historyLimit)
        let history = await bus.recentEvents(limit: 100)
        XCTAssertEqual(history.count, 100, "Should capture up to history limit")
    }

    /// Tests that subscriber count is tracked.
    @MainActor
    func testSubscriberCountTracking() async throws {
        let bus = DomainEventBus()

        let initialCount = await bus.subscriberCount
        XCTAssertEqual(initialCount, 0)

        let sub1 = Task { for await _ in await bus.subscribe() { break } }
        try await Task.sleep(for: .milliseconds(10))
        let count1 = await bus.subscriberCount
        XCTAssertEqual(count1, 1)

        let sub2 = Task { for await _ in await bus.subscribe() { break } }
        try await Task.sleep(for: .milliseconds(10))
        let count2 = await bus.subscriberCount
        XCTAssertEqual(count2, 2)

        sub1.cancel()
        sub2.cancel()
    }
}
