import Foundation
import Testing
@testable import QuartzKit

@Suite("Diagnostics export")
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
    }
}
