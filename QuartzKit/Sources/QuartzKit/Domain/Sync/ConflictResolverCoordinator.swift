import Foundation

// MARK: - ConflictResolverCoordinator (Per CODEX.md F6)

/// Coordinates conflict resolution through the state machine and event bus.
///
/// **Per CODEX.md F6:** ConflictStateMachine exists but was disconnected from conflict flows.
/// This coordinator ensures:
/// 1. All conflict resolution goes through state machine transitions
/// 2. Events are published to DomainEventBus for other subsystems
/// 3. No silent conflict resolution - every resolution is explicit
///
/// Usage:
/// ```swift
/// let coordinator = ConflictResolverCoordinator(stateMachine: machine, eventBus: bus)
/// try await coordinator.loadConflict(at: url)
/// try await coordinator.resolveKeepingLocal()
/// ```
@Observable
@MainActor
public final class ConflictResolverCoordinator {

    // MARK: - Dependencies

    /// The state machine enforcing valid transitions.
    public let stateMachine: ConflictStateMachine

    /// The event bus for publishing conflict events.
    private let eventBus: DomainEventBus

    /// The sync service for actual file operations.
    private let syncService: CloudSyncService

    // MARK: - State

    /// Whether a resolution operation is in progress.
    public private(set) var isOperating: Bool = false

    /// Error message from the last failed operation.
    public private(set) var lastError: String?

    // MARK: - Init

    public init(
        stateMachine: ConflictStateMachine = ConflictStateMachine(),
        eventBus: DomainEventBus = .shared,
        syncService: CloudSyncService = CloudSyncService()
    ) {
        self.stateMachine = stateMachine
        self.eventBus = eventBus
        self.syncService = syncService
    }

    // MARK: - Conflict Loading

    /// Detects and loads a conflict for the given URL.
    ///
    /// Transitions: clean → detected → diffLoaded
    /// Publishes: conflictDetected
    public func loadConflict(at url: URL) async throws {
        lastError = nil

        // Transition: clean → detected
        try stateMachine.detectConflict(at: url)

        // Publish detection event
        await eventBus.publish(.conflictDetected(url: url))

        // Build diff state
        do {
            if let diffState = try await syncService.buildConflictDiffState(for: url) {
                // Transition: detected → diffLoaded
                try stateMachine.loadDiff(diffState)
            } else {
                // No actual conflict found - reset
                stateMachine.reset()
            }
        } catch {
            // Loading failed - stay in detected state with error
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Returns the current diff state for display.
    public var diffState: ConflictDiffState? {
        stateMachine.diffState
    }

    /// Whether resolution can proceed.
    public var canResolve: Bool {
        stateMachine.canResolve
    }

    /// The URL of the current conflict.
    public var conflictURL: URL? {
        stateMachine.conflictURL
    }

    // MARK: - Resolution Operations

    /// Resolves by keeping the local version.
    ///
    /// Transitions: diffLoaded → resolving → resolved → clean
    /// Publishes: conflictResolved(.keptLocal)
    public func resolveKeepingLocal() async throws {
        guard let url = stateMachine.conflictURL else { return }
        try await performResolution(url: url, type: .keptLocal) {
            try self.syncService.resolveKeepingLocal(at: url)
        }
    }

    /// Resolves by keeping the cloud version.
    ///
    /// Transitions: diffLoaded → resolving → resolved → clean
    /// Publishes: conflictResolved(.keptCloud)
    public func resolveKeepingCloud() async throws {
        guard let url = stateMachine.conflictURL else { return }
        try await performResolution(url: url, type: .keptCloud) {
            try self.syncService.resolveKeepingCloud(at: url)
        }
    }

    /// Resolves by keeping both versions (branches conflict to sibling file).
    ///
    /// Transitions: diffLoaded → resolving → resolved → clean
    /// Publishes: conflictResolved(.keptBoth)
    public func resolveKeepingBoth() async throws {
        guard let url = stateMachine.conflictURL else { return }
        try await performResolution(url: url, type: .keptBoth) {
            try await self.syncService.resolveKeepingBoth(at: url)
        }
    }

    /// Resolves by writing merged content.
    ///
    /// Transitions: diffLoaded → resolving → resolved → clean
    /// Publishes: conflictResolved(.merged)
    public func resolveWithMerged(_ mergedContent: String) async throws {
        guard let url = stateMachine.conflictURL else { return }
        try await performResolution(url: url, type: .merged) {
            try await self.syncService.resolveWritingMerged(at: url, mergedUTF8: mergedContent)
        }
    }

    /// Cancels conflict resolution and returns to clean state.
    ///
    /// Cannot be called while resolving is in progress.
    public func cancel() throws {
        try stateMachine.cancel()
        lastError = nil
    }

    // MARK: - Private

    private func performResolution(
        url: URL,
        type: ConflictResolutionType,
        operation: @escaping () async throws -> Void
    ) async throws {
        guard stateMachine.canResolve else {
            throw ConflictCoordinatorError.cannotResolveInCurrentState(stateMachine.state)
        }

        isOperating = true
        lastError = nil

        do {
            // Transition: diffLoaded → resolving
            try stateMachine.beginResolving()

            // Perform the actual resolution
            try await operation()

            // Transition: resolving → resolved → clean
            try stateMachine.resolutionSucceeded()

            // Publish resolution event
            await eventBus.publish(.conflictResolved(url: url, resolution: type))

        } catch {
            // Transition: resolving → diffLoaded (retry allowed)
            try? stateMachine.resolutionFailed(error: error.localizedDescription)
            lastError = error.localizedDescription
            throw error
        }

        isOperating = false
    }
}

// MARK: - Errors

/// Errors from the conflict coordinator.
public enum ConflictCoordinatorError: LocalizedError {
    case cannotResolveInCurrentState(ConflictState)
    case noConflictLoaded

    public var errorDescription: String? {
        switch self {
        case .cannotResolveInCurrentState(let state):
            return "Cannot resolve conflict in state: \(state.rawValue)"
        case .noConflictLoaded:
            return "No conflict is currently loaded"
        }
    }
}
