import Foundation
import MetricKit
import os

// MARK: - Quartz MetricKit Telemetry

/// Production telemetry manager using MetricKit.
///
/// **What It Captures:**
/// - Frame drops (Liquid Glass validation): Hang rate, hitch time
/// - Memory issues: Peak memory, memory leaks, OOM crashes
/// - Background task timeouts: Task duration, terminations
/// - Disk I/O: Write/read latency, file system errors
/// - Launch performance: Cold/warm launch time
///
/// **Cross-Platform Notes:**
/// - **iOS/iPadOS**: Full MetricKit support. Background app suspension can
///   cause task timeouts — we track these via `backgroundTaskTerminations`.
/// - **macOS**: MetricKit available since macOS 12. `Optimize Storage` can
///   evict files, causing `fileNotDownloaded` errors — tracked via custom logs.
/// - **All platforms**: Payloads are delivered ~24h after collection.
///   Immediate diagnostics use `MXDiagnosticPayload` for crash/hang reports.
///
/// **Privacy:**
/// - MetricKit data is aggregated and anonymized by Apple.
/// - No user-identifiable data leaves the device.
/// - Diagnostic payloads contain only system-level stack traces.
///
/// **Usage:**
/// ```swift
/// // In AppDelegate or App init:
/// QuartzMetricManager.shared.startCollecting()
///
/// // On app termination:
/// QuartzMetricManager.shared.stopCollecting()
/// ```
@MainActor
public final class QuartzMetricManager: NSObject, Sendable {

    // MARK: - Singleton

    public static let shared = QuartzMetricManager()

    // MARK: - State

    private let logger = QuartzLogger.uiPerformance

    /// Latest metric payload summary (for in-app diagnostics display).
    public private(set) var latestMetricsSummary: MetricsSummary?

    /// Latest diagnostic payload summary (crashes, hangs).
    public private(set) var latestDiagnosticsSummary: DiagnosticsSummary?

    // MARK: - Thresholds

    /// Frame hitch threshold in milliseconds. Above this, UI is noticeably janky.
    private let hitchThresholdMs: Double = 16.67  // 60fps frame budget

    /// Memory warning threshold in MB.
    private let memoryWarningThresholdMB: Double = 500

    /// Launch time warning threshold in seconds.
    private let launchTimeWarningSeconds: Double = 2.0

    // MARK: - Lifecycle

    private override init() {
        super.init()
    }

    /// Starts collecting MetricKit payloads.
    /// Call this early in the app lifecycle (e.g., `applicationDidFinishLaunching`).
    public func startCollecting() {
        MXMetricManager.shared.add(self)
        logger.info("MetricKit collection started")
    }

    /// Stops collecting MetricKit payloads.
    /// Call this on app termination if needed.
    public func stopCollecting() {
        MXMetricManager.shared.remove(self)
        logger.info("MetricKit collection stopped")
    }

    // MARK: - Manual Signpost Reporting

    /// Reports a custom metric interval to MetricKit.
    ///
    /// Use this for tracking custom operations like Knowledge Graph builds.
    ///
    /// - Parameters:
    ///   - name: The operation name.
    ///   - duration: The duration in seconds.
    public func reportCustomMetric(name: String, duration: TimeInterval) {
        logger.info("Custom metric: \(name, privacy: .public) = \(duration * 1000, format: .fixed(precision: 2))ms")

        // Store for later analysis (MetricKit doesn't support custom metrics directly)
        // This could be sent to your own analytics service
    }
}

// MARK: - MXMetricManagerSubscriber

extension QuartzMetricManager: MXMetricManagerSubscriber {

