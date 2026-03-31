import SwiftUI
import os

// MARK: - Graph Performance Circuit Breaker

/// Circuit breaker for Knowledge Graph rendering.
///
/// **The Objective:**
/// Prevents UI freezes when the Knowledge Graph encounters performance issues:
/// - Too many nodes causing frame drops
/// - Physics simulation consuming too much CPU
/// - Memory pressure from large graphs
///
/// **Cross-Platform Nuances:**
/// - **macOS**: Can handle larger graphs (up to 500 nodes) due to more RAM/CPU.
/// - **iPadOS**: Medium capacity (up to 300 nodes), Stage Manager can reduce available resources.
/// - **iOS**: Most constrained (up to 200 nodes), background app suspension can interrupt.
///
/// **Graceful Degradation Strategy:**
/// 1. **Green State** (Open): Full physics simulation, all features enabled.
/// 2. **Yellow State** (Half-Open): Reduced simulation tick rate, fewer iterations.
/// 3. **Red State** (Closed): Static render only, no physics, simplified edges.
///
/// **Recovery:**
/// After a cooldown period, the circuit breaker attempts to resume normal operation.
/// If performance issues recur, it trips again with an extended cooldown.
@Observable
@MainActor
public final class GraphCircuitBreaker {

    // MARK: - State

    /// Current circuit state.
    public private(set) var state: CircuitState = .closed

    /// Number of consecutive failures before tripping.
    private let failureThreshold: Int = 3

    /// Current failure count.
    private var failureCount: Int = 0

    /// Cooldown duration before attempting recovery.
    private var cooldownDuration: TimeInterval = 5.0

    /// Maximum cooldown (exponential backoff cap).
    private let maxCooldownDuration: TimeInterval = 60.0

    /// Last time the circuit tripped.
    private var lastTripTime: Date?

    /// Recovery task.
    private var recoveryTask: Task<Void, Never>?

    // MARK: - Performance Thresholds

    /// Frame time threshold in milliseconds (16.67ms = 60fps).
    private let frameTimeThresholdMs: Double = 16.67

    /// Maximum nodes before automatic degradation.
    public let maxNodesForFullSimulation: Int

    /// Maximum nodes before static-only mode.
    public let maxNodesForSimplifiedMode: Int

    // MARK: - Metrics

    /// Rolling average frame time.
    private var rollingFrameTimeMs: Double = 0

    /// Frame time samples for averaging.
    private var frameTimeSamples: [Double] = []
    private let maxSamples = 10

    private let logger = Logger(subsystem: "com.quartz", category: "GraphCircuitBreaker")

    // MARK: - Init

