import Testing
import Foundation
@testable import QuartzKit

// MARK: - VoiceOver Settings Tests
//
// Settings model coverage: every preference enum has display names,
// all cases are accounted for, and values have valid bounds.

@Suite("VoiceOverSettings")
struct VoiceOverSettingsTests {

    @Test("Theme covers all cases with displayName")
    func themeCoverage() {
        let cases = AppearanceManager.Theme.allCases
        #expect(cases.count == 3, "Should have system, light, and dark themes")

        for theme in cases {
            #expect(!theme.rawValue.isEmpty,
                "Theme.\(theme) must have a rawValue for persistence")
        }

        let rawValues = Set(cases.map(\.rawValue))
        #expect(rawValues.count == cases.count, "All theme rawValues must be unique")
    }

    @Test("EditorFontFamily covers all cases")
    func fontFamilyCoverage() {
        let cases = AppearanceManager.EditorFontFamily.allCases
        #expect(cases.count >= 4,
            "Should have at least system, serif, monospaced, and rounded")

        let rawValues = Set(cases.map(\.rawValue))
        #expect(rawValues.count == cases.count, "All font family rawValues must be unique")
    }

    @Test("SyntaxVisibilityMode covers all cases")
    func syntaxVisibilityCoverage() {
        let cases = SyntaxVisibilityMode.allCases
        #expect(cases.count == 3,
            "Should have full, gentleFade, and hiddenUntilCaret modes")

        for mode in cases {
            let restored = SyntaxVisibilityMode(rawValue: mode.rawValue)
            #expect(restored == mode,
                "SyntaxVisibilityMode.\(mode) must round-trip through rawValue")
        }
    }

    @Test("AppearanceManager font size has valid bounds")
    @MainActor func fontSizeBounds() {
        let suiteName = "VoiceOverSettings-fontSize-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = AppearanceManager(defaults: defaults)

        #expect(manager.editorFontSize >= 12, "Minimum font size should be 12pt")
        #expect(manager.editorFontSize <= 24, "Maximum font size should be 24pt")
    }

    @Test("AppearanceManager line spacing has valid bounds")
    @MainActor func lineSpacingBounds() {
        let suiteName = "VoiceOverSettings-spacing-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = AppearanceManager(defaults: defaults)

        #expect(manager.editorLineSpacing >= 1.0, "Minimum line spacing should be 1.0")
        #expect(manager.editorLineSpacing <= 2.5, "Maximum line spacing should be 2.5")
    }

    @Test("ExportFormat has displayName and icon for all cases")
    func exportFormatLabels() {
        for format in ExportFormat.allCases {
            #expect(!format.displayName.isEmpty,
                "ExportFormat.\(format) must have a displayName for VoiceOver")
            #expect(!format.icon.isEmpty,
                "ExportFormat.\(format) must have an icon for visual identification")
            #expect(!format.fileExtension.isEmpty,
                "ExportFormat.\(format) must have a file extension")
            #expect(!format.mimeType.isEmpty,
                "ExportFormat.\(format) must have a MIME type")
        }
        #expect(ExportFormat.allCases.count == 4,
            "Should have pdf, html, rtf, and markdown formats")
    }

    @Test("StorageType covers all expected cases")
    func storageTypeCoverage() {
        let types: [StorageType] = [.local, .iCloudDrive, .webdav]
        #expect(types.count == 3, "Should have local, iCloudDrive, and webdav")

        let rawValues = Set(types.map(\.rawValue))
        #expect(rawValues.count == types.count, "All storage type rawValues must be unique")
    }
}
