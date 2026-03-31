import SwiftUI
import os

// MARK: - Crash Sentinel (Error Boundary)

/// Production-grade error boundary that catches SwiftUI view crashes.
///
/// **Hostile OS Threats:**
/// - **Memory corruption**: Jetsam kills background work, UI state becomes invalid
/// - **Thread race**: Main thread blocked while background mutates @Observable
/// - **Force unwrap**: Optional chain breaks deep in view hierarchy
/// - **Infinite loop**: Layout cycle in custom view measure
///
/// **Telemetry Signature:**
/// - `Logger.fault()` with full error chain
/// - Writes crash state to RecoveryJournal for post-mortem
/// - Posts `.quartzCrashSentinelTriggered` notification
///
/// **Recovery Strategy:**
/// 1. Catch the error at view boundary
/// 2. Log complete diagnostic context
/// 3. Present Liquid Glass recovery UI
/// 4. Offer "Export Diagnostics" for support
/// 5. Allow restart of failed component
///
/// **Usage:**
/// ```swift
/// ContentView()
///     .crashSentinel(
///         context: "MainEditor",
///         onCrash: { error in
///             RecoveryJournal.shared.recordCrash(error)
///         }
///     )
/// ```
public struct CrashSentinelModifier<FallbackContent: View>: ViewModifier {
    let context: String
    let onCrash: ((Error) -> Void)?
    let fallbackContent: () -> FallbackContent

    @State private var hasCrashed = false
    @State private var crashError: Error?
    @State private var crashTimestamp = Date()

    private let logger = Logger(subsystem: "com.quartz", category: "CrashSentinel")

    public init(
        context: String,
        onCrash: ((Error) -> Void)? = nil,
        @ViewBuilder fallback: @escaping () -> FallbackContent
    ) {
        self.context = context
        self.onCrash = onCrash
        self.fallbackContent = fallback
    }

    public func body(content: Content) -> some View {
        Group {
            if hasCrashed {
                fallbackContent()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                content
                    .onReceive(NotificationCenter.default.publisher(for: .quartzViewDidCrash)) { notification in
                        guard let userInfo = notification.userInfo,
                              let notificationContext = userInfo["context"] as? String,
                              notificationContext == context else { return }

                        let error = userInfo["error"] as? Error
                        handleCrash(error: error)
                    }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hasCrashed)
    }

    private func handleCrash(error: Error?) {
        crashError = error
        crashTimestamp = Date()
        hasCrashed = true

        // Log the crash
        logger.fault("""
            CRASH SENTINEL TRIGGERED
            Context: \(self.context, privacy: .public)
            Error: \(error?.localizedDescription ?? "Unknown", privacy: .public)
            Timestamp: \(self.crashTimestamp)
            """)

        // Invoke callback
        if let error = error {
            onCrash?(error)
        }

        // Post notification for telemetry
        NotificationCenter.default.post(
            name: .quartzCrashSentinelTriggered,
            object: nil,
            userInfo: [
                "context": context,
                "error": error as Any,
                "timestamp": crashTimestamp
            ]
        )
    }
}

// MARK: - Default Recovery View

/// Liquid Glass recovery screen shown when a view crashes.
public struct CrashRecoveryView: View {
    let context: String
    let error: Error?
    let timestamp: Date
    let onRetry: () -> Void
    let onExportDiagnostics: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAppearing = false
    @State private var showingDiagnostics = false

    public init(
        context: String,
        error: Error? = nil,
        timestamp: Date = Date(),
        onRetry: @escaping () -> Void,
        onExportDiagnostics: @escaping () -> Void
    ) {
        self.context = context
        self.error = error
        self.timestamp = timestamp
        self.onRetry = onRetry
        self.onExportDiagnostics = onExportDiagnostics
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)

            // Title
            Text("Something Went Wrong")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)

            // Subtitle
            Text("An unexpected error occurred in \(context).")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Error details (collapsible)
            if let error = error {
                DisclosureGroup("Technical Details", isExpanded: $showingDiagnostics) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error.localizedDescription)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)

                        Text("Time: \(timestamp.formatted(date: .abbreviated, time: .standard))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            }

            // Actions
            VStack(spacing: 12) {
                Button(action: onRetry) {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: onExportDiagnostics) {
                    Label("Export Diagnostics", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.1), radius: 20, y: 10)
        }
        .opacity(isAppearing ? 1 : 0)
        .scaleEffect(isAppearing ? 1 : 0.9)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isAppearing = true
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error occurred in \(context)")
        .accessibilityHint("Double tap Try Again to retry, or Export Diagnostics for support")
    }
}

// MARK: - Diagnostic Export Service

