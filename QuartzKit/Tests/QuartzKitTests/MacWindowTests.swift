import Testing
import Foundation
@testable import QuartzKit

// MARK: - Mac Window Tests
//
// macOS multi-window and menu command contracts: CommandRegistry,
// PaletteCommand shortcuts, DetailRoute destinations, templates.

@Suite("MacWindow")
struct MacWindowTests {

    @MainActor private func buildCommands() -> [PaletteCommand] {
        let noop: @MainActor @Sendable () -> Void = {}
        return CommandRegistry.build(
            vaultRoot: URL(fileURLWithPath: "/vault"),
            onNewNote: noop, onNewFolder: noop, onDailyNote: noop,
            onVaultChat: noop, onSettings: noop, onToggleFocus: noop,
            onToggleDarkMode: noop, onReindex: noop, onExportBackup: noop
        )
    }

    @Test("CommandRegistry provides commands for all menu categories")
    @MainActor func commandCategories() {
        let commands = buildCommands()
        #expect(commands.count >= 8,
            "Should have commands for note, folder, daily, chat, settings, focus, dark mode, reindex")
    }

    @Test("PaletteCommand has icon for menu display")
    @MainActor func commandIcons() {
        let commands = buildCommands()
        for cmd in commands {
            #expect(!cmd.icon.isEmpty,
                "Command '\(cmd.id)' must have an icon for menu display")
        }
    }

    @Test("DetailRoute supports all macOS window destinations")
    @MainActor func macDestinations() {
        let store = WorkspaceStore()

        // macOS windows can show any route
        let routes: [DetailRoute] = [
            .dashboard,
            .graph,
            .note(URL(fileURLWithPath: "/vault/note.md")),
            .empty
        ]

        for route in routes {
            store.route = route
            #expect(store.route == route, "Route \(route) must be settable")
        }
    }

    @Test("AppearanceManager showDashboardOnLaunch setting exists")
    @MainActor func dashboardOnLaunch() {
        let suiteName = "MacWindow-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let manager = AppearanceManager(defaults: defaults)

        // Property should be accessible (macOS-specific preference)
        let initial = manager.showDashboardOnLaunch
        manager.showDashboardOnLaunch = !initial
        #expect(manager.showDashboardOnLaunch == !initial)
    }

    @Test("NoteTemplate covers all template types")
    func templateCoverage() {
        let cases = NoteTemplate.allCases
        #expect(cases.count >= 5,
            "Should have blank, daily, meeting, zettel, and project templates")

        for template in cases {
            #expect(!template.displayName.isEmpty,
                "NoteTemplate.\(template) must have a display name")
            #expect(!template.icon.isEmpty,
                "NoteTemplate.\(template) must have an icon")
        }
    }

    @Test("SidebarFilter rawValues round-trip for menu state")
    func sidebarFilterMenuState() {
        for filter in SidebarFilter.allCases {
            let restored = SidebarFilter(rawValue: filter.rawValue)
            #expect(restored == filter)
        }
    }
}
