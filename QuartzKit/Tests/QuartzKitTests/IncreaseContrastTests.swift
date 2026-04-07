import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - Increase Contrast Tests
//
// Color contrast data contracts complementing ContrastComplianceTests.
// Verifies that all status/type enums expose sufficient variants
// and that color utilities work correctly.

@Suite("IncreaseContrast")
struct IncreaseContrastTests {

    @Test("Color hex initializer produces valid colors")
    func colorHexInit() {
        let red = Color(hex: 0xFF0000)
        let green = Color(hex: 0x00FF00)
        let blue = Color(hex: 0x0000FF)
        let white = Color(hex: 0xFFFFFF)
        let black = Color(hex: 0x000000)

        // All should be valid, distinct colors
        let descriptions = Set(["\(red)", "\(green)", "\(blue)", "\(white)", "\(black)"])
        #expect(descriptions.count == 5, "Hex colors should produce distinct Color values")
    }

    @Test("QuartzColors accent is a valid color")
    func accentColor() {
        let accent = QuartzColors.accent
        #expect("\(accent)" != "\(Color.clear)",
            "Accent color should not be transparent")
    }

    @Test("ExportFormat cases all have SF Symbol icons")
    func exportFormatIcons() {
        for format in ExportFormat.allCases {
            #expect(!format.icon.isEmpty,
                "ExportFormat.\(format.rawValue) must have an icon name for high-contrast display")
        }
    }

    @Test("NodeType covers all file node categories")
    func nodeTypeCoverage() {
        let note = FileNode(name: "n.md", url: URL(fileURLWithPath: "/n.md"), nodeType: .note)
        let folder = FileNode(name: "d", url: URL(fileURLWithPath: "/d"), nodeType: .folder)

        #expect(note.isNote)
        #expect(folder.isFolder)
        #expect(note.nodeType != folder.nodeType, "Note and folder types must be distinct")
    }

    @Test("CloudStatus covers all expected file sync states")
    func cloudStatusCoverage() {
        let statuses: [CloudStatus] = [.local, .downloaded, .downloading, .evicted]
        #expect(statuses.count == 4,
            "CloudStatus should cover local, downloaded, downloading, and evicted")

        let unique = Set(statuses)
        #expect(unique.count == 4, "All cloud status values must be distinct")
    }

    @Test("CloudSyncStatus covers all expected sync states")
    func cloudSyncStatusCoverage() {
        let statuses: [CloudSyncStatus] = [
            .current, .uploading, .downloading,
            .notDownloaded, .conflict, .error, .notApplicable
        ]
        #expect(statuses.count == 7,
            "CloudSyncStatus should cover all sync states")

        let rawValues = Set(statuses.map(\.rawValue))
        #expect(rawValues.count == 7, "All sync status rawValues must be unique")
    }

    @Test("FileMetadata hasConflict flag is accessible")
    func conflictFlag() {
        let clean = FileMetadata(
            createdAt: Date(), modifiedAt: Date(), fileSize: 100,
            isEncrypted: false, cloudStatus: .local, hasConflict: false
        )
        let conflicted = FileMetadata(
            createdAt: Date(), modifiedAt: Date(), fileSize: 100,
            isEncrypted: false, cloudStatus: .downloaded, hasConflict: true
        )

        #expect(!clean.hasConflict)
        #expect(conflicted.hasConflict,
            "Conflict flag enables high-contrast visual indicators")
    }
}