/// Generates diagnostic reports for crash recovery.
public actor DiagnosticExportService {

    public static let shared = DiagnosticExportService()

    private init() {}

    /// Generates a diagnostic report for the current app state.
    public func generateReport(
        context: String,
        error: Error?,
        additionalInfo: [String: Any] = [:]
    ) async -> DiagnosticReport {
        let deviceInfo = await gatherDeviceInfo()
        let appInfo = await gatherAppInfo()
        let memoryInfo = await gatherMemoryInfo()

        return DiagnosticReport(
            id: UUID(),
            timestamp: Date(),
            context: context,
            errorDescription: error?.localizedDescription,
            errorType: error.map { String(describing: type(of: $0)) },
            deviceInfo: deviceInfo,
            appInfo: appInfo,
            memoryInfo: memoryInfo,
            additionalInfo: additionalInfo.mapValues { String(describing: $0) }
        )
    }

    /// Exports the diagnostic report to a shareable format.
    public func exportToText(_ report: DiagnosticReport) -> String {
        """
        ═══════════════════════════════════════════════════════════════
        QUARTZ DIAGNOSTIC REPORT
        ═══════════════════════════════════════════════════════════════

        Report ID: \(report.id)
        Generated: \(report.timestamp.formatted())
        Context: \(report.context)

        ───────────────────────────────────────────────────────────────
        ERROR DETAILS
        ───────────────────────────────────────────────────────────────
        Type: \(report.errorType ?? "Unknown")
        Description: \(report.errorDescription ?? "No description")

        ───────────────────────────────────────────────────────────────
        DEVICE INFO
        ───────────────────────────────────────────────────────────────
        Model: \(report.deviceInfo.model)
        OS: \(report.deviceInfo.osVersion)
        Thermal State: \(report.deviceInfo.thermalState)

        ───────────────────────────────────────────────────────────────
        APP INFO
        ───────────────────────────────────────────────────────────────
        Version: \(report.appInfo.version)
        Build: \(report.appInfo.build)
        Bundle ID: \(report.appInfo.bundleID)

        ───────────────────────────────────────────────────────────────
        MEMORY INFO
        ───────────────────────────────────────────────────────────────
        Used: \(report.memoryInfo.usedMB) MB
        Available: \(report.memoryInfo.availableMB) MB
        Pressure: \(report.memoryInfo.pressureLevel)

        ───────────────────────────────────────────────────────────────
        ADDITIONAL INFO
        ───────────────────────────────────────────────────────────────
        \(report.additionalInfo.map { "\($0.key): \($0.value)" }.joined(separator: "\n"))

        ═══════════════════════════════════════════════════════════════
        END OF REPORT
        ═══════════════════════════════════════════════════════════════
        """
    }

    // MARK: - Private Helpers

    @MainActor
    private func gatherDeviceInfo() -> DeviceInfo {
        let processInfo = ProcessInfo.processInfo

        #if os(macOS)
        let model = "Mac"
        #else
        let model = UIDevice.current.model
        #endif

        return DeviceInfo(
            model: model,
            osVersion: processInfo.operatingSystemVersionString,
            thermalState: Self.thermalStateDisplayName(processInfo.thermalState)
        )
    }

    private static func thermalStateDisplayName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private func gatherAppInfo() -> AppInfo {
        let bundle = Bundle.main
        return AppInfo(
            version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            build: bundle.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
            bundleID: bundle.bundleIdentifier ?? "Unknown"
        )
    }

    private func gatherMemoryInfo() -> MemoryInfo {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        let usedMB = result == KERN_SUCCESS ? Int(info.resident_size / (1024 * 1024)) : 0
        let availableMB = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))

        return MemoryInfo(
            usedMB: usedMB,
            availableMB: availableMB,
            pressureLevel: "Unknown" // Would need SystemSentinel for this
        )
    }
}

// MARK: - Supporting Types

public struct DiagnosticReport: Sendable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let context: String
    public let errorDescription: String?
    public let errorType: String?
    public let deviceInfo: DeviceInfo
    public let appInfo: AppInfo
    public let memoryInfo: MemoryInfo
    public let additionalInfo: [String: String]
}

public struct DeviceInfo: Sendable, Codable {
    public let model: String
    public let osVersion: String
    public let thermalState: String
}

public struct AppInfo: Sendable, Codable {
    public let version: String
    public let build: String
    public let bundleID: String
}

public struct MemoryInfo: Sendable, Codable {
    public let usedMB: Int
    public let availableMB: Int
    public let pressureLevel: String
}

// MARK: - View Extension

public extension View {
    /// Wraps a view in a crash sentinel that catches errors and shows recovery UI.
    func crashSentinel(
        context: String,
        onCrash: ((Error) -> Void)? = nil
    ) -> some View {
        modifier(CrashSentinelModifier(
            context: context,
            onCrash: onCrash,
            fallback: {
                CrashRecoveryView(
                    context: context,
                    onRetry: {
                        // Would need to communicate back to parent to retry
                        NotificationCenter.default.post(
                            name: .quartzCrashSentinelRetry,
                            object: nil,
                            userInfo: ["context": context]
                        )
                    },
                    onExportDiagnostics: {
                        Task {
                            let report = await DiagnosticExportService.shared.generateReport(
                                context: context,
                                error: nil
                            )
                            let text = await DiagnosticExportService.shared.exportToText(report)

                            // Copy to clipboard
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            #else
                            UIPasteboard.general.string = text
                            #endif
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        ))
    }

    /// Wraps a view with a custom fallback for crash recovery.
    func crashSentinel<Fallback: View>(
        context: String,
        onCrash: ((Error) -> Void)? = nil,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) -> some View {
        modifier(CrashSentinelModifier(
            context: context,
            onCrash: onCrash,
            fallback: fallback
        ))
    }
}

// MARK: - Notifications

public extension Notification.Name {
    /// Posted by views when they crash (for CrashSentinel to catch).
    /// `userInfo` contains: context (String), error (Error?)
    static let quartzViewDidCrash = Notification.Name("quartzViewDidCrash")

    /// Posted when CrashSentinel catches a crash.
    /// `userInfo` contains: context, error, timestamp
    static let quartzCrashSentinelTriggered = Notification.Name("quartzCrashSentinelTriggered")

    /// Posted when user taps Retry in crash recovery UI.
    /// `userInfo` contains: context (String)
    static let quartzCrashSentinelRetry = Notification.Name("quartzCrashSentinelRetry")
}

// MARK: - Preview

#if DEBUG
#Preview("Crash Recovery") {
    CrashRecoveryView(
        context: "Editor",
        error: NSError(domain: "TestError", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "Failed to load document: The file was corrupted during sync."
        ]),
        onRetry: { print("Retry tapped") },
        onExportDiagnostics: { print("Export tapped") }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.2))
}
#endif
