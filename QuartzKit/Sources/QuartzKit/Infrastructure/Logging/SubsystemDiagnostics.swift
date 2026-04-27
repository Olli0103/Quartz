import Foundation

public enum DiagnosticsSubsystem: String, Codable, Sendable, CaseIterable {
    case save
    case fileCoordination
    case versionHistory
    case vaultRestore
    case indexing
    case embeddings
    case aiIndexing
    case renderer
    case backgroundTasks
    case graph
    case dashboard
    case diagnostics

    public var displayName: String {
        switch self {
        case .save: "Save / Autosave"
        case .fileCoordination: "iCloud / File Coordination"
        case .versionHistory: "Version History"
        case .vaultRestore: "Vault Restore / Security Scope"
        case .indexing: "Indexing / Search / Preview / Spotlight"
        case .embeddings: "Embeddings"
        case .aiIndexing: "AI Concept Extraction / AI Indexing"
        case .renderer: "Renderer / Markdown / TextKit"
        case .backgroundTasks: "Background Task Scheduler / Runtime Health"
        case .graph: "Knowledge Graph"
        case .dashboard: "Dashboard / Home / Metrics"
        case .diagnostics: "Diagnostics"
        }
    }

    static func inferred(from category: String) -> DiagnosticsSubsystem {
        let normalized = category.lowercased()
        if normalized.contains("save") || normalized.contains("editor") { return .save }
        if normalized.contains("coordinated") || normalized.contains("file") || normalized.contains("icloud") { return .fileCoordination }
        if normalized.contains("version") { return .versionHistory }
        if normalized.contains("vault") || normalized.contains("security") { return .vaultRestore }
        if normalized.contains("search") || normalized.contains("preview") || normalized.contains("spotlight") || normalized.contains("indexingtelemetry") { return .indexing }
        if normalized.contains("embedding") { return .embeddings }
        if normalized.contains("intelligence") || normalized.contains("knowledge") || normalized.contains("ai") { return .aiIndexing }
        if normalized.contains("renderer") || normalized.contains("textkit") { return .renderer }
        if normalized.contains("graph") { return .graph }
        if normalized.contains("dashboard") { return .dashboard }
        return .backgroundTasks
    }
}

public enum DiagnosticsEventLevel: String, Codable, Sendable {
    case debug
    case info
    case warning
    case error

    var isWarningOrError: Bool { self == .warning || self == .error }
}

public enum DiagnosticPrivacy {
    private static let sensitiveKeyFragments = [
        "body", "content", "prompt", "secret", "token", "credential", "apikey", "apiKey", "password"
    ]
    private static let pathLikePattern = #"(?:/[^/\s]+){2,}/?[^,\s)]*"#

    public static func sanitizedMetadata(_ metadata: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in metadata {
            let lowerKey = key.lowercased()
            if sensitiveKeyFragments.contains(where: { lowerKey.contains($0.lowercased()) }),
               !["contentLength", "bodyLength", "textLength", "chunkCount"].contains(key) {
                result[key] = "<redacted>"
                continue
            }
            if lowerKey.contains("path") || lowerKey.contains("url") {
                result[key] = safePathDescription(value)
            } else {
                result[key] = sanitizeFreeformMessage(value)
            }
        }
        return result
    }

    public static func sanitizeFreeformMessage(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " \\n ")
        var sanitized = normalized
        if let sensitiveRegex = try? NSRegularExpression(
            pattern: #"(?i)\b(body|content|prompt|token|secret|password|credential)=("[^"]*"|'[^']*'|[^\s,)]*)"#
        ) {
            let nsValue = sanitized as NSString
            let fullRange = NSRange(location: 0, length: nsValue.length)
            for match in sensitiveRegex.matches(in: sanitized, range: fullRange).reversed() {
                let key = nsValue.substring(with: match.range(at: 1))
                if let range = Range(match.range, in: sanitized) {
                    sanitized.replaceSubrange(range, with: "\(key)=<redacted>")
                }
            }
        }
        guard let regex = try? NSRegularExpression(pattern: pathLikePattern) else {
            return String(sanitized.prefix(500))
        }
        let nsValue = sanitized as NSString
        let fullRange = NSRange(location: 0, length: nsValue.length)
        for match in regex.matches(in: sanitized, range: fullRange).reversed() {
            let rawPath = nsValue.substring(with: match.range)
            let basename = URL(fileURLWithPath: rawPath).lastPathComponent
            let replacement = "<path:\(basename.isEmpty ? "redacted" : basename)>"
            if let range = Range(match.range, in: sanitized) {
                sanitized.replaceSubrange(range, with: replacement)
            }
        }
        return String(sanitized.prefix(500))
    }

    public static func safePathDescription(_ value: String) -> String {
        guard value.contains("/") else { return String(value.prefix(160)) }
        let basename = URL(fileURLWithPath: value).lastPathComponent
        return "<path:\(basename.isEmpty ? "redacted" : basename)>"
    }
}

