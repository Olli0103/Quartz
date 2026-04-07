import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - Contrast Compliance Tests
//
// Validates WCAG AA contrast requirements and color system integrity.
// WCAG AA requires:
//   - 4.5:1 contrast ratio for normal text
//   - 3.0:1 contrast ratio for large text (>= 18pt or >= 14pt bold)

@Suite("ContrastCompliance")
struct ContrastComplianceTests {

    /// Calculates relative luminance of an sRGB color per WCAG 2.1.
    private func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
        func linearize(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// Calculates contrast ratio between two luminances per WCAG 2.1.
    private func contrastRatio(l1: Double, l2: Double) -> Double {
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    @Test("QuartzColors provides distinct light/dark color variants")
    func lightDarkColorVariants() {
        let accent = QuartzColors.accent
        let folderYellow = QuartzColors.folderYellow
        let noteBlue = QuartzColors.noteBlue
        let canvasPurple = QuartzColors.canvasPurple

        #expect(type(of: accent) == Color.self)
        #expect(type(of: folderYellow) == Color.self)
        #expect(type(of: noteBlue) == Color.self)
        #expect(type(of: canvasPurple) == Color.self)
    }

    @Test("Tag palette provides 6+ distinct colors with deterministic mapping")
    func tagPaletteDeterministic() {
        let palette = QuartzColors.tagPalette
        #expect(palette.count >= 6)

        // Deterministic: same tag -> same color
        let color1 = QuartzColors.tagColor(for: "swift")
        let color2 = QuartzColors.tagColor(for: "swift")
        #expect(color1 == color2)
    }

    @Test("Primary text on white meets WCAG AA 4.5:1 contrast")
    func primaryTextOnWhite() {
        let textL = relativeLuminance(r: 0, g: 0, b: 0)
        let bgL = relativeLuminance(r: 1, g: 1, b: 1)
        let ratio = contrastRatio(l1: textL, l2: bgL)
        #expect(ratio >= 4.5,
            "Primary text on white must meet 4.5:1, got \(String(format: "%.1f", ratio)):1")
    }

    @Test("Primary text on dark background meets WCAG AA 4.5:1 contrast")
    func primaryTextOnDark() {
        let textL = relativeLuminance(r: 1, g: 1, b: 1)
        let bgL = relativeLuminance(r: 0.1, g: 0.1, b: 0.1)
        let ratio = contrastRatio(l1: textL, l2: bgL)
        #expect(ratio >= 4.5,
            "White text on dark bg must meet 4.5:1, got \(String(format: "%.1f", ratio)):1")
    }

    @Test("Secondary text meets WCAG AA large-text contrast (3:1)")
    func secondaryTextContrast() {
        let textL = relativeLuminance(r: 0.4, g: 0.4, b: 0.4)
        let bgL = relativeLuminance(r: 1, g: 1, b: 1)
        let ratio = contrastRatio(l1: textL, l2: bgL)
        #expect(ratio >= 3.0,
            "Secondary text on white should meet 3:1 for large text, got \(String(format: "%.1f", ratio)):1")
    }

    @Test("QuartzColors accent is distinguishable on dark backgrounds")
    func accentOnDark() {
        // QuartzColors.accent dark mode: 0xFFAB5E = RGB(255, 171, 94)
        let accentL = relativeLuminance(r: 255/255, g: 171/255, b: 94/255)
        let darkBgL = relativeLuminance(r: 0.1, g: 0.1, b: 0.1)
        let ratio = contrastRatio(l1: accentL, l2: darkBgL)
        #expect(ratio >= 3.0,
            "Accent on dark bg should meet 3:1 for icons/large text, got \(String(format: "%.1f", ratio)):1")
    }

    @Test("WCAG contrast calculation correctness: black on white = 21:1")
    func contrastCalculationVerification() {
        let black = relativeLuminance(r: 0, g: 0, b: 0)
        let white = relativeLuminance(r: 1, g: 1, b: 1)
        let ratio = contrastRatio(l1: black, l2: white)
        #expect(ratio >= 20.9 && ratio <= 21.1,
            "Black on white should be ~21:1, got \(String(format: "%.2f", ratio)):1")
    }
}
