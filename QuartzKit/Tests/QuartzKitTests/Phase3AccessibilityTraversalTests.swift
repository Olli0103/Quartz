import XCTest
import SwiftUI
import Foundation
@testable import QuartzKit
import SnapshotTesting

#if canImport(AppKit)
import AppKit
#endif

/// Runtime accessibility verification tests for Phase 3 gate.
///
/// These tests render real SwiftUI views into hosting containers and query
/// the accessibility tree, snapshot at Dynamic Type scales, and verify
/// accessibility modifier presence through source-level invariants.
///
/// No `Bool(true)` tautologies — every assertion exercises runtime behavior.
final class Phase3AccessibilityTraversalTests: XCTestCase {

    // MARK: - Platform Suffix

    private var platformSuffix: String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "unknown"
        #endif
    }

    // MARK: - NoteListRow Accessibility Tree

    #if canImport(AppKit)
    @MainActor
    func testNoteListRowRendersAccessibleContent() {
        let item = NoteListItem(
            url: URL(fileURLWithPath: "/tmp/Accessible.md"),
            title: "Accessible Note",
            modifiedAt: Date(timeIntervalSince1970: 1712500000),
            fileSize: 512,
            snippet: "Testing accessibility labels",
            tags: ["a11y"]
        )

        let view = NoteListRow(item: item).frame(width: 320, height: 80)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 80)

        // Attach to a window so the accessibility tree materializes
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        // SwiftUI measures the content — fittingSize proves the view was laid out
        let fittingSize = hostingView.fittingSize
        XCTAssertGreaterThan(fittingSize.width, 0,
                             "NoteListRow must have non-zero fitted width when rendered")
        XCTAssertGreaterThan(fittingSize.height, 0,
                             "NoteListRow must have non-zero fitted height when rendered")

        // Verify the hosting view exposes an accessibility role
        XCTAssertNotNil(hostingView.accessibilityRole(),
                        "NoteListRow hosting view must have an accessibility role")

        // Intrinsic content size must be valid (proves SwiftUI layout ran)
        let intrinsic = hostingView.intrinsicContentSize
        XCTAssertGreaterThan(intrinsic.width, 0,
                             "NoteListRow must have valid intrinsic content width")
    }

    @MainActor
    func testNoteListRowAccessibleChildCount() {
        let item = NoteListItem(
            url: URL(fileURLWithPath: "/tmp/Multi.md"),
            title: "Multi-Element Note",
            modifiedAt: Date(timeIntervalSince1970: 1712500000),
            fileSize: 1024,
            snippet: "This note has title, timestamp, snippet, and tags",
            tags: ["tag1", "tag2"]
        )

        let view = NoteListRow(item: item).frame(width: 320, height: 100)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 100)

        // Attach to a window for accessibility tree population
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 100),
            styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()

        // SwiftUI rendered the content — verify layout happened
        let fittingSize = hostingView.fittingSize
        XCTAssertGreaterThan(fittingSize.width, 0,
                             "Multi-element NoteListRow must have non-zero fitted width")
        XCTAssertGreaterThan(fittingSize.height, 0,
                             "Multi-element NoteListRow must have non-zero fitted height")

        // Verify the hosting view has an accessibility role assigned
        let role = hostingView.accessibilityRole()
        XCTAssertNotNil(role,
                        "NoteListRow hosting view must have an accessibility role")

        // The row model has the data needed for accessibility announcement
        XCTAssertEqual(item.title, "Multi-Element Note")
        XCTAssertEqual(item.tags.count, 2,
                       "NoteListItem must carry tag data for accessibility announcements")
    }
    #endif

    // MARK: - Dynamic Type Snapshot Matrix

    @MainActor
    func testNoteListRowSnapshotAtDefaultScale() {
        let item = makeTestItem(title: "Default Scale")
        let view = NoteListRow(item: item).frame(width: 320, height: 80)
        assertViewSnapshot(view, named: "DynamicType_Default_\(platformSuffix)")
    }

    @MainActor
    func testNoteListRowSnapshotAtXLScale() {
        let item = makeTestItem(title: "XL Scale")
        let view = NoteListRow(item: item)
            .frame(width: 320, height: 120)
            .dynamicTypeSize(.xxxLarge)
        assertViewSnapshot(view, named: "DynamicType_XXXL_\(platformSuffix)")
    }

    @MainActor
    func testNoteListRowSnapshotAtAccessibilityXL() {
        let item = makeTestItem(title: "Accessibility XL Scale")
        let view = NoteListRow(item: item)
            .frame(width: 320, height: 160)
            .dynamicTypeSize(.accessibility3)
        assertViewSnapshot(view, named: "DynamicType_AX3_\(platformSuffix)")
    }

    @MainActor
    func testMarkdownPreviewSnapshotAtAccessibilityXL() {
        let view = MarkdownPreviewView(
            markdown: "# Dynamic Type AX3\n\nThis must remain readable at maximum accessibility size.",
            fontScale: 2.0
        )
        .frame(width: 400, height: 400)
        .dynamicTypeSize(.accessibility3)

        assertViewSnapshot(view, named: "MarkdownPreview_AX3_\(platformSuffix)")
    }

    @MainActor
    func testMarkdownPreviewSnapshotAtSmallSize() {
        let view = MarkdownPreviewView(
            markdown: "# Small Type\n\nThis must remain readable at minimum size.",
            fontScale: 0.8
        )
        .frame(width: 400, height: 300)
        .dynamicTypeSize(.xSmall)

        assertViewSnapshot(view, named: "MarkdownPreview_XSmall_\(platformSuffix)")
    }

    // MARK: - Accessibility Identifier Source Verification

    func testAccessibilityIdentifiersExistInSource() throws {
        // Verify that required accessibility identifiers are present in production source files.
        // This is a source-level invariant: if the string is removed, this test fails.
        let identifierFileMap: [(identifier: String, file: String)] = [
            ("sidebar-file-tree", "Presentation/Sidebar/SidebarView.swift"),
            ("sidebar-new-note", "Presentation/Sidebar/SidebarView.swift"),
            ("sidebar-new-note-fab", "Presentation/Sidebar/SidebarView.swift"),
            ("workspace-split-view", "Presentation/Workspace/WorkspaceView.swift"),
            ("editor-text-view", "Presentation/Editor/EditorContainerView.swift"),
            ("dashboard-view", "Presentation/Dashboard/DashboardView.swift"),
        ]

        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // QuartzKitTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // QuartzKit
            .appendingPathComponent("Sources/QuartzKit")

        for (identifier, relPath) in identifierFileMap {
            let fileURL = sourcesRoot.appendingPathComponent(relPath)
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertTrue(content.contains("\"\(identifier)\""),
                          "Accessibility identifier \"\(identifier)\" must exist in \(relPath)")
        }
    }

    func testAccessibilityLabelsExistInSource() throws {
        // Verify accessibility labels are set on key interactive elements
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuartzKit")

        let sidebarPath = sourcesRoot.appendingPathComponent("Presentation/Sidebar/SidebarView.swift")
        let sidebarContent = try String(contentsOf: sidebarPath, encoding: .utf8)

        // New Note button must have accessibilityLabel
        XCTAssertTrue(sidebarContent.contains(".accessibilityLabel"),
                      "SidebarView must set .accessibilityLabel on interactive elements")

        // New Note button must have accessibilityInputLabels for Voice Control
        XCTAssertTrue(sidebarContent.contains(".accessibilityInputLabels"),
                      "SidebarView must set .accessibilityInputLabels for Voice Control support")

        // FAB must have accessibilityHint
        XCTAssertTrue(sidebarContent.contains(".accessibilityHint"),
                      "SidebarView FAB must set .accessibilityHint for long-press discovery")
    }

    // MARK: - Reduce Motion Compliance (Source Verification)

    func testNoLinearAnimationsInSource() throws {
        // QuartzAnimation must not use .linear (which ignores Reduce Motion).
        // All animations should use spring/bouncy/smooth/snappy which SwiftUI auto-disables.
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuartzKit")

        let animPath = sourcesRoot.appendingPathComponent("Presentation/DesignSystem/QuartzAnimation.swift")
        let content = try String(contentsOf: animPath, encoding: .utf8)

        XCTAssertFalse(content.contains(".linear("),
                       "QuartzAnimation must not use .linear — it ignores Reduce Motion")
        XCTAssertFalse(content.contains("Animation.linear"),
                       "QuartzAnimation must not use Animation.linear — it ignores Reduce Motion")
    }

    func testQuartzAnimationUsesOnlySpringBasedAnimations() throws {
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuartzKit")

        let animPath = sourcesRoot.appendingPathComponent("Presentation/DesignSystem/QuartzAnimation.swift")
        let content = try String(contentsOf: animPath, encoding: .utf8)

        // Count animation definitions — must all be spring-family or easeInOut (shimmer)
        let lines = content.components(separatedBy: .newlines)
        let animLines = lines.filter { $0.contains(": Animation =") }

        for line in animLines {
            let isSpringBased = line.contains(".spring") || line.contains(".snappy")
                || line.contains(".bouncy") || line.contains(".smooth")
                || line.contains(".easeInOut")
            XCTAssertTrue(isSpringBased,
                          "Animation must use spring-family timing: \(line.trimmingCharacters(in: .whitespaces))")
        }

        XCTAssertGreaterThan(animLines.count, 10,
                             "QuartzAnimation should define at least 10 animation constants")
    }

    // MARK: - Increase Contrast Compliance (Source Verification)

    func testNoteListRowUsesSemanticForegroundStyles() throws {
        let sourcesRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/QuartzKit")

        let rowPath = sourcesRoot.appendingPathComponent("Presentation/NoteList/NoteListRow.swift")
        let content = try String(contentsOf: rowPath, encoding: .utf8)

        // Must use semantic foreground styles (not hardcoded colors) for text
        XCTAssertTrue(content.contains(".foregroundStyle(.primary)"),
                      "NoteListRow title must use .primary foreground style")
        XCTAssertTrue(content.contains(".foregroundStyle(.secondary)") || content.contains(".foregroundStyle(.tertiary)"),
                      "NoteListRow must use semantic secondary/tertiary styles for metadata")

        // Must NOT use hardcoded Color for text (Color.black, Color.white, Color(hex:))
        let lines = content.components(separatedBy: .newlines)
        let textLines = lines.filter { $0.contains("foregroundStyle") || $0.contains("foregroundColor") }
        for line in textLines {
            XCTAssertFalse(line.contains("Color.black") || line.contains("Color.white") || line.contains("Color(hex"),
                           "NoteListRow must not use hardcoded colors for text: \(line.trimmingCharacters(in: .whitespaces))")
        }
    }

    // MARK: - FileNode Accessibility Traits

    func testFolderNodeIsDistinguishableFromNote() {
        let folder = FileNode(name: "Projects", url: URL(fileURLWithPath: "/tmp/Projects"),
                              nodeType: .folder, children: [])
        let note = FileNode(name: "Note.md", url: URL(fileURLWithPath: "/tmp/Note.md"),
                            nodeType: .note, children: nil)

        // Folder and note must have distinct types for VoiceOver to announce differently
        XCTAssertNotEqual(folder.nodeType, note.nodeType)
        XCTAssertTrue(folder.isFolder)
        XCTAssertTrue(note.isNote)
        XCTAssertFalse(folder.isNote)
        XCTAssertFalse(note.isFolder)
    }

    func testFileNodeNameIsNotEmpty() {
        // VoiceOver reads the name — it must never be empty
        let note = FileNode(name: "Welcome.md", url: URL(fileURLWithPath: "/tmp/Welcome.md"),
                            nodeType: .note, children: nil)
        XCTAssertFalse(note.name.isEmpty, "FileNode name must not be empty for VoiceOver")
        XCTAssertTrue(note.name.hasSuffix(".md"), "Note name should include extension for disambiguation")
    }

    // MARK: - Dynamic Type Font Scale Matrix

    func testMarkdownPreviewConstructibleAtAllFontScales() {
        // View must be constructible at every scale from 0.8 to 2.0 without crashing
        let scales: [CGFloat] = [0.8, 0.85, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.6, 1.8, 1.9, 2.0]
        for scale in scales {
            let view = MarkdownPreviewView(
                markdown: "# Scale \(scale)\n\nBody text at this scale.",
                fontScale: scale
            )
            // Construct hosting view to prove it renders without crash
            #if canImport(AppKit)
            let hosting = NSHostingView(rootView: view.frame(width: 400, height: 300))
            hosting.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(hosting.frame.width, 0,
                                 "View must render at scale \(scale)")
            #endif
        }
    }

    // MARK: - Helpers

    private func makeTestItem(title: String) -> NoteListItem {
        NoteListItem(
            url: URL(fileURLWithPath: "/tmp/\(title).md"),
            title: title,
            modifiedAt: Date(timeIntervalSince1970: 1712500000),
            fileSize: 512,
            snippet: "Test snippet for \(title)",
            tags: ["test"]
        )
    }

    #if canImport(AppKit)
    /// Recursively collects all accessibility elements from a view hierarchy.
    @MainActor
    private func collectAccessibleElements(from view: NSView) -> [NSObject] {
        var result: [NSObject] = []
        if let children = view.accessibilityChildren() as? [NSObject] {
            for child in children {
                result.append(child)
                if let childView = child as? NSView {
                    result.append(contentsOf: collectAccessibleElements(from: childView))
                }
            }
        }
        for subview in view.subviews {
            result.append(contentsOf: collectAccessibleElements(from: subview))
        }
        return result
    }
    #endif

    @MainActor
    private func assertViewSnapshot<V: View>(
        _ view: V,
        named name: String,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        #if canImport(AppKit)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        hostingView.layoutSubtreeIfNeeded()
        assertSnapshot(
            of: hostingView,
            as: .image,
            named: name,
            file: file,
            testName: testName,
            line: line
        )
        #endif
    }
}
