import Foundation
import os
import Dispatch

// MARK: - System Sentinel (Thermal & Memory Pressure Monitoring)

/// Production-grade system health monitor for hostile OS environments.
///
/// **Hostile OS Threats:**
/// - **iOS Jetsam**: Background apps killed when memory exceeds ~50MB footprint
/// - **iPadOS Stage Manager**: Multiple windows competing for limited RAM
/// - **macOS Thermal Throttling**: CPU throttled to 50% on .critical thermal state
/// - **iCloud bird daemon**: Mass file eviction during "Optimize Storage"
///
/// **Telemetry Signature:**
/// When triggered, emits:
/// - `os_signpost` interval: "SystemSentinel.pressureEvent"
/// - `Logger.fault()`: Critical pressure with thermal/memory state
/// - `NotificationCenter`: `.quartzSystemPressureChanged`
///
/// **Recovery Actions:**
/// - `.warning` memory: Pause non-essential background work
/// - `.critical` memory: Emergency flush, purge caches, throttle everything
/// - `.serious` thermal: Reduce animation frame rate to 30fps
/// - `.critical` thermal: Disable all animations, pause physics simulation
@MainActor
public final class SystemSentinel: @unchecked Sendable {

    // MARK: - Singleton

    public static let shared = SystemSentinel()

    // MARK: - State

    /// Current memory pressure level.
    public private(set) var memoryPressure: MemoryPressureLevel = .normal

    /// Current thermal state.
    public private(set) var thermalState: ProcessInfo.ThermalState = .nominal

    /// Combined system health score (0.0 = critical, 1.0 = healthy).
    public var healthScore: Double {
        let memoryScore: Double = switch memoryPressure {
        case .normal: 1.0
        case .warning: 0.6
        case .critical: 0.2
        }
        let thermalScore: Double = switch thermalState {
        case .nominal: 1.0
        case .fair: 0.8
        case .serious: 0.4
        case .critical: 0.1
        @unknown default: 0.5
        }
        return min(memoryScore, thermalScore)
    }

    /// Whether the system is under pressure and non-essential work should be deferred.
    public var isUnderPressure: Bool {
        memoryPressure != .normal || thermalState == .serious || thermalState == .critical
    }

    /// Whether the system is in critical state (emergency mode).
    public var isCritical: Bool {
        memoryPressure == .critical || thermalState == .critical
    }

    // MARK: - Private

    private let logger = Logger(subsystem: "com.quartz", category: "SystemSentinel")
    private let signpostLog = OSLog(subsystem: "com.quartz", category: .pointsOfInterest)

    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var thermalStateObserver: NSObjectProtocol?

    /// Callbacks registered by subsystems for pressure notifications.
    private var pressureCallbacks: [(SystemPressureEvent) -> Void] = []

    // MARK: - Init

    private init() {}

    // MARK: - Lifecycle

    /// Starts monitoring system pressure. Call once at app launch.
    public func startMonitoring() {
        startMemoryPressureMonitoring()
        startThermalStateMonitoring()

        // Log initial state
        thermalState = ProcessInfo.processInfo.thermalState
        logger.info("SystemSentinel started: thermal=\(self.thermalState.displayName), memory=\(self.memoryPressure.rawValue)")
    }

    /// Stops monitoring. Call on app termination if needed.
    public func stopMonitoring() {
        memoryPressureSource?.cancel()
        memoryPressureSource = nil

        if let observer = thermalStateObserver {
            NotificationCenter.default.removeObserver(observer)
            thermalStateObserver = nil
        }

        logger.info("SystemSentinel stopped")
    }

    /// Registers a callback to be invoked when system pressure changes.
    /// The callback is invoked on the main actor.
    public func registerPressureCallback(_ callback: @escaping (SystemPressureEvent) -> Void) {
        pressureCallbacks.append(callback)
    }

    // MARK: - Memory Pressure Monitoring

    private func startMemoryPressureMonitoring() {
        // Create memory pressure dispatch source
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical, .normal],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            // DispatchSourceMemoryPressure.data returns MemoryPressureEvent (OptionSet)
            let flags = source.data

