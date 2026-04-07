import Testing
import Foundation
@testable import QuartzKit

// MARK: - Keyboard Navigation Tests
//
// Keyboard-invocable command and shortcut contracts: Cmd+K palette,
// formatting actions, mutation origins, and filter/sort accessibility.

@Suite("KeyboardNavigation")
struct KeyboardNavigationTests {

    @Test("CommandRegistry provides sufficient commands for Cmd+K palette")
    @MainActor func commandRegistrySufficient() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )

        #expect(commands.count >= 8,
            "Command palette should have sufficient commands for keyboard users")
    }

    @Test("All palette commands have non-empty title and keywords")
    @MainActor func commandTitlesAndKeywords() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )

        for cmd in commands {
            #expect(!cmd.title.isEmpty,
                "Command '\(cmd.id)' must have a title for keyboard palette")
            #expect(!cmd.keywords.isEmpty,
                "Command '\(cmd.id)' must have keywords for fuzzy search")
        }
    }

    @Test("Command IDs are unique")
    @MainActor func commandIDsUnique() {
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
            "All command IDs must be unique for unambiguous keyboard invocation")
    }

    @Test("FormattingAction rawValues are unique")
    func formattingActionUniqueness() {
        let rawValues = FormattingAction.allCases.map(\.rawValue)
        let unique = Set(rawValues)
        #expect(unique.count == rawValues.count,
            "All formatting action rawValues must be unique for keyboard dispatch")
    }

    @Test("MutationOrigin covers all edit sources")
    func mutationOriginCoverage() {
        let cases = MutationOrigin.allCases
        #expect(cases.count >= 9,
            "Should cover userTyping, listContinuation, formatting, aiInsert, syncMerge, pasteOrDrop, writingTools, taskToggle, tableNavigation")

        let rawValues = Set(cases.map(\.rawValue))
        #expect(rawValues.contains("userTyping"))
        #expect(rawValues.contains("formatting"))
        #expect(rawValues.contains("pasteOrDrop"))
    }

    @Test("SidebarFilter and SidebarSortOrder are keyboard-selectable")
    func filterSortKeyboardAccess() {
        for filter in SidebarFilter.allCases {
            let restored = SidebarFilter(rawValue: filter.rawValue)
            #expect(restored == filter,
                "SidebarFilter.\(filter) must persist for keyboard-driven filter change")
        }

        for order in SidebarSortOrder.allCases {
            let restored = SidebarSortOrder(rawValue: order.rawValue)
            #expect(restored == order,
                "SidebarSortOrder.\(order) must persist for keyboard-driven sort change")
        }
    }
}
