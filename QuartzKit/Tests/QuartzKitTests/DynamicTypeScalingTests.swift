import Testing
import Foundation
@testable import QuartzKit

// MARK: - Dynamic Type Scaling Tests

@Suite("DynamicTypeScaling")
struct DynamicTypeScalingTests {

    @Test("AppearanceManager font size range is 12-24")
    @MainActor func fontSizeRange() {
        let defaults = UserDefaults(suiteName: "DynamicTypeTest-\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)

        // Default size should be within range
        #expect(manager.editorFontSize >= 12)
        #expect(manager.editorFontSize <= 24)

        // Can set to bounds
        manager.editorFontSize = 12
        #expect(manager.editorFontSize == 12)

        manager.editorFontSize = 24
        #expect(manager.editorFontSize == 24)
    }

    @Test("EditorFontFactory code font is monospaced")
    func codeFontIsMonospaced() {
        let codeFont = EditorFontFactory.makeCodeFont(size: 16)
        #expect(codeFont.pointSize == 16)

        // The monospaced font family variant should also produce a font
        let monoFont = EditorFontFactory.makeFont(family: .monospaced, size: 14)
        #expect(monoFont.pointSize == 14)
    }
}
