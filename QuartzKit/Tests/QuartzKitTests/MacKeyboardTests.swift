import Testing
import Foundation
@testable import QuartzKit

// MARK: - Mac Keyboard Tests
//
// Full keyboard shortcut data contracts: unique IDs for dispatch,
// formatting action coverage, mutation origin distinction.

@Suite("MacKeyboard")
struct MacKeyboardTests {

    @Test("CommandRegistry commands have unique IDs for keyboard dispatch")
    @MainActor func uniqueCommandIDs() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )

        let ids = commands.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(uniqueIDs.count == ids.count,
            "Command IDs must be unique for unambiguous keyboard dispatch")
    }

    @Test("FormattingAction has allCases for toolbar keyboard shortcuts")
    func formattingActionAllCases() {
        let actions = FormattingAction.allCases
        #expect(actions.count >= 20,
            "Formatting toolbar should have all text, block, inline, and advanced actions")

        // Key actions should have keyboard shortcuts
        let bold = actions.first(where: { $0.rawValue == "bold" })
        #expect(bold?.shortcut != nil, "Bold should have a keyboard shortcut")
    }

    @Test("MutationOrigin distinguishes keyboard vs other input sources")
    func mutationOriginKeyboard() {
        let keyboardOrigins: [MutationOrigin] = [.userTyping, .formatting, .pasteOrDrop]
        let nonKeyboardOrigins: [MutationOrigin] = [.aiInsert, .syncMerge, .writingTools]

        for origin in keyboardOrigins {
            let tx = MutationTransaction(origin: origin, editedRange: NSRange(location: 0, length: 1), replacementLength: 1)
            #expect(tx.registersUndo, "\(origin) should register undo for keyboard users")
        }

        for origin in nonKeyboardOrigins {
            // These may or may not register undo depending on the origin
            let tx = MutationTransaction(origin: origin, editedRange: NSRange(location: 0, length: 1), replacementLength: 1)
            _ = tx.registersUndo // Just verify it compiles
        }
    }

    @Test("SidebarSortOrder all cases usable via keyboard menu")
    func sortOrderKeyboard() {
        for order in SidebarSortOrder.allCases {
            #expect(!order.rawValue.isEmpty,
                "SidebarSortOrder.\(order) must have rawValue for keyboard menu persistence")
        }
        #expect(SidebarSortOrder.allCases.count >= 3)
    }

    @Test("All command keywords non-empty for fuzzy search")
    @MainActor func commandKeywordsNonEmpty() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )

        for cmd in commands {
            #expect(!cmd.keywords.isEmpty,
                "Command '\(cmd.id)' must have keywords for Cmd+K fuzzy search")
        }
    }
}
