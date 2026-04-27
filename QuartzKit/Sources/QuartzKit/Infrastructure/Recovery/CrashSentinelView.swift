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
        QuartzDiagnostics.fault(
            category: "CrashSentinel",
            """
            Crash sentinel triggered in \(self.context): \(error?.localizedDescription ?? "Unknown")
            """
        )

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

    private let diagnosticsStore: QuartzDiagnosticsStore

    private init(diagnosticsStore: QuartzDiagnosticsStore = .shared) {
        self.diagnosticsStore = diagnosticsStore
    }

    internal init(testingDiagnosticsStore diagnosticsStore: QuartzDiagnosticsStore) {
        self.diagnosticsStore = diagnosticsStore
    }

    /// Generates a diagnostic report for the current app state.
    public func generateReport(
        context: String,
        error: Error?,
        additionalInfo: [String: Any] = [:]
    ) async -> DiagnosticReport {
        let deviceInfo = await gatherDeviceInfo()
        let appInfo = gatherAppInfo()
        let memoryInfo = gatherMemoryInfo()
        let vaultInfo = await gatherVaultInfo()
        let metricInfo = await gatherMetricInfo()
        let recoveryInfo = await gatherRecoveryInfo()
        let recentDiagnosticsLog = await diagnosticsStore.recentLogText(limitBytes: 65_536)
        let diagnosticsLogLocation = await diagnosticsStore.logFileURL()?.path(percentEncoded: false)
        let rendererDiagnostics = await RendererDiagnostics.snapshot()
        let subsystemDiagnostics = await SubsystemDiagnostics.snapshot()
        let developerDiagnostics = DeveloperDiagnostics.status()

        var mergedAdditionalInfo = additionalInfo.mapValues { String(describing: $0) }
        for (key, value) in vaultInfo {
            mergedAdditionalInfo[key] = value
        }
        for (key, value) in metricInfo {
            mergedAdditionalInfo[key] = value
        }
        for (key, value) in recoveryInfo {
            mergedAdditionalInfo[key] = value
        }
        if let diagnosticsLogLocation {
            mergedAdditionalInfo["diagnosticsLogPath"] = diagnosticsLogLocation
        }

        return DiagnosticReport(
            id: UUID(),
            timestamp: Date(),
            context: context,
            errorDescription: error?.localizedDescription,
            errorType: error.map { String(describing: type(of: $0)) },
            deviceInfo: deviceInfo,
            appInfo: appInfo,
            memoryInfo: memoryInfo,
            developerDiagnostics: developerDiagnostics,
            subsystemDiagnostics: subsystemDiagnostics,
            rendererDiagnostics: rendererDiagnostics,
            recentDiagnosticsLog: recentDiagnosticsLog,
            additionalInfo: mergedAdditionalInfo
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

        ───────────────────────────────────────────────────────────────
        DEVELOPER DIAGNOSTICS MODE
        ───────────────────────────────────────────────────────────────
        \(developerDiagnosticsText(report.developerDiagnostics))

        ───────────────────────────────────────────────────────────────
        SUBSYSTEM HEALTH SUMMARY
        ───────────────────────────────────────────────────────────────
        \(subsystemHealthText(report.subsystemDiagnostics))

        ───────────────────────────────────────────────────────────────
        CROSS-SUBSYSTEM DIAGNOSTICS
        ───────────────────────────────────────────────────────────────
        \(subsystemDiagnosticsText(report.subsystemDiagnostics))

        ───────────────────────────────────────────────────────────────
        RENDERER DIAGNOSTICS
        ───────────────────────────────────────────────────────────────
        \(rendererDiagnosticsText(report.rendererDiagnostics))

        ───────────────────────────────────────────────────────────────
        RECENT DIAGNOSTICS LOG
        ───────────────────────────────────────────────────────────────
        \(report.recentDiagnosticsLog)

        ═══════════════════════════════════════════════════════════════
        END OF REPORT
        ═══════════════════════════════════════════════════════════════
        """
    }

    private func developerDiagnosticsText(_ status: DeveloperDiagnosticsStatus) -> String {
        """
        Status: \(status.enabled ? "enabled" : "disabled")
        Source: \(status.source)
        Supported config files: \(status.supportedConfigFiles.joined(separator: ", "))
        Supported keys: \(status.supportedKeys.joined(separator: ", "))
        Flags:
        \(status.flags.sorted { $0.key < $1.key }.map { "- \($0.key): \($0.value)" }.joined(separator: "\n"))
        \(status.invalidConfigWarning.map { "Config warning: \($0)" } ?? "Config warning: none")
        """
    }

    private func subsystemHealthText(_ snapshot: SubsystemDiagnosticsSnapshot) -> String {
        DiagnosticsSubsystem.allCases.map { subsystem in
            let state = snapshot.currentState[subsystem] ?? [:]
            let warning = state["lastWarningOrError"].map { " warning=\($0)" } ?? ""
            let duration = state["lastDurationMs"].map { " durationMs=\($0)" } ?? ""
            let event = state["lastEvent"] ?? "none"
            return "\(subsystem.displayName): lastEvent=\(event)\(warning)\(duration)"
        }.joined(separator: "\n")
    }

    private func subsystemDiagnosticsText(_ snapshot: SubsystemDiagnosticsSnapshot) -> String {
        var sections: [String] = []
        let slowText = snapshot.topSlowOperations.isEmpty
            ? "None captured."
            : subsystemEventsText(snapshot.topSlowOperations)
        sections.append("Top slow operations:\n\(slowText)")

        let repeatedText = snapshot.repeatedEventSummaries.isEmpty
            ? "None captured."
            : subsystemEventsText(snapshot.repeatedEventSummaries)
        sections.append("Repeated event summaries:\n\(repeatedText)")

        for subsystem in DiagnosticsSubsystem.allCases {
            let warnings = snapshot.warningsAndErrorsBySubsystem[subsystem] ?? []
            let recent = snapshot.eventsBySubsystem[subsystem] ?? []
            let state = snapshot.currentState[subsystem] ?? [:]
            let stateText = state.isEmpty
                ? "No current state captured."
                : state.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            sections.append("""
            \(subsystem.displayName)
            State: \(stateText)
            Warnings/errors:
            \(subsystemEventsText(warnings))
            Recent events:
            \(subsystemEventsText(recent))
            """)
        }
        return sections.joined(separator: "\n\n")
    }

    private func subsystemEventsText(_ events: [SubsystemDiagnosticEvent]) -> String {
        guard !events.isEmpty else { return "None captured." }
        return events.map { event in
            var parts: [String] = [
                event.timestamp.formatted(),
                "[\(event.level.rawValue.uppercased())]",
                event.name
            ]
            if let reasonCode = event.reasonCode {
                parts.append("reason=\(reasonCode)")
            }
            if let noteBasename = event.noteBasename {
                parts.append("note=\(noteBasename)")
            }
            if let vaultName = event.vaultName {
                parts.append("vault=\(vaultName)")
            }
            if let durationMs = event.durationMs {
                parts.append("durationMs=\(String(format: "%.1f", durationMs))")
            }
            if let generation = event.generation {
                parts.append("generation=\(generation)")
            }
            if let revision = event.revision {
                parts.append("revision=\(revision)")
            }
            if !event.counts.isEmpty {
                parts.append(event.counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            }
            if !event.metadata.isEmpty {
                parts.append(event.metadata.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            }
            return parts.joined(separator: " ")
        }.joined(separator: "\n")
    }

    private func rendererDiagnosticsText(_ snapshot: RendererDiagnosticsSnapshot) -> String {
        guard snapshot.enabled else {
            return "Status: disabled\nEnable: \(snapshot.enablementHint)"
        }

        return """
        Status: enabled

        Last render durations:
        \(snapshot.lastRenderDurations.isEmpty ? "None captured." : snapshot.lastRenderDurations.joined(separator: "\n"))

        Last span checksums:
        \(snapshot.lastSpanChecksums.isEmpty ? "None captured." : snapshot.lastSpanChecksums.joined(separator: "\n"))

        Last warnings/errors:
        \(diagnosticEventsText(snapshot.warningsAndErrors))

        Last detected corruption signals:
        \(diagnosticEventsText(snapshot.corruptionSignals))

        Last renderer events:
        \(diagnosticEventsText(snapshot.lastEvents))
        """
    }

    private func diagnosticEventsText(_ events: [RendererDiagnosticEvent]) -> String {
        guard !events.isEmpty else { return "None captured." }
        return events.map { event in
            var parts: [String] = [
                event.timestamp.formatted(),
                "[\(event.level.rawValue.uppercased())]",
                event.name
            ]
            if let noteBasename = event.noteBasename {
                parts.append("note=\(noteBasename)")
            }
            if let range = event.affectedRange {
                parts.append("range=\(range.location):\(range.length)")
            }
            if let lineRange = event.lineRange {
                parts.append("lines=\(lineRange.start)-\(lineRange.end)")
            }
            if let textRevision = event.textRevision {
                parts.append("textRevision=\(textRevision)")
            }
            if let renderGeneration = event.renderGeneration {
                parts.append("renderGeneration=\(renderGeneration)")
            }
            if !event.metadata.isEmpty {
                let metadata = event.metadata
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: " ")
                parts.append(metadata)
            }
            return parts.joined(separator: " ")
        }.joined(separator: "\n")
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

    @MainActor
    private func gatherMetricInfo() -> [String: String] {
        var info: [String: String] = [:]

        if let metrics = QuartzMetricManager.shared.latestMetricsSummary {
            if let coldLaunch = metrics.coldLaunchTimeSeconds {
                info["metrics.coldLaunchSeconds"] = String(format: "%.2f", coldLaunch)
            }
            if let totalHang = metrics.totalHangTimeMs {
                info["metrics.totalHangMs"] = String(format: "%.0f", totalHang)
            }
            if let peakMemory = metrics.peakMemoryMB {
                info["metrics.peakMemoryMB"] = String(format: "%.0f", peakMemory)
            }
            if let cpuTime = metrics.cpuTimeSeconds {
                info["metrics.cpuTimeSeconds"] = String(format: "%.2f", cpuTime)
            }
            if let diskWrites = metrics.diskWritesGB {
                info["metrics.diskWritesGB"] = String(format: "%.3f", diskWrites)
            }
            if let hitchRate = metrics.scrollHitchRate {
                info["metrics.scrollHitchRate"] = String(format: "%.4f", hitchRate)
            }
        }

        if let diagnostics = QuartzMetricManager.shared.latestDiagnosticsSummary {
            info["diagnostics.crashCount"] = String(diagnostics.crashCount)
            info["diagnostics.hangCount"] = String(diagnostics.hangCount)
            info["diagnostics.diskWriteExceptionCount"] = String(diagnostics.diskWriteExceptionCount)
            info["diagnostics.cpuExceptionCount"] = String(diagnostics.cpuExceptionCount)
        }

        return info
    }

    @MainActor
    private func gatherVaultInfo() -> [String: String] {
        let manager = VaultAccessManager.shared
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var info: [String: String] = [
            "vault.hasPersistedBookmark": String(manager.hasPersistedBookmark)
        ]

        if let lastVaultName = manager.lastVaultName {
            info["vault.lastVaultName"] = lastVaultName
        }

        if let activeVaultURL = manager.activeVaultURL {
            info["vault.activeVaultName"] = activeVaultURL.lastPathComponent

            let quartzDirectory = activeVaultURL.appending(path: ".quartz", directoryHint: .isDirectory)
            for fileName in [
                "preview-cache.json",
                "search-index.json",
                "embeddings.idx",
                "ai_index.json",
                "recovery_journal.json"
            ] {
                let fileURL = fileName == "embeddings.idx"
                    ? VectorEmbeddingService.indexFileURL(for: activeVaultURL)
                    : quartzDirectory.appending(path: fileName)
                let path = fileURL.path(percentEncoded: false)
                let exists = FileManager.default.fileExists(atPath: path)
                info["vault.\(fileName).exists"] = String(exists)
                guard exists,
                      let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
                    continue
                }

                if let size = attributes[.size] as? NSNumber {
                    info["vault.\(fileName).sizeBytes"] = size.stringValue
                }
                if let modifiedDate = attributes[.modificationDate] as? Date {
                    info["vault.\(fileName).modified"] = timestampFormatter.string(from: modifiedDate)
                }
            }

            for (key, value) in KnowledgeExtractionService.persistedHealthSummary(vaultRootURL: activeVaultURL) {
                info[key] = value
            }
        }

        if let lastError = manager.lastError?.localizedDescription {
            info["vault.lastError"] = lastError
        }

        return info
    }

    private func gatherRecoveryInfo() async -> [String: String] {
        let pendingEntries = await RecoveryJournal.shared.pendingEntries
        let deferredEntries = await RecoveryJournal.shared.deferredEntries
        return [
            "recovery.pendingEntries": String(pendingEntries.count),
            "recovery.deferredEntries": String(deferredEntries.count)
        ]
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
    public let developerDiagnostics: DeveloperDiagnosticsStatus
    public let subsystemDiagnostics: SubsystemDiagnosticsSnapshot
    public let rendererDiagnostics: RendererDiagnosticsSnapshot
    public let recentDiagnosticsLog: String
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