public struct SubsystemDiagnosticEvent: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let subsystem: DiagnosticsSubsystem
    public let level: DiagnosticsEventLevel
    public let name: String
    public let reasonCode: String?
    public let noteBasename: String?
    public let vaultName: String?
    public let durationMs: Double?
    public let counts: [String: Int]
    public let generation: UInt64?
    public let revision: UInt64?
    public let metadata: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        subsystem: DiagnosticsSubsystem,
        level: DiagnosticsEventLevel = .info,
        name: String,
        reasonCode: String? = nil,
        noteBasename: String? = nil,
        vaultName: String? = nil,
        durationMs: Double? = nil,
        counts: [String: Int] = [:],
        generation: UInt64? = nil,
        revision: UInt64? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.subsystem = subsystem
        self.level = level
        self.name = name
        self.reasonCode = reasonCode
        self.noteBasename = noteBasename
        self.vaultName = vaultName
        self.durationMs = durationMs
        self.counts = counts
        self.generation = generation
        self.revision = revision
        self.metadata = DiagnosticPrivacy.sanitizedMetadata(metadata)
    }
}

public struct DeveloperDiagnosticsStatus: Codable, Sendable, Equatable {
    public let enabled: Bool
    public let source: String
    public let supportedConfigFiles: [String]
    public let supportedKeys: [String]
    public let flags: [String: String]
    public let invalidConfigWarning: String?

    public init(
        enabled: Bool,
        source: String,
        supportedConfigFiles: [String],
        supportedKeys: [String],
        flags: [String: String],
        invalidConfigWarning: String? = nil
    ) {
        self.enabled = enabled
        self.source = source
        self.supportedConfigFiles = supportedConfigFiles
        self.supportedKeys = supportedKeys
        self.flags = flags
        self.invalidConfigWarning = invalidConfigWarning
    }
}

public enum DeveloperDiagnostics {
    public static let developerModeKey = "quartz.developerDiagnostics.enabled"
    public static let developerModeSourceKey = "quartz.developerDiagnostics.source"
    public static let invalidConfigWarningKey = "quartz.developerDiagnostics.invalidConfigWarning"
    public static let rendererDiagnosticsKey = "quartz.developerDiagnostics.rendererDiagnosticsEnabled"
    public static let verboseIndexingKey = "quartz.developerDiagnostics.verboseIndexingDiagnosticsEnabled"
    public static let verboseAIKey = "quartz.developerDiagnostics.verboseAIDiagnosticsEnabled"
    public static let verboseSaveKey = "quartz.developerDiagnostics.verboseSaveDiagnosticsEnabled"
    public static let verboseGraphKey = "quartz.developerDiagnostics.verboseGraphDiagnosticsEnabled"
    public static let verboseDashboardKey = "quartz.developerDiagnostics.verboseDashboardDiagnosticsEnabled"
    public static let includeDebugTimingsKey = "quartz.developerDiagnostics.includeDebugTimings"

    public static let configFileNames = ["developer-diagnostics.json", "diagnostics.json"]
    public static let supportedKeys = [
        "developerDiagnosticsEnabled",
        "rendererDiagnosticsEnabled",
        "verboseIndexingDiagnosticsEnabled",
        "verboseAIDiagnosticsEnabled",
        "verboseSaveDiagnosticsEnabled",
        "verboseGraphDiagnosticsEnabled",
        "verboseDashboardDiagnosticsEnabled",
        "includeDebugTimings",
        "maxRendererEvents",
        "maxSubsystemEvents"
    ]

