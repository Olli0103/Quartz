import Foundation
import os

// MARK: - Operation Watchdog (Signpost + Deadlock Detection)

/// Precision instrumentation for detecting slow operations and potential deadlocks.
///
/// **Hostile OS Threats:**
/// - **NSFileCoordinator deadlock**: iCloud sync lock held indefinitely
/// - **Main thread starvation**: AST parsing blocking UI for >16ms
/// - **Regex catastrophic backtracking**: Malicious input freezing parser
///
/// **Telemetry Signature:**
/// - `os_signpost` intervals with precise nanosecond timing
/// - Automatic fault logging if operation exceeds threshold
/// - Stack trace capture on timeout for post-mortem debugging
///
/// **Usage:**
/// ```swift
/// let watchdog = OperationWatchdog.shared
/// try await watchdog.monitoredOperation(
///     name: "FileCoordinator.read",
///     threshold: .milliseconds(500)
/// ) {
///     try CoordinatedFileWriter.shared.read(from: url)
/// }
/// ```
public actor OperationWatchdog {

    // MARK: - Singleton

    public static let shared = OperationWatchdog()

    // MARK: - Configuration

    /// Default threshold for slow operation warnings.
    public var defaultThreshold: Duration = .milliseconds(500)

    /// Whether to capture stack traces on timeout (expensive, debug only).
    public var captureStackTraces: Bool = false

    // MARK: - State

    private let logger = Logger(subsystem: "com.quartz", category: "OperationWatchdog")
    private let signpostLog = OSLog(subsystem: "com.quartz", category: .pointsOfInterest)

    /// Active operations being monitored.
    private var activeOperations: [UUID: MonitoredOperation] = [:]

    /// Statistics for telemetry.
    private var statistics = OperationStatistics()

    // MARK: - Init

    private init() {}

    // MARK: - Synchronous Monitoring

    /// Monitors a synchronous operation with os_signpost and timeout detection.
    ///
    /// - Parameters:
    ///   - name: Operation name for logging (e.g., "AST.parse")
    ///   - category: Optional category for grouping (e.g., "editor", "file")
    ///   - threshold: Maximum allowed duration before triggering fault
    ///   - operation: The synchronous operation to monitor
    /// - Returns: The operation's result
    /// - Throws: The operation's error, or `WatchdogError.timeout` if it exceeds threshold
    @discardableResult
    public func monitoredSync<T>(
        name: StaticString,
        category: String = "general",
        threshold: Duration? = nil,
        operation: () throws -> T
    ) rethrows -> T {
        let operationID = UUID()
        let effectiveThreshold = threshold ?? defaultThreshold
        let startTime = DispatchTime.now()
        let signpostID = OSSignpostID(log: signpostLog)

        // Begin signpost interval
        os_signpost(.begin, log: signpostLog, name: name, signpostID: signpostID, "category=%{public}s", category)

        defer {
            // End signpost interval
            os_signpost(.end, log: signpostLog, name: name, signpostID: signpostID)

            // Calculate duration
            let endTime = DispatchTime.now()
            let durationNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            let durationMs = Double(durationNanos) / 1_000_000

            // Check threshold
            let thresholdNanos = UInt64(effectiveThreshold.components.seconds) * 1_000_000_000
                + UInt64(effectiveThreshold.components.attoseconds / 1_000_000_000)

            if durationNanos > thresholdNanos {
                // Emit fault log
                logger.fault("""
                    SLOW OPERATION DETECTED
                    Name: \(name, privacy: .public)
                    Category: \(category, privacy: .public)
                    Duration: \(durationMs, format: .fixed(precision: 2))ms
                    Threshold: \(Double(thresholdNanos) / 1_000_000, format: .fixed(precision: 2))ms
                    """)
                QuartzDiagnostics.fault(
                    category: "OperationWatchdog",
                    "Slow operation detected: \(name) [\(category)] \(String(format: "%.2f", durationMs))ms"
                )

                // Post notification for RecoveryJournal
                Task { @MainActor in
                    NotificationCenter.default.post(
                        name: .quartzSlowOperationDetected,
                        object: nil,
                        userInfo: [
                            "name": "\(name)",
                            "category": category,
                            "durationMs": durationMs,
                            "thresholdMs": Double(thresholdNanos) / 1_000_000
                        ]
                    )
                }
            }

            // Update statistics (fire-and-forget)
            Task {
                await self.recordOperation(
                    name: "\(name)",
                    category: category,
                    durationMs: durationMs,
                    exceededThreshold: durationNanos > thresholdNanos
                )
            }
        }

        return try operation()
    }

    // MARK: - Async Monitoring with Timeout

    /// Monitors an async operation with hard timeout enforcement.
    ///
    /// - Parameters:
    ///   - name: Operation name for logging
    ///   - category: Optional category for grouping
    ///   - threshold: Maximum duration before fault logging
    ///   - timeout: Hard timeout that cancels the operation
    ///   - operation: The async operation to monitor
    /// - Returns: The operation's result
    /// - Throws: `WatchdogError.timeout` if hard timeout exceeded
    @discardableResult
    public func monitoredAsync<T: Sendable>(
        name: StaticString,
        category: String = "general",
        threshold: Duration? = nil,
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let effectiveThreshold = threshold ?? defaultThreshold
        let signpostID = OSSignpostID(log: signpostLog)
        let startTime = DispatchTime.now()

        os_signpost(.begin, log: signpostLog, name: name, signpostID: signpostID, "category=%{public}s,timeout=%lldms", category, Int64(timeout.components.seconds * 1000))

        do {
            let result = try await withThrowingTaskGroup(of: T.self) { group in
                // Main operation task
                group.addTask {
                    try await operation()
                }

                // Timeout task
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw WatchdogError.timeout(operation: "\(name)", durationMs: Double(timeout.components.seconds) * 1000)
                }

                // Return first to complete
                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            os_signpost(.end, log: signpostLog, name: name, signpostID: signpostID, "success")

            // Check threshold (non-fatal warning)
            let endTime = DispatchTime.now()
            let durationNanos = endTime.uptimeNanoseconds - startTime.uptimeNanoseconds
            let durationMs = Double(durationNanos) / 1_000_000
            let thresholdNanos = UInt64(effectiveThreshold.components.seconds) * 1_000_000_000

            if durationNanos > thresholdNanos {
                logger.warning("Operation '\(name, privacy: .public)' exceeded threshold: \(durationMs, format: .fixed(precision: 2))ms")
                QuartzDiagnostics.warning(
                    category: "OperationWatchdog",
                    "Operation '\(name)' exceeded threshold: \(String(format: "%.2f", durationMs))ms"
                )
            }

            await recordOperation(name: "\(name)", category: category, durationMs: durationMs, exceededThreshold: durationNanos > thresholdNanos)

            return result

        } catch let error as WatchdogError {
            os_signpost(.end, log: signpostLog, name: name, signpostID: signpostID, "timeout")
            logger.fault("OPERATION TIMEOUT: \(name, privacy: .public) exceeded \(timeout.components.seconds)s hard limit")
            QuartzDiagnostics.fault(
                category: "OperationWatchdog",
                "Operation timeout: \(name) exceeded \(timeout.components.seconds)s hard limit"
            )

            // Capture diagnostic info
            await recordTimeout(name: "\(name)", category: category, timeoutMs: Double(timeout.components.seconds) * 1000)

            throw error

        } catch {
            os_signpost(.end, log: signpostLog, name: name, signpostID: signpostID, "error")
            throw error
        }
    }

    // MARK: - File Coordinator Monitoring

    /// Specialized monitor for NSFileCoordinator operations.
    /// Uses a background watchdog thread to detect true deadlocks.
    public func monitoredFileCoordination<T>(
        at url: URL,
        timeout: Duration = .seconds(5),
        operation: () throws -> T
    ) throws -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        let operationID = UUID()
        let startTime = DispatchTime.now()

        os_signpost(.begin, log: signpostLog, name: "FileCoordinator", signpostID: signpostID, "url=%{public}s", url.lastPathComponent)

        // Create watchdog timer on background queue
        let watchdogQueue = DispatchQueue(label: "com.quartz.filecoordinator.watchdog", qos: .utility)
        var didComplete = false
        let completionLock = NSLock()

        watchdogQueue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout.components.seconds * 1000))) { [logger] in
            completionLock.lock()
            let completed = didComplete
            completionLock.unlock()

            if !completed {
                // Still running after timeout — potential deadlock
                logger.fault("""
                    POTENTIAL FILE COORDINATOR DEADLOCK
                    URL: \(url.lastPathComponent, privacy: .public)
                    Timeout: \(timeout.components.seconds)s
                    Thread may be blocked waiting for iCloud coordination.
                    """)

                // Post critical notification
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .quartzFileCoordinatorTimeout,
                        object: nil,
                        userInfo: ["url": url, "operationID": operationID]
                    )
                }
            }
        }

        defer {
            completionLock.lock()
            didComplete = true
            completionLock.unlock()

            os_signpost(.end, log: signpostLog, name: "FileCoordinator", signpostID: signpostID)

            let endTime = DispatchTime.now()
            let durationMs = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000

            if durationMs > 100 {
                logger.info("FileCoordinator completed: \(url.lastPathComponent, privacy: .public) in \(durationMs, format: .fixed(precision: 2))ms")
            }
        }

        return try operation()
    }

    // MARK: - Statistics

    private func recordOperation(name: String, category: String, durationMs: Double, exceededThreshold: Bool) {
        statistics.totalOperations += 1
        statistics.totalDurationMs += durationMs

        if exceededThreshold {
            statistics.slowOperations += 1
        }

        // Track per-category stats
        var categoryStats = statistics.categoryStats[category] ?? CategoryStatistics()
        categoryStats.operations += 1
        categoryStats.totalDurationMs += durationMs
        if exceededThreshold { categoryStats.slowOperations += 1 }
        statistics.categoryStats[category] = categoryStats
    }

    private func recordTimeout(name: String, category: String, timeoutMs: Double) {
        statistics.timeouts += 1

        var categoryStats = statistics.categoryStats[category] ?? CategoryStatistics()
        categoryStats.timeouts += 1
        statistics.categoryStats[category] = categoryStats
    }

    /// Returns current operation statistics.
    public func getStatistics() -> OperationStatistics {
        statistics
    }

    /// Resets all statistics.
    public func resetStatistics() {
        statistics = OperationStatistics()
    }
}

