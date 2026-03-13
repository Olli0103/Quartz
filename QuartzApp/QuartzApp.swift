import SwiftUI
import QuartzKit

@main
struct QuartzApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Quartz – v\(QuartzKit.version)")
        }
    }
}
