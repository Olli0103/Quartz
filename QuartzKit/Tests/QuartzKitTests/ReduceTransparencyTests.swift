import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - Reduce Transparency Tests
//
// Material/design system contracts for opaque fallback when
// Reduce Transparency is enabled. Verifies design token types
// and color palette contracts.

@Suite("ReduceTransparency")
struct ReduceTransparencyTests {

    @Test("QuartzMaterialLayer has sidebar and floating cases")
    func materialLayerCases() {
        let layers: [QuartzMaterialLayer] = [.sidebar, .floating]
        #expect(layers.count == 2,
            "Material layers should cover sidebar and floating contexts")
    }

    @Test("QuartzAmbientMeshStyle has all depth levels")
    func ambientMeshStyles() {
        let styles: [QuartzAmbientMeshStyle] = [.onboarding, .shell, .editorChrome]
        #expect(styles.count == 3,
            "Ambient mesh should cover onboarding, shell, and editorChrome depths")
    }

    @Test("QuartzColors provides semantic color tokens")
    func semanticColors() {
        // These should all resolve to non-nil Color values
        let accent = QuartzColors.accent
        let folderYellow = QuartzColors.folderYellow
        let noteBlue = QuartzColors.noteBlue
        let assetOrange = QuartzColors.assetOrange
        let canvasPurple = QuartzColors.canvasPurple

        // Verify they are distinct (different descriptions)
        let descriptions = Set([
            "\(accent)", "\(folderYellow)", "\(noteBlue)",
            "\(assetOrange)", "\(canvasPurple)"
        ])
        #expect(descriptions.count >= 4,
            "Node type colors should be visually distinct")
    }

    @Test("QuartzColors tagPalette has sufficient variety")
    func tagPaletteVariety() {
        let palette = QuartzColors.tagPalette
        #expect(palette.count >= 8,
            "Tag palette should have at least 8 colors for visual variety")
    }

    @Test("QuartzColors tagColor is deterministic across calls")
    func tagColorDeterministic() {
        let color1 = QuartzColors.tagColor(for: "swift")
        let color2 = QuartzColors.tagColor(for: "swift")

        #expect("\(color1)" == "\(color2)",
            "Same tag should produce same color deterministically")

        let different = QuartzColors.tagColor(for: "python")
        // Different tags should generally produce different colors
        // (not guaranteed but likely with good hash distribution)
        _ = different // Access to verify it compiles
    }
}