    private struct FileConfig: Decodable {
        var developerDiagnosticsEnabled: Bool?
        var rendererDiagnosticsEnabled: Bool?
        var verboseIndexingDiagnosticsEnabled: Bool?
        var verboseAIDiagnosticsEnabled: Bool?
        var verboseSaveDiagnosticsEnabled: Bool?
        var verboseGraphDiagnosticsEnabled: Bool?
        var verboseDashboardDiagnosticsEnabled: Bool?
        var includeDebugTimings: Bool?
        var maxRendererEvents: Int?
        var maxSubsystemEvents: Int?
    }

    public static var isEnabled: Bool {
        if ProcessInfo.processInfo.arguments.contains("-QuartzDeveloperDiagnostics") {
            return true
        }
        if ProcessInfo.processInfo.environment["QUARTZ_DEVELOPER_DIAGNOSTICS"] == "1" {
            return true
        }
        return UserDefaults.standard.bool(forKey: developerModeKey)
    }

    public static var isRendererDiagnosticsEnabled: Bool {
        isEnabled && UserDefaults.standard.bool(forKey: rendererDiagnosticsKey)
    }

    public static var includeDebugTimings: Bool {
        isEnabled && UserDefaults.standard.bool(forKey: includeDebugTimingsKey)
    }

    public static func verboseDiagnosticsEnabled(for subsystem: DiagnosticsSubsystem) -> Bool {
        guard isEnabled else { return false }
        switch subsystem {
        case .save, .fileCoordination, .versionHistory, .vaultRestore:
            return UserDefaults.standard.bool(forKey: verboseSaveKey)
        case .indexing, .embeddings:
            return UserDefaults.standard.bool(forKey: verboseIndexingKey)
        case .aiIndexing:
            return UserDefaults.standard.bool(forKey: verboseAIKey)
        case .graph:
            return UserDefaults.standard.bool(forKey: verboseGraphKey)
        case .dashboard:
            return UserDefaults.standard.bool(forKey: verboseDashboardKey)
        case .renderer:
            return isRendererDiagnosticsEnabled
        case .backgroundTasks, .diagnostics:
            return includeDebugTimings
        }
    }

    public static func loadVaultConfiguration(from vaultRoot: URL) {
        let quartzDirectory = vaultRoot.appending(path: ".quartz", directoryHint: .isDirectory)
        let fileURL = configFileNames
            .map { quartzDirectory.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }

        guard let fileURL else {
            clearFileBackedConfiguration()
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let config = try JSONDecoder().decode(FileConfig.self, from: data)
            apply(config, source: ".quartz file")
            UserDefaults.standard.removeObject(forKey: invalidConfigWarningKey)
            SubsystemDiagnostics.record(
                level: .info,
                subsystem: .diagnostics,
                name: "developerModeConfigLoaded",
                reasonCode: config.developerDiagnosticsEnabled == true ? "diagnostics.developerModeEnabled" : nil,
                vaultName: vaultRoot.lastPathComponent,
                metadata: ["configFile": fileURL.lastPathComponent]
            )
        } catch {
            let warning = "Invalid developer diagnostics config \(fileURL.lastPathComponent): \(error.localizedDescription)"
            UserDefaults.standard.set(warning, forKey: invalidConfigWarningKey)
            SubsystemDiagnostics.record(
                level: .warning,
                subsystem: .diagnostics,
                name: "developerModeConfigInvalid",
                reasonCode: "diagnostics.configInvalid",
                vaultName: vaultRoot.lastPathComponent,
                metadata: ["configFile": fileURL.lastPathComponent, "error": error.localizedDescription]
            )
            QuartzDiagnostics.warning(category: "Diagnostics", warning)
        }
    }

