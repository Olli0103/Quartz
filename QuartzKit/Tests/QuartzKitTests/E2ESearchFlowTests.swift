import Testing
import Foundation
@testable import QuartzKit

// MARK: - E2E Search Flow Tests

@Suite("E2ESearchFlow")
struct E2ESearchFlowTests {

    @Test("CommandPaletteEngine initializes with commands and empty search")
    @MainActor func engineInitialization() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )
        let engine = CommandPaletteEngine(
            previewRepository: nil,
            commands: commands
        )

        #expect(engine.searchText.isEmpty)
        #expect(engine.selectedIndex == 0)
    }

    @Test("PaletteCommand keywords exist for fuzzy matching")
    @MainActor func paletteCommandKeywords() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )

        // Find a specific well-known command
        let newNote = commands.first { $0.id.contains("new") || $0.title.contains("New") }
        #expect(newNote != nil)
        if let cmd = newNote {
            #expect(!cmd.keywords.isEmpty)
            #expect(!cmd.icon.isEmpty)
        }
    }
}
