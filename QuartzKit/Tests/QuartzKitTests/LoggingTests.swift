import Testing
import Foundation
import os
@testable import QuartzKit

// MARK: - QuartzLogger Tests

/// Verifies logger category instances, path redaction, and measure utility.

@Suite("QuartzLogger")
struct LoggingTests {

    @Test("All category loggers are accessible")
    func categoryLoggers() {
        // Verify each logger can be accessed without crashing
        _ = QuartzLogger.fileSystem
        _ = QuartzLogger.intelligence
        _ = QuartzLogger.uiPerformance
        _ = QuartzLogger.sync
        _ = QuartzLogger.security
        _ = QuartzLogger.editor
        _ = QuartzLogger.ai
        _ = QuartzLogger.navigation
    }

    @Test("Signpost logger is accessible")
    func signpostLogger() {
        _ = QuartzLogger.signpost
    }

    @Test("redactedPath returns filename only")
    func redactedPathFilenameOnly() {
        let url = URL(fileURLWithPath: "/Users/secret/Documents/vault/notes/daily.md")
        let result = QuartzLogger.redactedPath(url)
        #expect(result == "daily.md", "redactedPath should return only the filename, got: \(result)")
    }

    @Test("relativePath computes correct relative path")
    func relativePathCorrect() {
        let vaultRoot = URL(fileURLWithPath: "/Users/test/vault")
        let noteURL = URL(fileURLWithPath: "/Users/test/vault/notes/daily.md")
        let result = QuartzLogger.relativePath(noteURL, in: vaultRoot)
        #expect(result.contains("notes") && result.contains("daily.md"),
            "Should contain relative path components, got: \(result)")
    }

    @Test("relativePath falls back for non-child paths")
    func relativePathFallback() {
        let vaultRoot = URL(fileURLWithPath: "/Users/test/vault")
        let otherURL = URL(fileURLWithPath: "/tmp/other/file.md")
        let result = QuartzLogger.relativePath(otherURL, in: vaultRoot)
        // Should fall back to filename when path is outside vault
        #expect(result.contains("file.md"), "Should fall back to filename, got: \(result)")
    }

    @Test("measure completes and returns result")
    func measureCompletes() async {
        let result = await QuartzLogger.measure("test-operation", logger: QuartzLogger.editor) {
            return 42
        }
        #expect(result == 42, "measure should return the operation result")
    }
}
