import SwiftUI
import QuartzKit

@main
struct QuartzApp: App {
    @State private var appState = AppState()
    @State private var appearanceManager = AppearanceManager()
    @State private var focusModeManager = FocusModeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.featureGate, ServiceContainer.shared.resolveFeatureGate())
                .environment(\.appearanceManager, appearanceManager)
                .environment(\.focusModeManager, focusModeManager)
                .preferredColorScheme(appearanceManager.theme.colorScheme)
                .tint(Color(hex: 0xF2994A))
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 700)

        Settings {
            SettingsView()
                .environment(\.appearanceManager, appearanceManager)
        }
        #endif
    }
}
