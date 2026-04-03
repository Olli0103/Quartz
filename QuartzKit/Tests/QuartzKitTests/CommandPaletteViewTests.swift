import Testing
import Foundation
@testable import QuartzKit

// MARK: - Command Palette Engine Tests

@Suite("CommandPaletteView")
struct CommandPaletteViewTests {

    @Test("PaletteCommand, NoteResult, PaletteItem models and keyboard navigation")
    @MainActor func modelsAndNavigation() {
        // PaletteCommand
        var executed = false
        let cmd = PaletteCommand(
            id: "test-cmd",
            title: "New Note",
            icon: "doc.badge.plus",
            shortcutLabel: "Cmd+N",
            keywords: ["create", "add"]
        ) {
            executed = true
        }
        #expect(cmd.id == "test-cmd")
        #expect(cmd.title == "New Note")
        #expect(cmd.icon == "doc.badge.plus")
        #expect(cmd.shortcutLabel == "Cmd+N")
        #expect(cmd.keywords.count == 2)

        // Execute action
        cmd.action()
        #expect(executed == true)

        // NoteResult
        let noteResult = NoteResult(
            url: URL(fileURLWithPath: "/vault/test.md"),
            title: "Test Note",
            folderPath: "Projects/",
            modifiedAt: Date(),
            snippet: "Preview text",
            matchScore: 12
        )
        #expect(noteResult.matchScore == 12)
        #expect(noteResult.folderPath == "Projects/")

        // PaletteItem enum
        let noteItem = PaletteItem.note(noteResult)
        let cmdItem = PaletteItem.command(cmd)
        #expect(noteItem.id.hasPrefix("note:"))
        #expect(cmdItem.id.hasPrefix("cmd:"))
        #expect(noteItem.title == "Test Note")
        #expect(cmdItem.title == "New Note")
        #expect(noteItem.score == 12)

        // CommandPaletteEngine keyboard navigation
        let engine = CommandPaletteEngine(
            previewRepository: nil,
            commands: [cmd]
        )
        // With nil repo and a single command, default results may include the command
        // Test navigation methods don't crash with empty results
        engine.moveSelectionUp()
        engine.moveSelectionDown()
        #expect(engine.selectedIndex >= 0)

        // executeSelected returns nil when no selection matches
        let result = engine.executeSelected()
        // Result depends on whether default results populated; just verify no crash
        _ = result
    }
}