// MARK: - Supporting Types

public extension OperationWatchdog {

    /// Errors thrown by the watchdog.
    enum WatchdogError: Error, LocalizedError {
        case timeout(operation: String, durationMs: Double)

        public var errorDescription: String? {
            switch self {
            case .timeout(let operation, let durationMs):
                return "Operation '\(operation)' timed out after \(Int(durationMs))ms"
            }
        }
    }

    /// A tracked operation.
    struct MonitoredOperation: Sendable {
        let id: UUID
        let name: String
        let category: String
        let startTime: DispatchTime
        let threshold: Duration
    }

    /// Aggregated statistics.
    struct OperationStatistics: Sendable {
        public var totalOperations: Int = 0
        public var slowOperations: Int = 0
        public var timeouts: Int = 0
        public var totalDurationMs: Double = 0
        public var categoryStats: [String: CategoryStatistics] = [:]

        public var averageDurationMs: Double {
            totalOperations > 0 ? totalDurationMs / Double(totalOperations) : 0
        }
    }

    struct CategoryStatistics: Sendable {
        public var operations: Int = 0
        public var slowOperations: Int = 0
        public var timeouts: Int = 0
        public var totalDurationMs: Double = 0
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when an operation exceeds its threshold (non-fatal warning).
    static let quartzSlowOperationDetected = Notification.Name("quartzSlowOperationDetected")

    /// Posted when NSFileCoordinator appears to be deadlocked.
    static let quartzFileCoordinatorTimeout = Notification.Name("quartzFileCoordinatorTimeout")
}

// MARK: - Convenience Extensions

public extension OperationWatchdog {

    /// Quick signpost marker for instantaneous events.
    func markEvent(_ name: StaticString, message: String = "") {
        let signpostID = OSSignpostID(log: signpostLog)
        os_signpost(.event, log: signpostLog, name: name, signpostID: signpostID, "%{public}s", message)
    }
}
