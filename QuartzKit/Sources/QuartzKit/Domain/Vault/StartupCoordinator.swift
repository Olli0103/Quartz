import Foundation
import os

/// Coordinates app startup through a deterministic phase progression.
///
/// Replaces timing heuristics with an explicit handshake:
/// `initial → vaultResolved → editorMounted → indexWarm → restorationApplied`
///
/// Each phase must be reached in order. Callers can `await` a target phase,
/// and the coordinator resumes all waiters when the phase is reached.
@MainActor
@Observable
public final class StartupCoordinator {

    // MARK: - Phase Definition

    /// The ordered startup phases.
    public enum StartupPhase: Int, Comparable, Sendable, CaseIterable {
        /// App launched, no vault loaded yet.
        case initial = 0
        /// Security-scoped bookmark restored, vault directory accessible.
        case vaultResolved = 1
        /// EditorSession created and wired into the workspace lifecycle.
        case editorMounted = 2
        /// Search index + graph edges loaded (from cache or rebuilt).
        case indexWarm = 3
        /// Route, scroll position, and cursor restoration have been explicitly applied or skipped.
        case restorationApplied = 4

        public static func < (lhs: StartupPhase, rhs: StartupPhase) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - State

    /// The current startup phase.
    public private(set) var currentPhase: StartupPhase = .initial

    /// Whether startup is fully complete.
    public var isFullyStarted: Bool { currentPhase == .restorationApplied }

    private var phaseContinuations: [StartupPhase: [CheckedContinuation<Void, Never>]] = [:]
    private let logger = Logger(subsystem: "com.quartz", category: "StartupCoordinator")

    // MARK: - Init

    public init() {}

    // MARK: - Phase Progression

    /// Advances to the specified phase.
    ///
    /// - Parameter phase: The phase to advance to. Must be exactly one step
    ///   ahead of the current phase (no skipping).
    /// - Returns: `true` if the advance succeeded, `false` if the phase
    ///   was invalid (not sequential).
    @discardableResult
    public func advance(to phase: StartupPhase) -> Bool {
        guard phase.rawValue == currentPhase.rawValue + 1 else {
            logger.warning("Cannot advance from \(String(describing: self.currentPhase)) to \(String(describing: phase)) — must be sequential")
            return false
        }

        currentPhase = phase
        logger.info("Startup phase: \(String(describing: phase))")

        // Resume all continuations waiting for this phase or earlier
        for (waitingPhase, continuations) in phaseContinuations where waitingPhase <= phase {
            for continuation in continuations {
                continuation.resume()
            }
        }
        phaseContinuations = phaseContinuations.filter { $0.key > phase }

        return true
    }

    /// Suspends until the specified phase is reached.
    ///
    /// Returns immediately if the coordinator is already at or past the target phase.
    public func awaitPhase(_ phase: StartupPhase) async {
        if currentPhase >= phase { return }

        await withCheckedContinuation { continuation in
            phaseContinuations[phase, default: []].append(continuation)
        }
    }

    /// Resets the coordinator to `.initial` (for vault switching).
    ///
    /// Resumes any pending continuations to unblock waiters.
    public func reset() {
        for (_, continuations) in phaseContinuations {
            for continuation in continuations {
                continuation.resume()
            }
        }
        phaseContinuations.removeAll()
        currentPhase = .initial
        logger.info("Startup coordinator reset")
    }
}
