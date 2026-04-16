import Foundation
import Testing
@testable import QuartzKit

@Suite("Editor product truthfulness")
@MainActor
struct EditorProductTruthfulnessTests {

    @Test("Custom command surface only exposes vault-wide note search")
    func searchCommandTruthfulness() {
        #expect(KeyboardShortcutCommands.exposesCustomInNoteFindCommand == false)
        #expect(KeyboardShortcutCommands.vaultSearchCommandTitle == "Search Notes…")
        #expect(SearchView.isVaultWideSearchSheet == true)
        #expect(SearchView.navigationTitleText == "Search Notes")
        #expect(SearchView.promptText == "Search all notes…")
    }

    @Test("Typewriter mode stays hidden until live editor behavior exists")
    func typewriterModeTruthfulness() {
        #expect(FocusModeManager.exposesTypewriterModeSetting == false)
        #expect(EditorSettingsView.showsTypewriterModeControl == false)
    }

    @Test("Markdown preview is not exposed as a live editor mode")
    func previewTruthfulness() {
        #expect(MarkdownPreviewView.isUserFacingEditorMode == false)
    }

    @Test("Share menu labels describe export and copy behavior honestly")
    func shareMenuTruthfulness() {
        #expect(ShareMenuView.toolbarAccessibilityLabelText == "Export note")
        #expect(ShareMenuView.toolbarHelpText == "Export or copy this note")
    }

    @Test("Toolbar hides shallow footnote affordance until a full user path exists")
    func footnoteSurfaceTruthfulness() {
        #expect(FormattingToolbar.exposesFootnoteAction == false)
        #expect(FormattingToolbar.primaryActions.contains(.footnote) == false)
        #expect(FormattingToolbar.secondaryActions.contains(.footnote) == false)
    }

    @Test("Inspector surfaces backlinks only when note context is real")
    func backlinksExposurePolicy() {
        let note = NoteDocument(fileURL: URL(fileURLWithPath: "/tmp/Note.md"))
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)

        #expect(
            InspectorSidebar.shouldShowBacklinksExperience(
                note: note,
                vaultRootURL: root,
                onNavigateToNote: { _ in }
            )
        )
        #expect(
            InspectorSidebar.shouldShowBacklinksExperience(
                note: nil,
                vaultRootURL: root,
                onNavigateToNote: { _ in }
            ) == false
        )
        #expect(
            InspectorSidebar.shouldShowBacklinksExperience(
                note: note,
                vaultRootURL: nil,
                onNavigateToNote: { _ in }
            ) == false
        )
    }

    @Test("Inspector backlink loader resolves real wiki backlinks")
    func backlinksLoaderTruthfulness() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(
            "QuartzBacklinks-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let provider = FileSystemVaultProvider(frontmatterParser: FrontmatterParser())
        let targetURL = root.appendingPathComponent("Target.md")
        let sourceURL = root.appendingPathComponent("Source.md")

        try await provider.saveNote(
            NoteDocument(
                fileURL: targetURL,
                frontmatter: Frontmatter(title: "Target"),
                body: "Target body"
            )
        )
        try await provider.saveNote(
            NoteDocument(
                fileURL: sourceURL,
                frontmatter: Frontmatter(title: "Source"),
                body: "See [[Target]] in this note."
            )
        )

        let target = try await provider.readNote(at: targetURL)
        let backlinks = try await InspectorSidebar.loadBacklinks(
            for: target,
            in: root,
            vaultProvider: provider
        )

        #expect(backlinks.count == 1)
        #expect(
            backlinks[0].sourceNoteURL.resolvingSymlinksInPath() ==
            sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        )
        #expect(backlinks[0].sourceNoteName == "Source")
        #expect(backlinks[0].context.contains("[[Target]]"))
    }
}
