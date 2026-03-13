import SwiftUI
import QuartzKit

@main
struct QuartzApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(\.featureGate, ServiceContainer.shared.resolveFeatureGate())
        }
    }
}
