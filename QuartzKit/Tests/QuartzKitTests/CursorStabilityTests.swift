import Testing
import Foundation
@testable import QuartzKit

// MARK: - Cursor Stability Tests

/// Verifies that cursor position tracking remains consistent through
/// delegate callbacks. The native text view is the source of truth;
/// EditorSession just mirrors the reported position.

@Suite("Cursor Stability")
struct CursorStabilityTests {

    @Test("Cursor position defaults to zero")
    @MainActor func cursorDefaultsToZero() {
        let session = EditorSession(vaultProvider: AdvancedMockVaultProvider(), frontmatterParser: FrontmatterParser(), inspectorStore: InspectorStore())
        #expect(session.cursorPosition == NSRange(location: 0, length: 0))
    }

    @Test("selectionDidChange updates cursor position")
    @MainActor func selectionDidChangeUpdatesCursor() {
        let session = EditorSession(vaultProvider: AdvancedMockVaultProvider(), frontmatterParser: FrontmatterParser(), inspectorStore: InspectorStore())
        let newRange = NSRange(location: 42, length: 10)
        session.selectionDidChange(newRange)
        #expect(session.cursorPosition == newRange)
    }

    @Test("Rapid selectionDidChange calls maintain consistency")
    @MainActor func rapidSelectionChanges() {
        let session = EditorSession(vaultProvider: AdvancedMockVaultProvider(), frontmatterParser: FrontmatterParser(), inspectorStore: InspectorStore())

        // Simulate rapid cursor movements (arrow keys held down)
        for i in 0..<100 {
            session.selectionDidChange(NSRange(location: i, length: 0))
        }
        #expect(session.cursorPosition == NSRange(location: 99, length: 0),
            "Last selection change should win")
    }
}
