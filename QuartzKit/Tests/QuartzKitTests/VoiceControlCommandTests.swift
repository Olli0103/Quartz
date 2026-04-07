import Testing
import Foundation
@testable import QuartzKit

// MARK: - Voice Control Command Tests
//
// Validates that all commands are speakable and unambiguous for Voice Control.
// Voice Control requires unique, pronounceable titles that don't conflict.

@Suite("VoiceControlCommand")
struct VoiceControlCommandTests {

    @MainActor private func buildCommands() -> [PaletteCommand] {
        let noop: @MainActor @Sendable () -> Void = {}
        return CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )
    }

    @Test("All palette commands have keywords for fuzzy search")
    @MainActor func commandsHaveKeywords() {
        let commands = buildCommands()
        #expect(!commands.isEmpty)
        for cmd in commands {
            #expect(!cmd.keywords.isEmpty, "Command '\(cmd.title)' has no keywords")
        }
    }

    @Test("All commands have speakable non-empty titles")
    @MainActor func commandTitlesSpeakable() {
        let commands = buildCommands()
        for cmd in commands {
            #expect(!cmd.title.isEmpty, "Command \(cmd.id) must have a title for Voice Control")
            #expect(cmd.title.count >= 2,
                "Command \(cmd.id) title '\(cmd.title)' too short for voice recognition")
            let letters = cmd.title.filter { $0.isLetter }
            #expect(!letters.isEmpty,
                "Command \(cmd.id) title must contain letters for Voice Control")
        }
    }

    @Test("Command titles are unique for Voice Control disambiguation")
    @MainActor func commandTitlesUnique() {
        let commands = buildCommands()
        let titles = commands.map { $0.title.lowercased() }
        #expect(Set(titles).count == titles.count,
            "All command titles must be unique (case-insensitive) for Voice Control")
    }

    @Test("Command IDs are unique")
    @MainActor func commandIdsUnique() {
        let commands = buildCommands()
        let ids = commands.map { $0.id }
        #expect(Set(ids).count == ids.count, "All command IDs must be unique")
    }

    @Test("Minimum command count covers essential operations")
    @MainActor func minimumCommandCount() {
        let commands = buildCommands()
        #expect(commands.count >= 8,
            "Should have at least 8 commands for essential operations")
    }

    @Test("All commands have SF Symbol icons")
    @MainActor func commandsHaveIcons() {
        let commands = buildCommands()
        for cmd in commands {
            #expect(!cmd.icon.isEmpty, "Command '\(cmd.title)' must have an icon")
        }
    }
}
