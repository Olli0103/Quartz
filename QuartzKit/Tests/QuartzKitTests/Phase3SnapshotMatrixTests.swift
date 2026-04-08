import XCTest
import SwiftUI
import Foundation
@testable import QuartzKit
import SnapshotTesting

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform snapshot diff tests for key Quartz views.
///
/// Uses `swift-snapshot-testing` to capture pixel-accurate snapshots and compare
/// against committed baselines in `__Snapshots__/`. First run records baselines
/// (mode `.missing`); subsequent runs compare against them.
///
/// **Platform-conditional baselines**: Each snapshot name includes a platform suffix
/// (e.g., `_macOS`, `_iOS`) so baselines are stored separately per platform.
/// This prevents cross-platform false positives from rendering differences.
///
/// **Platforms tested**: macOS (NSHostingView), iOS (UIHostingController).
/// Each test renders the view in a fixed frame to ensure deterministic output.
final class Phase3SnapshotMatrixTests: XCTestCase {

    // MARK: - Platform Suffix

    private var platformSuffix: String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "unknown"
        #endif
    }

    // MARK: - MarkdownPreviewView (Zero Dependencies)

    @MainActor
    func testMarkdownPreviewHeadingParagraph() {
        let view = MarkdownPreviewView(
            markdown: "# Welcome to Quartz\n\nA premium markdown notes app.\n\n## Features\n\n- Fast editing\n- Cross-platform\n- Accessible",
            fontScale: 1.0
        )
        .frame(width: 400, height: 300)

        assertViewSnapshot(view, named: "MarkdownPreview_HeadingParagraph_\(platformSuffix)")
    }

    @MainActor
    func testMarkdownPreviewTaskList() {
        let view = MarkdownPreviewView(
            markdown: "# Todo\n\n- [ ] First task\n- [x] Completed task\n- [ ] Third task\n\nSome notes below the list.",
            fontScale: 1.0
        )
        .frame(width: 400, height: 300)

        assertViewSnapshot(view, named: "MarkdownPreview_TaskList_\(platformSuffix)")
    }

    @MainActor
    func testMarkdownPreviewLargeFont() {
        let view = MarkdownPreviewView(
            markdown: "# Accessibility\n\nThis text should render at 1.5x scale for Dynamic Type testing.",
            fontScale: 1.5
        )
        .frame(width: 400, height: 300)

        assertViewSnapshot(view, named: "MarkdownPreview_LargeFont_\(platformSuffix)")
    }

    // MARK: - NoteListRow (Minimal Dependencies)

    @MainActor
    func testNoteListRowStandard() {
        let item = NoteListItem(
            url: URL(fileURLWithPath: "/tmp/Welcome.md"),
            title: "Welcome to Quartz",
            modifiedAt: Date(timeIntervalSince1970: 1712500000),
            fileSize: 1024,
            snippet: "A premium markdown notes app for Apple platforms. Built with SwiftUI and TextKit 2.",
            tags: ["readme", "getting-started"]
        )

        assertViewSnapshot(
            NoteListRow(item: item).frame(width: 320, height: 80),
            named: "NoteListRow_Standard_\(platformSuffix)"
        )
    }

    @MainActor
    func testNoteListRowFavorite() {
        let item = NoteListItem(
            url: URL(fileURLWithPath: "/tmp/ProjectA.md"),
            title: "Project A — Design Doc",
            modifiedAt: Date(timeIntervalSince1970: 1712500000),
            fileSize: 4096,
            snippet: "Architecture decisions and rationale for the new editor engine.",
            tags: ["project", "architecture", "phase-3"],
            isFavorite: true
        )

        assertViewSnapshot(
            NoteListRow(item: item).frame(width: 320, height: 80),
            named: "NoteListRow_Favorite_\(platformSuffix)"
        )
    }

    @MainActor
    func testNoteListRowLongTitle() {
        let item = NoteListItem(
            url: URL(fileURLWithPath: "/tmp/LongNote.md"),
            title: "This is a very long title that should be truncated in the display row",
            modifiedAt: Date(timeIntervalSince1970: 1712500000),
            fileSize: 512,
            snippet: "Short snippet.",
            tags: []
        )

        assertViewSnapshot(
            NoteListRow(item: item).frame(width: 320, height: 80),
            named: "NoteListRow_LongTitle_\(platformSuffix)"
        )
    }

    // MARK: - Dark Mode Variants

    @MainActor
    func testMarkdownPreviewDarkMode() {
        let view = MarkdownPreviewView(
            markdown: "# Dark Mode\n\nContent should be readable with light text on dark background.",
            fontScale: 1.0
        )
        .frame(width: 400, height: 200)
        .preferredColorScheme(.dark)

        assertViewSnapshot(view, named: "MarkdownPreview_DarkMode_\(platformSuffix)")
    }

    @MainActor
    func testNoteListRowDarkMode() {
        let item = NoteListItem(
            url: URL(fileURLWithPath: "/tmp/Dark.md"),
            title: "Dark Mode Note",
            modifiedAt: Date(timeIntervalSince1970: 1712500000),
            fileSize: 256,
            snippet: "Testing dark mode rendering for visual regression.",
            tags: ["theme"]
        )

        assertViewSnapshot(
            NoteListRow(item: item)
                .frame(width: 320, height: 80)
                .preferredColorScheme(.dark),
            named: "NoteListRow_DarkMode_\(platformSuffix)"
        )
    }

    // MARK: - Platform-Specific Width Variants

    @MainActor
    func testMarkdownPreviewCompactWidth() {
        let view = MarkdownPreviewView(
            markdown: "# iPhone View\n\nCompact width layout for phone-sized screens.\n\n- Item 1\n- Item 2",
            fontScale: 1.0
        )
        .frame(width: 320, height: 400)

        assertViewSnapshot(view, named: "MarkdownPreview_CompactWidth_\(platformSuffix)")
    }

    @MainActor
    func testMarkdownPreviewRegularWidth() {
        let view = MarkdownPreviewView(
            markdown: "# iPad View\n\nRegular width layout for tablet and desktop screens.\n\n| Column A | Column B |\n|---|---|\n| Data 1 | Data 2 |",
            fontScale: 1.0
        )
        .frame(width: 768, height: 400)

        assertViewSnapshot(view, named: "MarkdownPreview_RegularWidth_\(platformSuffix)")
    }

    // MARK: - Helpers

    /// Bridges a SwiftUI view to the platform's hosting controller and asserts a snapshot.
    @MainActor
    private func assertViewSnapshot<V: View>(
        _ view: V,
        named name: String,
        record: SnapshotTestingConfiguration.Record? = nil,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        #if canImport(UIKit)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = UIScreen.main.bounds
        controller.view.layoutIfNeeded()
        assertSnapshot(
            of: controller,
            as: .image,
            named: name,
            record: record,
            file: file,
            testName: testName,
            line: line
        )
        #elseif canImport(AppKit)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        hostingView.layoutSubtreeIfNeeded()
        assertSnapshot(
            of: hostingView,
            as: .image,
            named: name,
            record: record,
            file: file,
            testName: testName,
            line: line
        )
        #endif
    }
}
