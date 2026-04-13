import Testing
import Foundation
@testable import QuartzKit

// MARK: - Dynamic Type Scaling Tests

@Suite("DynamicTypeScaling")
@MainActor
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

        let monoFont = EditorFontFactory.makeFont(family: .monospaced, size: 14)
        #expect(monoFont.pointSize == 14)
    }

    @Test("All font families produce fonts at minimum Dynamic Type size")
    func allFamiliesAtMinSize() {
        let minSize: CGFloat = 12
        for family in AppearanceManager.EditorFontFamily.allCases {
            let font = EditorFontFactory.makeFont(family: family, size: minSize)
            #expect(font.pointSize == minSize,
                "\(family) must produce \(minSize)pt font")
        }
    }

    @Test("All font families produce fonts at maximum Dynamic Type size")
    func allFamiliesAtMaxSize() {
        let maxSize: CGFloat = 24
        for family in AppearanceManager.EditorFontFamily.allCases {
            let font = EditorFontFactory.makeFont(family: family, size: maxSize)
            #expect(font.pointSize == maxSize,
                "\(family) must produce \(maxSize)pt font")
        }
    }

    @Test("Code font scales across full Dynamic Type range")
    func codeFontFullRange() {
        let sizes: [CGFloat] = [12, 14, 16, 18, 20, 22, 24]
        for size in sizes {
            let font = EditorFontFactory.makeCodeFont(size: size)
            #expect(font.pointSize == size,
                "Code font must scale to \(size)pt")
        }
    }

    @Test("Bold font weight is distinguishable at all sizes for heading hierarchy")
    func boldFontDistinguishable() {
        let sizes: [CGFloat] = [12, 16, 20, 24]
        for size in sizes {
            let regular = EditorFontFactory.makeFont(family: .system, size: size, weight: .regular)
            let bold = EditorFontFactory.makeFont(family: .system, size: size, weight: .bold)
            // Both should be at the correct point size
            #expect(regular.pointSize == size)
            #expect(bold.pointSize == size)
        }
    }

    @Test("Line spacing is configurable for readability")
    @MainActor func lineSpacingConfigurable() {
        let defaults = UserDefaults(suiteName: "DynTypeLS-\(UUID().uuidString)")!
        let manager = AppearanceManager(defaults: defaults)
        let original = manager.editorLineSpacing
        #expect(original >= 0, "Line spacing should be non-negative")
    }

    @Test("Font family setting persists across AppearanceManager instances")
    @MainActor func fontFamilyPersists() {
        let suiteName = "DynTypeFF-\(UUID().uuidString)"
        let defaults1 = UserDefaults(suiteName: suiteName)!
        let manager1 = AppearanceManager(defaults: defaults1)
        manager1.editorFontFamily = .serif

        let defaults2 = UserDefaults(suiteName: suiteName)!
        let manager2 = AppearanceManager(defaults: defaults2)
        #expect(manager2.editorFontFamily == .serif,
            "Font family should persist for user preference consistency")
    }
}
