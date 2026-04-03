import Testing
import Foundation
@testable import QuartzKit

// MARK: - VoiceOver Editor Accessibility Tests

@Suite("VoiceOverEditor")
struct VoiceOverEditorTests {

    @Test("EditorSession exposes accessible state: wordCount, isDirty, cursor position")
    @MainActor func editorAccessibleState() {
        let session = EditorSession(
            vaultProvider: MockVaultProvider(),
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )

        // Empty session state
        #expect(session.wordCount == 0)
        #expect(session.isDirty == false)
        #expect(session.cursorPosition.location == 0)

        // currentText and isDirty are private(set) — verify read access works for VoiceOver
        #expect(session.currentText.isEmpty)
    }

    @Test("EditorFontFactory produces fonts for all families")
    func fontFactoryAllFamilies() {
        let families = AppearanceManager.EditorFontFamily.allCases
        #expect(families.count >= 4) // system, serif, monospaced, rounded

        for family in families {
            let font = EditorFontFactory.makeFont(family: family, size: 16)
            #expect(font.pointSize == 16)
        }

        // Code font is monospaced
        let codeFont = EditorFontFactory.makeCodeFont(size: 14)
        #expect(codeFont.pointSize == 14)
    }
}