    public init() {
        // Platform-specific thresholds
        #if os(macOS)
        maxNodesForFullSimulation = 400
        maxNodesForSimplifiedMode = 600
        #elseif os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            maxNodesForFullSimulation = 280
            maxNodesForSimplifiedMode = 400
        } else {
            maxNodesForFullSimulation = 180
            maxNodesForSimplifiedMode = 280
        }
        #else
        maxNodesForFullSimulation = 280
        maxNodesForSimplifiedMode = 400
        #endif
    }

    // MARK: - Circuit State

    public enum CircuitState: String, Sendable {
        /// Full functionality — physics simulation enabled.
        case closed = "normal"

        /// Degraded — reduced simulation, monitoring for recovery.
        case halfOpen = "degraded"

        /// Open — static render only, waiting for cooldown.
        case open = "static"

        /// Display name for UI.
        public var displayName: String {
            switch self {
            case .closed: return "Full Quality"
            case .halfOpen: return "Reduced Quality"
            case .open: return "Static Mode"
            }
        }

        /// Icon for status display.
        public var iconName: String {
            switch self {
            case .closed: return "checkmark.circle.fill"
            case .halfOpen: return "exclamationmark.triangle.fill"
            case .open: return "xmark.octagon.fill"
            }
        }
    }

    // MARK: - Public API

    /// Reports a frame render time. Call this after each canvas draw.
    ///
    /// - Parameter frameTimeMs: The frame render time in milliseconds.
    public func reportFrameTime(_ frameTimeMs: Double) {
        // Update rolling average
        frameTimeSamples.append(frameTimeMs)
        if frameTimeSamples.count > maxSamples {
            frameTimeSamples.removeFirst()
        }
        rollingFrameTimeMs = frameTimeSamples.reduce(0, +) / Double(frameTimeSamples.count)

        // Check for performance issues
        if frameTimeMs > frameTimeThresholdMs * 2 {
            recordFailure()
        } else if state == .halfOpen && rollingFrameTimeMs < frameTimeThresholdMs {
            recordSuccess()
        }
    }

    /// Checks if physics simulation should run.
    ///
    /// - Parameter nodeCount: The number of nodes in the graph.
    /// - Returns: `true` if simulation should run.
    public func shouldRunSimulation(nodeCount: Int) -> Bool {
        switch state {
        case .closed:
            return nodeCount <= maxNodesForFullSimulation
        case .halfOpen:
            return nodeCount <= maxNodesForFullSimulation / 2
        case .open:
            return false
        }
    }

    /// Returns the recommended simulation tick rate.
    ///
    /// - Returns: Tick interval in seconds (0.016 = 60fps, 0.033 = 30fps).
    public var recommendedTickInterval: TimeInterval {
        switch state {
        case .closed: return 0.016  // 60fps
        case .halfOpen: return 0.033  // 30fps
        case .open: return 0  // No simulation
        }
    }

    /// Returns the recommended layout iteration count.
    ///
    /// - Parameter baseIterations: The base iteration count.
    /// - Returns: Adjusted iteration count based on circuit state.
    public func adjustedIterations(_ baseIterations: Int) -> Int {
        switch state {
        case .closed: return baseIterations
        case .halfOpen: return baseIterations / 2
        case .open: return 0
        }
    }

    /// Checks if edges should be simplified (no glow, dashed lines).
    public var shouldSimplifyEdges: Bool {
        state == .open
    }

    /// Checks if labels should be hidden for performance.
    public var shouldHideLabels: Bool {
        state == .open
    }

    /// Manually trips the circuit (e.g., on memory warning).
    public func trip() {
        transitionTo(.open)
    }

    /// Manually resets the circuit (e.g., after settings change).
    public func reset() {
        recoveryTask?.cancel()
        failureCount = 0
        cooldownDuration = 5.0
        state = .closed
        logger.info("Circuit breaker manually reset")
    }

    // MARK: - Internal Logic

    private func recordFailure() {
        failureCount += 1
        logger.warning("Frame drop detected (count: \(self.failureCount)/\(self.failureThreshold))")

        if failureCount >= failureThreshold {
            switch state {
            case .closed:
                transitionTo(.halfOpen)
            case .halfOpen:
                transitionTo(.open)
            case .open:
                // Already at maximum degradation
                break
            }
        }
    }

    private func recordSuccess() {
        if state == .halfOpen {
            failureCount = 0
            transitionTo(.closed)
        }
    }

    private func transitionTo(_ newState: CircuitState) {
        guard state != newState else { return }

        let oldState = state
        state = newState
        failureCount = 0
        lastTripTime = Date()

        logger.info("Circuit breaker: \(oldState.rawValue) → \(newState.rawValue)")

        // Post notification for UI updates
        NotificationCenter.default.post(
            name: .quartzGraphCircuitStateChanged,
            object: nil,
            userInfo: ["state": newState]
        )

        // Schedule recovery if we degraded
        if newState == .open {
            scheduleRecovery()
        }
    }

    private func scheduleRecovery() {
        recoveryTask?.cancel()
        recoveryTask = Task {
            try? await Task.sleep(for: .seconds(cooldownDuration))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                logger.info("Attempting circuit recovery after \(self.cooldownDuration)s cooldown")
                self.transitionTo(.halfOpen)

                // Exponential backoff for next trip
                self.cooldownDuration = min(self.cooldownDuration * 2, self.maxCooldownDuration)
            }
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when the graph circuit breaker state changes.
    static let quartzGraphCircuitStateChanged = Notification.Name("quartzGraphCircuitStateChanged")
}

// MARK: - SwiftUI Integration

/// Environment key for the graph circuit breaker.
private struct GraphCircuitBreakerKey: EnvironmentKey {
    static let defaultValue: GraphCircuitBreaker? = nil
}

public extension EnvironmentValues {
    var graphCircuitBreaker: GraphCircuitBreaker? {
        get { self[GraphCircuitBreakerKey.self] }
        set { self[GraphCircuitBreakerKey.self] = newValue }
    }
}

// MARK: - Status View

/// Compact status indicator for the circuit breaker state.
public struct GraphCircuitBreakerStatusView: View {
    let circuitBreaker: GraphCircuitBreaker

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(circuitBreaker: GraphCircuitBreaker) {
        self.circuitBreaker = circuitBreaker
    }

    public var body: some View {
        if circuitBreaker.state != .closed {
            HStack(spacing: 6) {
                Image(systemName: circuitBreaker.state.iconName)
                    .foregroundStyle(stateColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion && circuitBreaker.state == .halfOpen)

                Text(circuitBreaker.state.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(stateColor.opacity(0.1))
            )
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }

    private var stateColor: Color {
        switch circuitBreaker.state {
        case .closed: return .green
        case .halfOpen: return .orange
        case .open: return .red
        }
    }
}
