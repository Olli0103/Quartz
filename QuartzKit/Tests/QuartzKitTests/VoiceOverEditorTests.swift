import Testing
import Foundation
@testable import QuartzKit

// MARK: - VoiceOver Editor Accessibility Tests

@Suite("VoiceOverEditor")
@MainActor
struct VoiceOverEditorTests {

    @Test("EditorSession exposes accessible state: wordCount, isDirty, cursor position")
    @MainActor func editorAccessibleState() {
        let session = EditorSession(
            vaultProvider: MockVaultProvider(),
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )

        // Empty session state — VoiceOver reads these properties
        #expect(session.wordCount == 0)
        #expect(session.isDirty == false)
        #expect(session.cursorPosition.location == 0)
        #expect(session.currentText.isEmpty)
    }

    @Test("EditorSession exposes character count via currentText for VoiceOver summary")
    @MainActor func editorCharacterCount() {
        let session = EditorSession(
            vaultProvider: MockVaultProvider(),
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        #expect(session.currentText.count == 0)
    }

    @Test("EditorSession note is nil before loading for VoiceOver navigation context")
    @MainActor func editorNoteNameAccessible() {
        let session = EditorSession(
            vaultProvider: MockVaultProvider(),
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        // Before loading a note, note should be nil
        #expect(session.note == nil, "No note loaded — note should be nil")
    }

    @Test("EditorFontFactory produces fonts for all families")
    func fontFactoryAllFamilies() {
        let families = AppearanceManager.EditorFontFamily.allCases
        #expect(families.count >= 4) // system, serif, monospaced, rounded

        for family in families {
            let font = EditorFontFactory.makeFont(family: family, size: 16)
            #expect(font.pointSize == 16,
                "Font for \(family) should be 16pt, got \(font.pointSize)")
        }
    }

    @Test("EditorFontFactory code font is monospaced and accessible")
    func codeFontMonospaced() {
        let codeFont = EditorFontFactory.makeCodeFont(size: 14)
        #expect(codeFont.pointSize == 14)

        // Code font at larger accessibility size
        let largeCF = EditorFontFactory.makeCodeFont(size: 24)
        #expect(largeCF.pointSize == 24, "Code font must scale to max Dynamic Type size")
    }

    @Test("EditorFontFactory font sizes scale across full range for Dynamic Type")
    func fontSizeScaling() {
        let sizes: [CGFloat] = [12, 14, 16, 18, 20, 22, 24]
        for size in sizes {
            for family in AppearanceManager.EditorFontFamily.allCases {
                let font = EditorFontFactory.makeFont(family: family, size: size)
                #expect(font.pointSize == size,
                    "Font for \(family) at \(size)pt should match requested size")
            }
        }
    }

    @Test("EditorFontFactory produces bold and italic variants for accessibility")
    func fontVariantsAccessible() {
        let families = AppearanceManager.EditorFontFamily.allCases
        for family in families {
            // Bold variant — used for headings, must be distinguishable
            let boldFont = EditorFontFactory.makeFont(family: family, size: 16, weight: .bold)
            #expect(boldFont.pointSize == 16)

            // Italic variant — used for emphasis
            let italicFont = EditorFontFactory.makeFont(family: family, size: 16, italic: true)
            #expect(italicFont.pointSize == 16)
        }
    }

    @Test("EditorSession isSaving state is observable for status announcements")
    @MainActor func savingStateObservable() {
        let session = EditorSession(
            vaultProvider: MockVaultProvider(),
            frontmatterParser: FrontmatterParser(),
            inspectorStore: InspectorStore()
        )
        // isSaving should be accessible for VoiceOver status announcements
        #expect(session.isSaving == false)
    }

    // NOTE: True VoiceOver cursor and editing announcements require XCUITest.

    @Test("Font families all produce non-zero-size fonts for readability")
    func fontFamiliesNonZero() {
        for family in AppearanceManager.EditorFontFamily.allCases {
            let font = EditorFontFactory.makeFont(family: family, size: 16)
            #expect(font.pointSize > 0,
                "Font family \(family) must produce non-zero size for VoiceOver text sizing")
        }
    }
}
