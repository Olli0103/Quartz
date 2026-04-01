import Foundation

// MARK: - Conflict State Machine (Per CODEX.md F12)

/// Explicit state machine for sync conflict resolution.
///
/// **Per CODEX.md F12:** Conflict semantics were operation-driven, not state machine transitions.
/// This type enforces valid state transitions with compile-time and runtime checks.
///
/// States:
/// - `clean`: No conflict detected
/// - `detected`: Conflict discovered (versions differ)
/// - `diffLoaded`: Diff computed and ready for display
/// - `resolving`: User chose a resolution, applying it
/// - `resolved`: Resolution complete, transitioning back to clean
///
/// Transitions are validated - invalid transitions throw errors.
@Observable
@MainActor
public final class ConflictStateMachine {

    // MARK: - State

    /// The current conflict state.
    public private(set) var state: ConflictState = .clean

    /// The file URL with the conflict (nil when clean).
    public private(set) var conflictURL: URL?

    /// The diff state for display (nil until loaded).
    public private(set) var diffState: ConflictDiffState?

    /// Error message if resolution failed.
    public private(set) var errorMessage: String?

    /// Tracks state transition history for debugging.
    public private(set) var transitionHistory: [(from: ConflictState, to: ConflictState, timestamp: Date)] = []

    // MARK: - Init

    public init() {}

    // MARK: - State Transitions

    /// Detects a new conflict.
    /// Valid from: `clean`
    /// Transitions to: `detected`
    public func detectConflict(at url: URL) throws {
        try validateTransition(to: .detected)

        conflictURL = url
        errorMessage = nil
        transition(to: .detected)
    }

    /// Loads the diff for display.
    /// Valid from: `detected`
    /// Transitions to: `diffLoaded`
    public func loadDiff(_ diff: ConflictDiffState) throws {
        try validateTransition(to: .diffLoaded)

        diffState = diff
        transition(to: .diffLoaded)
    }

    /// User chose a resolution strategy, now applying.
    /// Valid from: `diffLoaded`
    /// Transitions to: `resolving`
    public func beginResolving() throws {
        try validateTransition(to: .resolving)

        transition(to: .resolving)
    }

    /// Resolution succeeded.
    /// Valid from: `resolving`
    /// Transitions to: `resolved` then immediately to `clean`
    public func resolutionSucceeded() throws {
        try validateTransition(to: .resolved)

        transition(to: .resolved)

        // Auto-transition to clean after successful resolution
        reset()
    }

    /// Resolution failed, can retry.
    /// Valid from: `resolving`
    /// Transitions to: `diffLoaded` (for retry)
    public func resolutionFailed(error: String) throws {
        guard state == .resolving else {
            throw ConflictStateMachineError.invalidTransition(from: state, to: .diffLoaded)
        }

        errorMessage = error
        transition(to: .diffLoaded)
    }

    /// Cancels conflict resolution and returns to clean state.
    /// Valid from: any state except `resolving`
    public func cancel() throws {
        guard state != .resolving else {
            throw ConflictStateMachineError.cannotCancelWhileResolving
        }

        reset()
    }

    /// Resets to clean state.
    public func reset() {
        let previousState = state
        conflictURL = nil
        diffState = nil
        errorMessage = nil
        state = .clean

        if previousState != .clean {
            transitionHistory.append((from: previousState, to: .clean, timestamp: Date()))
        }
    }

    // MARK: - Validation

    private func validateTransition(to newState: ConflictState) throws {
        let validTransitions = state.validNextStates
        guard validTransitions.contains(newState) else {
            throw ConflictStateMachineError.invalidTransition(from: state, to: newState)
        }
    }

    private func transition(to newState: ConflictState) {
        transitionHistory.append((from: state, to: newState, timestamp: Date()))
        state = newState
    }

    // MARK: - Convenience Queries

    /// Whether the state machine is in a conflict state (not clean).
    public var hasActiveConflict: Bool {
        state != .clean
    }

    /// Whether the user can choose a resolution strategy.
    public var canResolve: Bool {
        state == .diffLoaded
    }

    /// Whether resolution is in progress.
    public var isResolving: Bool {
        state == .resolving
    }
}

// MARK: - Conflict State Enum

/// States for the conflict resolution state machine.
public enum ConflictState: String, Sendable, CaseIterable {
    /// No conflict detected.
    case clean

    /// Conflict discovered (versions differ).
    case detected

    /// Diff computed and ready for display.
    case diffLoaded

    /// User chose resolution, applying it.
    case resolving

    /// Resolution complete.
    case resolved

    /// Valid next states from this state.
    var validNextStates: Set<ConflictState> {
        switch self {
        case .clean:
            return [.detected]
        case .detected:
            return [.diffLoaded, .clean]  // Can cancel from detected
        case .diffLoaded:
            return [.resolving, .clean]   // Can cancel or resolve
        case .resolving:
            return [.resolved, .diffLoaded]  // Success or retry
        case .resolved:
            return [.clean]  // Auto-transition
        }
    }
}

// MARK: - Errors

/// Errors that can occur during conflict state transitions.
public enum ConflictStateMachineError: LocalizedError {
    case invalidTransition(from: ConflictState, to: ConflictState)
    case cannotCancelWhileResolving

    public var errorDescription: String? {
        switch self {
        case .invalidTransition(let from, let to):
            return "Invalid conflict state transition: \(from.rawValue) → \(to.rawValue)"
        case .cannotCancelWhileResolving:
            return "Cannot cancel while resolution is in progress"
        }
    }
}