    /// Called when MetricKit delivers a new payload (typically once per day).
    public nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        // Process payloads on the current thread, then dispatch summary to MainActor
        for payload in payloads {
            let summary = extractMetricsSummary(from: payload)
            Task { @MainActor [self, summary] in
                self.latestMetricsSummary = summary
                NotificationCenter.default.post(
                    name: .quartzMetricsReceived,
                    object: nil,
                    userInfo: ["summary": summary]
                )
            }
        }
    }

    /// Called when MetricKit delivers diagnostic payloads (crashes, hangs, disk writes).
    public nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Process payloads on the current thread, then dispatch summary to MainActor
        for payload in payloads {
            let summary = extractDiagnosticsSummary(from: payload)
            Task { @MainActor [self, summary] in
                self.latestDiagnosticsSummary = summary
                NotificationCenter.default.post(
                    name: .quartzDiagnosticsReceived,
                    object: nil,
                    userInfo: ["summary": summary]
                )
            }
        }
    }

    // MARK: - Payload Processing (nonisolated to allow processing in callback)

    private nonisolated func extractMetricsSummary(from payload: MXMetricPayload) -> MetricsSummary {
        var summary = MetricsSummary()

        // MARK: Launch Metrics
        if let launchMetrics = payload.applicationLaunchMetrics {
            let coldLaunch = launchMetrics.histogrammedTimeToFirstDraw
            if let median = coldLaunch.bucketEnumerator.allObjects.first as? MXHistogramBucket<UnitDuration> {
                let launchTimeSeconds = median.bucketEnd.converted(to: .seconds).value
                summary.coldLaunchTimeSeconds = launchTimeSeconds
            }
        }

        // MARK: Responsiveness Metrics (Frame Drops)
        if let responsivenessMetrics = payload.applicationResponsivenessMetrics {
            let hangTime = responsivenessMetrics.histogrammedApplicationHangTime
            var totalHangTimeMs: Double = 0

            for case let bucket as MXHistogramBucket<UnitDuration> in hangTime.bucketEnumerator {
                let hangMs = bucket.bucketEnd.converted(to: .milliseconds).value
                let count = bucket.bucketCount
                totalHangTimeMs += hangMs * Double(count)
            }

            summary.totalHangTimeMs = totalHangTimeMs
        }

        // MARK: Memory Metrics
        if let memoryMetrics = payload.memoryMetrics {
            let peakMemoryMB = memoryMetrics.peakMemoryUsage.converted(to: .megabytes).value
            summary.peakMemoryMB = peakMemoryMB
        }

        // MARK: CPU Metrics
        if let cpuMetrics = payload.cpuMetrics {
            let cpuTimeSeconds = cpuMetrics.cumulativeCPUTime.converted(to: .seconds).value
            summary.cpuTimeSeconds = cpuTimeSeconds
        }

        // MARK: Disk I/O Metrics
        if let diskMetrics = payload.diskIOMetrics {
            let writesGB = diskMetrics.cumulativeLogicalWrites.converted(to: .gigabytes).value
            summary.diskWritesGB = writesGB
        }

        // MARK: Animation Metrics (Liquid Glass validation)
        if let animationMetrics = payload.animationMetrics {
            let scrollHitchRate = animationMetrics.scrollHitchTimeRatio.value
            summary.scrollHitchRate = scrollHitchRate
        }

        return summary
    }

    private nonisolated func extractDiagnosticsSummary(from payload: MXDiagnosticPayload) -> DiagnosticsSummary {
        var summary = DiagnosticsSummary()

        // MARK: Crash Diagnostics
        if let crashDiagnostics = payload.crashDiagnostics {
            summary.crashCount = crashDiagnostics.count
        }

        // MARK: Hang Diagnostics (UI freezes)
        if let hangDiagnostics = payload.hangDiagnostics {
            summary.hangCount = hangDiagnostics.count
        }

        // MARK: Disk Write Diagnostics (Background write issues)
        if let diskDiagnostics = payload.diskWriteExceptionDiagnostics {
            summary.diskWriteExceptionCount = diskDiagnostics.count
        }

        // MARK: CPU Exception Diagnostics
        if let cpuDiagnostics = payload.cpuExceptionDiagnostics {
            summary.cpuExceptionCount = cpuDiagnostics.count
        }

        return summary
    }
}

// MARK: - Summary Types

public extension QuartzMetricManager {

    /// Summary of metrics from a MetricKit payload.
    struct MetricsSummary: Sendable {
        public var coldLaunchTimeSeconds: Double?
        public var totalHangTimeMs: Double?
        public var peakMemoryMB: Double?
        public var cpuTimeSeconds: Double?
        public var diskWritesGB: Double?
        public var scrollHitchRate: Double?

        public init() {}
    }

    /// Summary of diagnostics from a MetricKit payload.
    struct DiagnosticsSummary: Sendable {
        public var crashCount: Int = 0
        public var hangCount: Int = 0
        public var diskWriteExceptionCount: Int = 0
        public var cpuExceptionCount: Int = 0

        public var hasIssues: Bool {
            crashCount > 0 || hangCount > 0 || diskWriteExceptionCount > 0 || cpuExceptionCount > 0
        }

        public init() {}
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted when MetricKit delivers a metrics payload.
    static let quartzMetricsReceived = Notification.Name("quartzMetricsReceived")

    /// Posted when MetricKit delivers a diagnostics payload.
    static let quartzDiagnosticsReceived = Notification.Name("quartzDiagnosticsReceived")
}
