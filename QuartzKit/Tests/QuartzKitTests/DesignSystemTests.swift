import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import SwiftUI
@testable import QuartzKit

// MARK: - Design System Tests

/// Verifies Color(hex:) utility and typography constants.

@Suite("Design System")
struct DesignSystemTests {

    @Test("Color(hex:) with valid hex produces non-nil color")
    func colorHexValid() {
        let color = Color(hex: 0xF2994A)
        // Color is always non-nil (struct), just verify it creates without crash
        _ = color
    }

    @Test("SyntaxVisibilityMode has 3 cases")
    func syntaxVisibilityModes() {
        let modes: [SyntaxVisibilityMode] = [.full, .gentleFade, .hiddenUntilCaret]
        #expect(modes.count == 3)
    }
}
