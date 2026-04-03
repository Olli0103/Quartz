import Testing
import Foundation
@testable import QuartzKit

// MARK: - Scene Storage / Editor State Restoration Tests

@Suite("SceneStorage")
struct SceneStorageTests {

    @MainActor private func makeSession() -> EditorSession {
        let provider = MockVaultProvider()
        let parser = FrontmatterParser()
        let inspectorStore = InspectorStore()
        return EditorSession(
            vaultProvider: provider,
            frontmatterParser: parser,
            inspectorStore: inspectorStore
        )
    }

    @Test("restoreCursor clamps out-of-range values, restoreScroll updates offset")
    @MainActor func cursorAndScrollRestoration() {
        let session = makeSession()
        // Empty session — currentText.count == 0

        // Cursor beyond text length — should clamp to 0
        session.restoreCursor(location: 999, length: 10)
        #expect(session.cursorPosition.location == 0)
        #expect(session.cursorPosition.length == 0)

        // Zero cursor works
        session.restoreCursor(location: 0)
        #expect(session.cursorPosition.location == 0)
        #expect(session.cursorPosition.length == 0)

        // Restore scroll offset
        session.restoreScroll(y: 42.5)
        #expect(session.scrollOffset.y == 42.5)

        // Scroll with zero
        session.restoreScroll(y: 0)
        #expect(session.scrollOffset.y == 0)
    }

    @Test("awaitReadiness resolves immediately when already ready, signalReadyForRestoration is idempotent")
    @MainActor func readinessHandshake() async {
        let session = makeSession()

        // Signal ready
        session.signalReadyForRestoration()
        #expect(session.isReadyForRestoration == true)

        // awaitReadiness returns immediately when already ready
        await session.awaitReadiness()
        #expect(session.isReadyForRestoration == true)

        // Signaling again is idempotent (no crash)
        session.signalReadyForRestoration()
        #expect(session.isReadyForRestoration == true)
    }
}