    public static func status() -> DeveloperDiagnosticsStatus {
        var source = "disabled"
        if ProcessInfo.processInfo.arguments.contains("-QuartzDeveloperDiagnostics") {
            source = "launch argument"
        } else if ProcessInfo.processInfo.environment["QUARTZ_DEVELOPER_DIAGNOSTICS"] == "1" {
            source = "environment"
        } else if let storedSource = UserDefaults.standard.string(forKey: developerModeSourceKey),
                  UserDefaults.standard.bool(forKey: developerModeKey) {
            source = storedSource
        } else if UserDefaults.standard.bool(forKey: developerModeKey) {
            source = "UserDefaults"
        }

        return DeveloperDiagnosticsStatus(
            enabled: isEnabled,
            source: source,
            supportedConfigFiles: configFileNames.map { ".quartz/\($0)" },
            supportedKeys: supportedKeys,
            flags: [
                "rendererDiagnosticsEnabled": String(isRendererDiagnosticsEnabled),
                "verboseIndexingDiagnosticsEnabled": String(UserDefaults.standard.bool(forKey: verboseIndexingKey)),
                "verboseAIDiagnosticsEnabled": String(UserDefaults.standard.bool(forKey: verboseAIKey)),
                "verboseSaveDiagnosticsEnabled": String(UserDefaults.standard.bool(forKey: verboseSaveKey)),
                "verboseGraphDiagnosticsEnabled": String(UserDefaults.standard.bool(forKey: verboseGraphKey)),
                "verboseDashboardDiagnosticsEnabled": String(UserDefaults.standard.bool(forKey: verboseDashboardKey)),
                "includeDebugTimings": String(includeDebugTimings)
            ],
            invalidConfigWarning: UserDefaults.standard.string(forKey: invalidConfigWarningKey)
        )
    }

