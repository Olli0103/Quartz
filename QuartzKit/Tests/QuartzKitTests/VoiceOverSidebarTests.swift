import Testing
import Foundation
@testable import QuartzKit

// MARK: - VoiceOver Sidebar Accessibility Tests

@Suite("VoiceOverSidebar")
struct VoiceOverSidebarTests {

    @Test("FileNode provides accessible name via name property")
    func fileNodeAccessibleName() {
        let noteNode = FileNode(
            name: "My Note.md",
            url: URL(fileURLWithPath: "/vault/My Note.md"),
            nodeType: .note
        )
        #expect(noteNode.name == "My Note.md")
        #expect(noteNode.isNote == true)
        #expect(noteNode.isFolder == false)

        let folderNode = FileNode(
            name: "Projects",
            url: URL(fileURLWithPath: "/vault/Projects"),
            nodeType: .folder,
            children: []
        )
        #expect(folderNode.name == "Projects")
        #expect(folderNode.isFolder == true)
    }

    @Test("CommandRegistry commands all have IDs, titles, and icons")
    @MainActor func commandRegistryCompleteness() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )
        #expect(commands.count >= 8) // 9+ commands depending on platform

        for cmd in commands {
            #expect(!cmd.id.isEmpty)
            #expect(!cmd.title.isEmpty)
            #expect(!cmd.icon.isEmpty)
        }

        // Check IDs are unique
        let ids = commands.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