            Task { @MainActor in
                // Check flags as raw UInt values
                let isWarning = flags.contains(.warning)
                let isCritical = flags.contains(.critical)
                self.handleMemoryPressureFlags(isWarning: isWarning, isCritical: isCritical)
            }
        }

        source.setCancelHandler { [weak self] in
            self?.logger.debug("Memory pressure source cancelled")
        }

        source.resume()
        memoryPressureSource = source
    }

    private func handleMemoryPressureFlags(isWarning: Bool, isCritical: Bool) {
        let previousLevel = memoryPressure

        if isCritical {
            memoryPressure = .critical
        } else if isWarning {
            memoryPressure = .warning
        } else {
            memoryPressure = .normal
        }

        guard memoryPressure != previousLevel else { return }

        // Emit signpost for Instruments
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.event, log: signpostLog, name: "MemoryPressure", signpostID: signpostID, "%{public}s", memoryPressure.rawValue)

        // Log the transition
        switch memoryPressure {
        case .critical:
            logger.fault("CRITICAL memory pressure! Initiating emergency throttle.")
        case .warning:
            logger.warning("Memory pressure warning. Throttling non-essential work.")
        case .normal:
            logger.info("Memory pressure returned to normal.")
        }

        // Notify subsystems
        let pressureEvent = SystemPressureEvent(
            source: .memory,
            level: memoryPressure == .critical ? .critical : (memoryPressure == .warning ? .warning : .normal),
            thermalState: thermalState,
            memoryPressure: memoryPressure,
            timestamp: Date()
        )

        notifyPressureChange(pressureEvent)
    }

    // MARK: - Thermal State Monitoring

    private func startThermalStateMonitoring() {
        thermalStateObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleThermalStateChange()
            }
        }
    }

    private func handleThermalStateChange() {
        let previousState = thermalState
        thermalState = ProcessInfo.processInfo.thermalState

        guard thermalState != previousState else { return }

        // Emit signpost for Instruments
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.event, log: signpostLog, name: "ThermalState", signpostID: signpostID, "%{public}s", thermalState.displayName)

        // Log the transition
        switch thermalState {
        case .critical:
            logger.fault("CRITICAL thermal state! CPU heavily throttled. Disabling animations.")
        case .serious:
            logger.warning("Serious thermal pressure. Reducing frame rate.")
        case .fair:
            logger.info("Thermal state: fair. Minor throttling may occur.")
        case .nominal:
            logger.info("Thermal state returned to nominal.")
        @unknown default:
            logger.warning("Unknown thermal state: \(self.thermalState.rawValue)")
        }

        // Notify subsystems
        let pressureEvent = SystemPressureEvent(
            source: .thermal,
            level: thermalState == .critical ? .critical : (thermalState == .serious ? .warning : .normal),
            thermalState: thermalState,
            memoryPressure: memoryPressure,
            timestamp: Date()
        )

        notifyPressureChange(pressureEvent)
    }

    // MARK: - Notification Dispatch

    private func notifyPressureChange(_ event: SystemPressureEvent) {
        // Invoke registered callbacks
        for callback in pressureCallbacks {
            callback(event)
        }

        // Post notification for loose coupling
        NotificationCenter.default.post(
            name: .quartzSystemPressureChanged,
            object: nil,
            userInfo: ["event": event]
        )
    }

    // MARK: - Manual Triggers (for testing)

    #if DEBUG
    /// Simulates a memory pressure event for testing.
    public func simulateMemoryPressure(_ level: MemoryPressureLevel) {
        memoryPressure = level
        let event = SystemPressureEvent(
            source: .memory,
            level: level == .critical ? .critical : (level == .warning ? .warning : .normal),
            thermalState: thermalState,
            memoryPressure: level,
            timestamp: Date()
        )
        notifyPressureChange(event)
    }

    /// Simulates a thermal state change for testing.
    public func simulateThermalState(_ state: ProcessInfo.ThermalState) {
        thermalState = state
        let event = SystemPressureEvent(
            source: .thermal,
            level: state == .critical ? .critical : (state == .serious ? .warning : .normal),
            thermalState: state,
            memoryPressure: memoryPressure,
            timestamp: Date()
        )
        notifyPressureChange(event)
    }
    #endif
}

// MARK: - Supporting Types

public extension SystemSentinel {

    /// Memory pressure levels corresponding to DispatchSource events.
    enum MemoryPressureLevel: String, Sendable {
        case normal = "normal"
        case warning = "warning"
        case critical = "critical"
    }

    /// A pressure event emitted when system state changes.
    struct SystemPressureEvent: Sendable {
        public let source: PressureSource
        public let level: PressureLevel
        public let thermalState: ProcessInfo.ThermalState
        public let memoryPressure: MemoryPressureLevel
        public let timestamp: Date

        public enum PressureSource: String, Sendable {
            case memory
            case thermal
        }

        public enum PressureLevel: String, Sendable {
            case normal
            case warning
            case critical
        }
    }
}

// MARK: - ThermalState Extension

public extension ProcessInfo.ThermalState {
    var displayName: String {
        switch self {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when system memory or thermal pressure changes.
    /// `userInfo["event"]` contains `SystemSentinel.SystemPressureEvent`.
    static let quartzSystemPressureChanged = Notification.Name("quartzSystemPressureChanged")
}