    public static func resetForTesting() {
        [
            developerModeKey,
            developerModeSourceKey,
            invalidConfigWarningKey,
            rendererDiagnosticsKey,
            verboseIndexingKey,
            verboseAIKey,
            verboseSaveKey,
            verboseGraphKey,
            verboseDashboardKey,
            includeDebugTimingsKey
        ].forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    private static func apply(_ config: FileConfig, source: String) {
        if let enabled = config.developerDiagnosticsEnabled {
            UserDefaults.standard.set(enabled, forKey: developerModeKey)
            UserDefaults.standard.set(source, forKey: developerModeSourceKey)
        }
        set(config.rendererDiagnosticsEnabled, forKey: rendererDiagnosticsKey)
        set(config.verboseIndexingDiagnosticsEnabled, forKey: verboseIndexingKey)
        set(config.verboseAIDiagnosticsEnabled, forKey: verboseAIKey)
        set(config.verboseSaveDiagnosticsEnabled, forKey: verboseSaveKey)
        set(config.verboseGraphDiagnosticsEnabled, forKey: verboseGraphKey)
        set(config.verboseDashboardDiagnosticsEnabled, forKey: verboseDashboardKey)
        set(config.includeDebugTimings, forKey: includeDebugTimingsKey)

        if let maxSubsystemEvents = config.maxSubsystemEvents {
            Task { await SubsystemDiagnosticsStore.shared.setCapacity(maxSubsystemEvents) }
        }
        if let maxRendererEvents = config.maxRendererEvents {
            Task { await RendererDiagnosticsStore.shared.setCapacity(maxRendererEvents) }
        }
    }

    private static func set(_ value: Bool?, forKey key: String) {
        guard let value else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func clearFileBackedConfiguration() {
        guard UserDefaults.standard.string(forKey: developerModeSourceKey) == ".quartz file" else { return }
        resetForTesting()
    }
}

public struct SubsystemDiagnosticsSnapshot: Codable, Sendable, Equatable {
    public let recentEvents: [SubsystemDiagnosticEvent]
    public let eventsBySubsystem: [DiagnosticsSubsystem: [SubsystemDiagnosticEvent]]
    public let warningsAndErrorsBySubsystem: [DiagnosticsSubsystem: [SubsystemDiagnosticEvent]]
    public let topSlowOperations: [SubsystemDiagnosticEvent]
    public let repeatedEventSummaries: [SubsystemDiagnosticEvent]
    public let currentState: [DiagnosticsSubsystem: [String: String]]

    public init(
        recentEvents: [SubsystemDiagnosticEvent],
        eventsBySubsystem: [DiagnosticsSubsystem: [SubsystemDiagnosticEvent]],
        warningsAndErrorsBySubsystem: [DiagnosticsSubsystem: [SubsystemDiagnosticEvent]],
        topSlowOperations: [SubsystemDiagnosticEvent],
        repeatedEventSummaries: [SubsystemDiagnosticEvent],
        currentState: [DiagnosticsSubsystem: [String: String]]
    ) {
        self.recentEvents = recentEvents
        self.eventsBySubsystem = eventsBySubsystem
        self.warningsAndErrorsBySubsystem = warningsAndErrorsBySubsystem
        self.topSlowOperations = topSlowOperations
        self.repeatedEventSummaries = repeatedEventSummaries
        self.currentState = currentState
    }
}

public actor SubsystemDiagnosticsStore {
    public static let shared = SubsystemDiagnosticsStore()

    private var capacity: Int
    private var events: [SubsystemDiagnosticEvent] = []
    private var repeatedCounts: [String: Int] = [:]
    private var currentState: [DiagnosticsSubsystem: [String: String]] = [:]

    public init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
    }

    public func setCapacity(_ capacity: Int) {
        self.capacity = max(1, min(capacity, 5_000))
        trimIfNeeded()
    }

    public func reset() {
        events.removeAll()
        repeatedCounts.removeAll()
        currentState.removeAll()
    }

    public func record(_ event: SubsystemDiagnosticEvent) {
        let key = repeatKey(for: event)
        let count = (repeatedCounts[key] ?? 0) + 1
        repeatedCounts[key] = count

        if count <= 3 {
            append(event)
        } else if count == 4 || count.isMultiple(of: 10) {
            append(SubsystemDiagnosticEvent(
                subsystem: event.subsystem,
                level: event.level,
                name: "\(event.name).repeated",
                reasonCode: event.reasonCode,
                noteBasename: event.noteBasename,
                vaultName: event.vaultName,
                counts: ["repeatCount": count],
                metadata: event.metadata.merging(["summary": "Repeated identical diagnostic event"]) { current, _ in current }
            ))
        }

        updateState(from: event)
    }

    public func updateState(
        subsystem: DiagnosticsSubsystem,
        values: [String: String]
    ) {
        var state = currentState[subsystem] ?? [:]
        for (key, value) in DiagnosticPrivacy.sanitizedMetadata(values) {
            state[key] = value
        }
        currentState[subsystem] = state
    }

    public func snapshot() -> SubsystemDiagnosticsSnapshot {
        var bySubsystem: [DiagnosticsSubsystem: [SubsystemDiagnosticEvent]] = [:]
        var warnings: [DiagnosticsSubsystem: [SubsystemDiagnosticEvent]] = [:]
        for subsystem in DiagnosticsSubsystem.allCases {
            bySubsystem[subsystem] = Array(events.filter { $0.subsystem == subsystem }.suffix(80))
            warnings[subsystem] = Array(events.filter { $0.subsystem == subsystem && $0.level.isWarningOrError }.suffix(30))
        }
        let slow = events
            .filter { ($0.durationMs ?? 0) > 0 }
            .sorted { ($0.durationMs ?? 0) > ($1.durationMs ?? 0) }
            .prefix(20)
        let repeated = events.filter { $0.name.hasSuffix(".repeated") }.suffix(30)
        return SubsystemDiagnosticsSnapshot(
            recentEvents: Array(events.suffix(150)),
            eventsBySubsystem: bySubsystem,
            warningsAndErrorsBySubsystem: warnings,
            topSlowOperations: Array(slow),
            repeatedEventSummaries: Array(repeated),
            currentState: currentState
        )
    }

    private func append(_ event: SubsystemDiagnosticEvent) {
        events.append(event)
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    private func repeatKey(for event: SubsystemDiagnosticEvent) -> String {
        [
            event.subsystem.rawValue,
            event.level.rawValue,
            event.name,
            event.reasonCode ?? "",
            event.noteBasename ?? "",
            event.vaultName ?? "",
            event.metadata["error"] ?? "",
            event.metadata["message"] ?? ""
        ].joined(separator: "|")
    }

    private func updateState(from event: SubsystemDiagnosticEvent) {
        var state = currentState[event.subsystem] ?? [:]
        state["lastEvent"] = event.name
        state["lastLevel"] = event.level.rawValue
        if let reasonCode = event.reasonCode {
            state["lastReasonCode"] = reasonCode
        }
        if let duration = event.durationMs {
            state["lastDurationMs"] = String(format: "%.1f", duration)
        }
        if let noteBasename = event.noteBasename {
            state["lastNote"] = noteBasename
        }
        if let vaultName = event.vaultName {
            state["lastVault"] = vaultName
        }
        if event.level.isWarningOrError {
            state["lastWarningOrError"] = event.reasonCode ?? event.name
        }
        for (key, value) in event.metadata where key.hasPrefix("state.") || key.hasPrefix("status.") || key.hasPrefix("last.") {
            state[String(key.dropFirst(key.contains(".") ? key.split(separator: ".", maxSplits: 1).first!.count + 1 : 0))] = value
        }
        currentState[event.subsystem] = state
    }
}

public enum SubsystemDiagnostics {
    public static func record(
        level: DiagnosticsEventLevel = .info,
        subsystem: DiagnosticsSubsystem,
        name: String,
        reasonCode: String? = nil,
        noteBasename: String? = nil,
        vaultName: String? = nil,
        durationMs: Double? = nil,
        counts: [String: Int] = [:],
        generation: UInt64? = nil,
        revision: UInt64? = nil,
        metadata: [String: String] = [:],
        verbose: Bool = false
    ) {
        guard level != .debug || DeveloperDiagnostics.verboseDiagnosticsEnabled(for: subsystem) else { return }
        guard !verbose || DeveloperDiagnostics.verboseDiagnosticsEnabled(for: subsystem) else { return }
        let event = SubsystemDiagnosticEvent(
            subsystem: subsystem,
            level: level,
            name: name,
            reasonCode: reasonCode,
            noteBasename: noteBasename,
            vaultName: vaultName,
            durationMs: durationMs,
            counts: counts,
            generation: generation,
            revision: revision,
            metadata: metadata
        )
        Task(priority: .utility) {
            await SubsystemDiagnosticsStore.shared.record(event)
        }
    }

    public static func recordLegacy(
        level: DiagnosticsEventLevel,
        category: String,
        message: String
    ) {
        let subsystem = DiagnosticsSubsystem.inferred(from: category)
        record(
            level: level,
            subsystem: subsystem,
            name: "legacy.\(category)",
            reasonCode: reasonCode(from: message),
            metadata: [
                "category": category,
                "message": message
            ]
        )
    }

    public static func updateState(
        subsystem: DiagnosticsSubsystem,
        values: [String: String]
    ) {
        Task(priority: .utility) {
            await SubsystemDiagnosticsStore.shared.updateState(subsystem: subsystem, values: values)
        }
    }

    public static func snapshot() async -> SubsystemDiagnosticsSnapshot {
        await SubsystemDiagnosticsStore.shared.snapshot()
    }

    public static func resetForTesting() async {
        await SubsystemDiagnosticsStore.shared.reset()
    }

    private static func reasonCode(from message: String) -> String? {
        let lower = message.lowercased()
        if lower.contains("coordination timed out") || lower.contains("timed out") { return "save.coordinationTimeout" }
        if lower.contains("recovery copy") { return "save.recoveryCopyCreated" }
        if lower.contains("emergency primary write") { return "save.emergencyDirectWrite" }
        if lower.contains("snapshot") && lower.contains("created") { return "version.snapshotCreated" }
        if lower.contains("snapshot") && lower.contains("duplicate") { return "version.snapshotSkippedDuplicate" }
        if lower.contains("snapshot") && lower.contains("failed") { return "version.snapshotFailed" }
        if lower.contains("restore") && lower.contains("failed") { return "vault.restoreFailed" }
        if lower.contains("security-scoped access denied") { return "vault.securityScopeFailed" }
        if lower.contains("loadindex") && lower.contains("missing") { return "embedding.indexMissingDeferred" }
        if lower.contains("loadindex") && lower.contains("rejected") { return "embedding.indexRejectedMalformed" }
        if lower.contains("404") { return "ai.http404" }
        if lower.contains("backoff") { return "ai.backoff" }
        return nil
    }
}
