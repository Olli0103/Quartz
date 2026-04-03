import Testing
import Foundation
@testable import QuartzKit

// MARK: - Voice Control Command Tests

@Suite("VoiceControlCommand")
struct VoiceControlCommandTests {

    @Test("All palette commands have keywords for fuzzy search")
    @MainActor func commandsHaveKeywords() {
        let noop: @MainActor @Sendable () -> Void = {}
        let commands = CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )
        #expect(!commands.isEmpty)

        for cmd in commands {
            #expect(!cmd.keywords.isEmpty, "Command '\(cmd.title)' has no keywords")
        }
    }
}
