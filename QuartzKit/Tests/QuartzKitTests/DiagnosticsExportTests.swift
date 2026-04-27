import Foundation
import Testing
@testable import QuartzKit

@Suite("Diagnostics export", .serialized)
struct DiagnosticsExportTests {
    @Test("Diagnostics store persists warning and error entries")
    func diagnosticsStorePersistsEntries() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quartz-diagnostics-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("diagnostics.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }

        let store = QuartzDiagnosticsStore(logURL: logURL, maximumLogBytes: 4_096)
        await store.record(level: .warning, category: "VaultAccessManager", message: "Bookmark refresh failed")
        await store.record(level: .error, category: "AppState", message: "User-facing error: Something broke")

        let text = await store.recentLogText()
        #expect(text.contains("[WARNING] [VaultAccessManager] Bookmark refresh failed"))
        #expect(text.contains("[ERROR] [AppState] User-facing error: Something broke"))
    }

    @Test("Diagnostic export includes recent log excerpt")
    func diagnosticExportIncludesRecentLog() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quartz-diagnostics-export-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("diagnostics.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }

        let store = QuartzDiagnosticsStore(logURL: logURL, maximumLogBytes: 4_096)
        await store.record(level: .fault, category: "CrashSentinel", message: "Crash sentinel triggered in Unit Test")

        let service = DiagnosticExportService(testingDiagnosticsStore: store)
        let report = await service.generateReport(context: "Unit Test", error: nil)
        let exported = await service.exportToText(report)

        #expect(exported.contains("Context: Unit Test"))
        #expect(exported.contains("RECENT DIAGNOSTICS LOG"))
        #expect(exported.contains("Crash sentinel triggered in Unit Test"))
        #expect(exported.contains("DEVELOPER DIAGNOSTICS MODE"))
        #expect(exported.contains("CROSS-SUBSYSTEM DIAGNOSTICS"))
        #expect(exported.contains("Knowledge Graph"))
        #expect(exported.contains("Dashboard / Home / Metrics"))
    }

