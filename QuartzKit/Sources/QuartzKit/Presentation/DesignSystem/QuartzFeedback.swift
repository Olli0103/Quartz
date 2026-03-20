import Foundation

#if os(iOS)
import UIKit
#endif

/// Central tactile feedback for primary actions. UIKit-backed on iPhone / iPad; no-op elsewhere.
@MainActor
public enum QuartzFeedback {
    public static func selection() {
        #if os(iOS)
        impact(.light)
        #endif
    }

    public static func primaryAction() {
        #if os(iOS)
        impact(.medium)
        #endif
    }

    public static func success() {
        #if os(iOS)
        notify(.success)
        #endif
    }

    public static func warning() {
        #if os(iOS)
        notify(.warning)
        #endif
    }

    public static func destructive() {
        #if os(iOS)
        notify(.error)
        #endif
    }

    public static func toggle() {
        #if os(iOS)
        impact(.rigid)
        #endif
    }

    #if os(iOS)
    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
    #endif
}
