import SwiftUI
import QuartzKit

@main
struct QuartzApp: App {
    @State private var appState = AppState()
    @State private var appearanceManager = AppearanceManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.featureGate, ServiceContainer.shared.resolveFeatureGate())
                .environment(\.appearanceManager, appearanceManager)
                .preferredColorScheme(appearanceManager.theme.colorScheme)
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .environment(\.appearanceManager, appearanceManager)
        }
        #endif
    }
}
