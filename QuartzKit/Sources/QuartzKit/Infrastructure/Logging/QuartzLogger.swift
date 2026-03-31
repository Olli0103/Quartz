import Foundation
import os

// MARK: - Quartz Unified Logging Infrastructure

/// Centralized, privacy-respecting logging for the Quartz app.
///
/// Uses Apple's `os.Logger` with categorized subsystems for filtering in Console.app.
/// All production logs respect user privacy — file paths and content are marked `<private>`.
///
/// **Usage:**
/// ```swift
/// QuartzLogger.fileSystem.info("Loading vault at \(url, privacy: .private)")
/// QuartzLogger.intelligence.debug("Indexed \(count) notes")
/// QuartzLogger.uiPerformance.warning("Frame drop detected: \(duration)ms")
/// ```
///
/// **Filtering in Console.app:**
/// - Filter by `subsystem:com.quartz` for all Quartz logs
/// - Filter by `category:fileSystem` for specific category
///
/// **Cross-Platform Notes:**
/// - macOS: Logs persist to unified logging system, viewable via Console.app
/// - iOS/iPadOS: Logs viewable via Xcode console or `log` CLI when device is connected
/// - All platforms: MetricKit captures aggregated diagnostic data
public enum QuartzLogger {

    // MARK: - Subsystem

    /// The app's bundle identifier used as the logging subsystem.
    private static let subsystem = "com.olli.QuartzNotes"

    // MARK: - Category Loggers

    /// File system operations: vault loading, note save/load, iCloud coordination.
    public static let fileSystem = Logger(subsystem: subsystem, category: "fileSystem")

    /// Intelligence Engine: embeddings, semantic links, concept extraction, graph building.
    public static let intelligence = Logger(subsystem: subsystem, category: "intelligence")

    /// UI Performance: frame drops, rendering latency, animation timing.
    public static let uiPerformance = Logger(subsystem: subsystem, category: "uiPerformance")

    /// Cloud Sync: iCloud Drive status, conflict resolution, sync progress.
    public static let sync = Logger(subsystem: subsystem, category: "sync")

    /// Security: biometric auth, encryption, keychain access.
    public static let security = Logger(subsystem: subsystem, category: "security")

    /// Editor: TextKit operations, highlighting, list continuation.
    public static let editor = Logger(subsystem: subsystem, category: "editor")

    /// AI Services: chat, embeddings, provider interactions.
    public static let ai = Logger(subsystem: subsystem, category: "ai")

    /// Navigation: sidebar, note selection, wiki-link navigation.
    public static let navigation = Logger(subsystem: subsystem, category: "navigation")

    // MARK: - Signpost Support

    /// Signpost logger for performance instrumentation with Instruments.app.
    ///
    /// **Usage:**
    /// ```swift
    /// let signpostID = OSSignpostID(log: QuartzLogger.signpost)
    /// os_signpost(.begin, log: QuartzLogger.signpost, name: "BuildGraph", signpostID: signpostID)
    /// // ... work ...
    /// os_signpost(.end, log: QuartzLogger.signpost, name: "BuildGraph", signpostID: signpostID)
    /// ```
    public static let signpost = OSLog(subsystem: subsystem, category: .pointsOfInterest)

    // MARK: - Convenience Methods

    /// Logs an operation with automatic begin/end signposting.
    ///
    /// - Parameters:
    ///   - name: The signpost name (visible in Instruments).
    ///   - logger: The category logger for text logs.
    ///   - operation: The async operation to measure.
    /// - Returns: The result of the operation.
    @inlinable
    public static func measure<T>(
        _ name: StaticString,
        logger: Logger,
        operation: () async throws -> T
    ) async rethrows -> T {
        let signpostID = OSSignpostID(log: signpost)
        os_signpost(.begin, log: signpost, name: name, signpostID: signpostID)
        defer { os_signpost(.end, log: signpost, name: name, signpostID: signpostID) }

        logger.debug("Starting: \(name, privacy: .public)")
        let start = CFAbsoluteTimeGetCurrent()

        let result = try await operation()

        let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
        logger.debug("Completed: \(name, privacy: .public) in \(duration, format: .fixed(precision: 2))ms")

        return result
    }

    /// Logs an error with full context.
    ///
    /// - Parameters:
    ///   - error: The error to log.
    ///   - context: Additional context string.
    ///   - logger: The category logger.
    @inlinable
    public static func logError(
        _ error: Error,
        context: String,
        logger: Logger
    ) {
        let nsError = error as NSError
        logger.error("""
            [\(context, privacy: .public)] Error: \(error.localizedDescription, privacy: .public)
            Domain: \(nsError.domain, privacy: .public)
            Code: \(nsError.code)
            UserInfo: \(String(describing: nsError.userInfo), privacy: .private)
            """)
    }
}

// MARK: - Privacy Helpers

public extension QuartzLogger {

    /// Redacts a file path for logging, showing only the filename.
    ///
    /// - Parameter url: The file URL to redact.
    /// - Returns: Just the last path component (filename).
    @inlinable
    static func redactedPath(_ url: URL) -> String {
        url.lastPathComponent
    }

    /// Redacts a vault-relative path for logging.
    ///
    /// - Parameters:
    ///   - url: The file URL.
    ///   - vaultRoot: The vault root URL.
    /// - Returns: The relative path within the vault.
    @inlinable
    static func relativePath(_ url: URL, in vaultRoot: URL) -> String {
        let fullPath = url.path(percentEncoded: false)
        let rootPath = vaultRoot.path(percentEncoded: false)
        guard fullPath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(fullPath.dropFirst(rootPath.count + 1))
    }
}

// MARK: - Log Level Convenience

public extension Logger {

    /// Logs a trace-level message (most verbose, for debugging).
    @inlinable
    func trace(_ message: String) {
        self.log(level: .debug, "\(message, privacy: .public)")
    }

    /// Logs a success message (info level with checkmark prefix).
    @inlinable
    func success(_ message: String) {
        self.info("✓ \(message, privacy: .public)")
    }

    /// Logs a performance warning (when thresholds exceeded).
    @inlinable
    func performanceWarning(_ message: String, threshold: Double, actual: Double) {
        self.warning("⚠️ Performance: \(message, privacy: .public) (threshold: \(threshold)ms, actual: \(actual, format: .fixed(precision: 2))ms)")
    }
}

// MARK: - Debug Build Helpers

#if DEBUG
public extension QuartzLogger {

    /// Logs to console only in debug builds (for development).
    @inlinable
    static func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        let message = items.map { String(describing: $0) }.joined(separator: separator)
        print("[QuartzDebug] \(message)", terminator: terminator)
    }
}
#endif