    @Test("Developer diagnostics mode loads valid vault config")
    func developerDiagnosticsLoadsValidVaultConfig() async throws {
        DeveloperDiagnostics.resetForTesting()
        await SubsystemDiagnostics.resetForTesting()
        defer { DeveloperDiagnostics.resetForTesting() }

        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("quartz-dev-diagnostics-\(UUID().uuidString)", isDirectory: true)
        let quartz = vault.appendingPathComponent(".quartz", isDirectory: true)
        try FileManager.default.createDirectory(at: quartz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let config = """
        {
          "developerDiagnosticsEnabled": true,
          "rendererDiagnosticsEnabled": true,
          "verboseIndexingDiagnosticsEnabled": true,
          "verboseAIDiagnosticsEnabled": true,
          "verboseSaveDiagnosticsEnabled": true,
          "verboseGraphDiagnosticsEnabled": true,
          "verboseDashboardDiagnosticsEnabled": true,
          "includeDebugTimings": true
        }
        """
        try config.write(to: quartz.appendingPathComponent("developer-diagnostics.json"), atomically: true, encoding: .utf8)

        DeveloperDiagnostics.loadVaultConfiguration(from: vault)
        let status = DeveloperDiagnostics.status()

        #expect(status.enabled)
        #expect(status.source == ".quartz file")
        #expect(DeveloperDiagnostics.isRendererDiagnosticsEnabled)
        #expect(DeveloperDiagnostics.verboseDiagnosticsEnabled(for: .embeddings))
        #expect(status.supportedConfigFiles.contains(".quartz/developer-diagnostics.json"))
    }

    @Test("Developer diagnostics handles invalid JSON safely")
    func developerDiagnosticsHandlesInvalidJSONSafely() async throws {
        DeveloperDiagnostics.resetForTesting()
        await SubsystemDiagnostics.resetForTesting()
        defer { DeveloperDiagnostics.resetForTesting() }

        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("quartz-dev-diagnostics-invalid-\(UUID().uuidString)", isDirectory: true)
        let quartz = vault.appendingPathComponent(".quartz", isDirectory: true)
        try FileManager.default.createDirectory(at: quartz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        try "{ nope".write(to: quartz.appendingPathComponent("developer-diagnostics.json"), atomically: true, encoding: .utf8)

        DeveloperDiagnostics.loadVaultConfiguration(from: vault)
        try await Task.sleep(for: .milliseconds(50))
        let status = DeveloperDiagnostics.status()

        #expect(status.invalidConfigWarning?.contains("Invalid developer diagnostics config") == true)
    }

    @Test("Subsystem diagnostics ring buffer and repeated events are bounded")
    func subsystemDiagnosticsRingBufferAndRepeatedEventsAreBounded() async {
        let store = SubsystemDiagnosticsStore(capacity: 5)

        for _ in 0..<20 {
            await store.record(SubsystemDiagnosticEvent(
                subsystem: .save,
                level: .error,
                name: "saveFailed",
                reasonCode: "save.coordinationTimeout",
                noteBasename: "Note.md",
                metadata: ["error": "timeout"]
            ))
        }

        let snapshot = await store.snapshot()
        #expect(snapshot.recentEvents.count <= 5)
        #expect(snapshot.repeatedEventSummaries.contains { $0.name == "saveFailed.repeated" })
    }

    @Test("AI index health decodes legacy state and exports persisted backoff")
    func aiIndexHealthDecodesLegacyStateAndExportsBackoff() async throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("quartz-ai-health-\(UUID().uuidString)", isDirectory: true)
        let quartz = vault.appendingPathComponent(".quartz", isDirectory: true)
        try FileManager.default.createDirectory(at: quartz, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let legacy = #"{"processedTimestamps":{"a.md":"2026-04-27T10:00:00Z"},"conceptEdges":{}}"#
        try legacy.write(to: quartz.appendingPathComponent("ai_index.json"), atomically: true, encoding: .utf8)
        let legacySummary = KnowledgeExtractionService.persistedHealthSummary(vaultRootURL: vault)
        #expect(legacySummary["aiIndex.status"] == "idle")
        #expect(legacySummary["aiIndex.processedNotes"] == "1")

        var state = AIIndexState()
        state.lastStatus = "failedConfiguration"
        state.lastFailureReason = "ai.http404"
        state.backoffUntil = Date(timeIntervalSince1970: 1_777_777_777)
        state.processedTimestamps = ["a.md": Date(timeIntervalSince1970: 1_777_777_000)]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: quartz.appendingPathComponent("ai_index.json"), options: .atomic)

        let failedSummary = KnowledgeExtractionService.persistedHealthSummary(vaultRootURL: vault)
        #expect(failedSummary["aiIndex.status"] == "failedConfiguration")
        #expect(failedSummary["aiIndex.lastFailureReason"] == "ai.http404")
        #expect(failedSummary["aiIndex.backoffUntil"] != nil)
    }

    @Test("Diagnostic export includes renderer diagnostics section")
    func diagnosticExportIncludesRendererDiagnosticsSection() async throws {
        let rendererEvent = RendererDiagnosticEvent(
            name: "applyHighlightSpansFinish",
            noteBasename: "Note.md",
            metadata: [
                "durationMs": "7",
                "spanChecksum": "abc123",
                "textChecksum": "text123"
            ]
        )

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quartz-diagnostics-renderer-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("diagnostics.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }

        let store = QuartzDiagnosticsStore(logURL: logURL, maximumLogBytes: 4_096)
        let service = DiagnosticExportService(testingDiagnosticsStore: store)
        let report = diagnosticReport(
            context: "Renderer Unit Test",
            rendererDiagnostics: RendererDiagnosticsSnapshot(
                enabled: true,
                enablementHint: RendererDiagnostics.enablementHint,
                lastEvents: [rendererEvent],
                warningsAndErrors: [],
                lastRenderDurations: ["applyHighlightSpansFinish: 7 ms"],
                lastSpanChecksums: ["applyHighlightSpansFinish Note.md: abc123"],
                corruptionSignals: []
            )
        )
        let exported = await service.exportToText(report)

        #expect(exported.contains("RENDERER DIAGNOSTICS"))
        #expect(exported.contains("Status: enabled"))
        #expect(exported.contains("applyHighlightSpansFinish"))
        #expect(exported.contains("abc123"))
    }

    @Test("Diagnostic export explains renderer diagnostics when disabled")
    func diagnosticExportExplainsRendererDiagnosticsWhenDisabled() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quartz-diagnostics-renderer-disabled-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("diagnostics.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }

        let store = QuartzDiagnosticsStore(logURL: logURL, maximumLogBytes: 4_096)
        let service = DiagnosticExportService(testingDiagnosticsStore: store)
        let report = diagnosticReport(
            context: "Renderer Disabled Unit Test",
            rendererDiagnostics: RendererDiagnosticsSnapshot(
                enabled: false,
                enablementHint: RendererDiagnostics.enablementHint,
                lastEvents: [],
                warningsAndErrors: [],
                lastRenderDurations: [],
                lastSpanChecksums: [],
                corruptionSignals: []
            )
        )
        let exported = await service.exportToText(report)

        #expect(exported.contains("RENDERER DIAGNOSTICS"))
        #expect(exported.contains("Status: disabled"))
        #expect(exported.contains("Enable Settings > Editor > Advanced > Enable Renderer Diagnostics"))
    }

    @Test("Diagnostics export includes subsystem state and redacts paths and content")
    func diagnosticExportIncludesSubsystemStateAndRedactsSensitiveData() async throws {
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("quartz-diagnostics-subsystem-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("diagnostics.log")
        defer { try? FileManager.default.removeItem(at: logURL.deletingLastPathComponent()) }

        let store = QuartzDiagnosticsStore(logURL: logURL, maximumLogBytes: 4_096)
        await store.record(
            level: .error,
            category: "EditorSave",
            message: "save failed path=/Users/name/Vault/Secret.md content=\"Do not leak this note\""
        )

        let event = SubsystemDiagnosticEvent(
            subsystem: .graph,
            level: .warning,
            name: "graphCoverageCapped",
            reasonCode: "graph.coverageCapped",
            counts: ["displayedNoteNodes": 200, "totalVaultNotes": 900],
            metadata: [
                "path": "/Users/name/Vault/Secret.md",
                "body": "Do not leak this note"
            ]
        )
        let report = diagnosticReport(
            context: "Subsystem Unit Test",
            subsystemDiagnostics: SubsystemDiagnosticsSnapshot(
                recentEvents: [event],
                eventsBySubsystem: [.graph: [event]],
                warningsAndErrorsBySubsystem: [.graph: [event]],
                topSlowOperations: [],
                repeatedEventSummaries: [],
                currentState: [.graph: ["displayedNotes": "200", "totalNotes": "900"]]
            )
        )
        let exported = await DiagnosticExportService(testingDiagnosticsStore: store).exportToText(report)

        #expect(exported.contains("graph.coverageCapped"))
        #expect(exported.contains("displayedNoteNodes=200"))
        #expect(exported.contains("<path:Secret.md>"))
        #expect(!exported.contains("/Users/name/Vault/Secret.md"))
        #expect(!exported.contains("Do not leak this note"))
    }

    private func diagnosticReport(
        context: String,
        rendererDiagnostics: RendererDiagnosticsSnapshot = RendererDiagnosticsSnapshot(
            enabled: false,
            enablementHint: RendererDiagnostics.enablementHint,
            lastEvents: [],
            warningsAndErrors: [],
            lastRenderDurations: [],
            lastSpanChecksums: [],
            corruptionSignals: []
        ),
        subsystemDiagnostics: SubsystemDiagnosticsSnapshot = SubsystemDiagnosticsSnapshot(
            recentEvents: [],
            eventsBySubsystem: [:],
            warningsAndErrorsBySubsystem: [:],
            topSlowOperations: [],
            repeatedEventSummaries: [],
            currentState: [:]
        )
    ) -> DiagnosticReport {
        DiagnosticReport(
            id: UUID(),
            timestamp: Date(),
            context: context,
            errorDescription: nil,
            errorType: nil,
            deviceInfo: DeviceInfo(model: "Mac", osVersion: "Test", thermalState: "nominal"),
            appInfo: AppInfo(version: "Test", build: "Test", bundleID: "QuartzKitTests"),
            memoryInfo: MemoryInfo(usedMB: 1, availableMB: 2, pressureLevel: "nominal"),
            developerDiagnostics: DeveloperDiagnosticsStatus(
                enabled: false,
                source: "disabled",
                supportedConfigFiles: DeveloperDiagnostics.configFileNames.map { ".quartz/\($0)" },
                supportedKeys: DeveloperDiagnostics.supportedKeys,
                flags: [:]
            ),
            subsystemDiagnostics: subsystemDiagnostics,
            rendererDiagnostics: rendererDiagnostics,
            recentDiagnosticsLog: "No diagnostics captured yet.",
            additionalInfo: [:]
        )
    }
}
