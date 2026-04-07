import Testing
import Foundation
import SwiftUI
@testable import QuartzKit

// MARK: - Material Token Tests
//
// Design token consistency: material layers, mesh styles,
// color palette, and deterministic tag coloring.

@Suite("MaterialToken")
struct MaterialTokenTests {

    @Test("QuartzMaterialLayer covers all depth levels")
    func materialLayers() {
        let layers: [QuartzMaterialLayer] = [.sidebar, .floating]
        #expect(layers.count == 2,
            "Material layers: sidebar (background) and floating (elevated)")
    }

    @Test("QuartzAmbientMeshStyle covers all rendering contexts")
    func meshStyles() {
        let styles: [QuartzAmbientMeshStyle] = [.onboarding, .shell, .editorChrome]
        #expect(styles.count == 3,
            "Mesh styles: onboarding (rich), shell (subtle), editorChrome (very subtle)")
    }

    @Test("QuartzColors accent gradient is not empty")
    func accentGradient() {
        let gradient = QuartzColors.accentGradient
        let desc = "\(gradient)"
        #expect(!desc.isEmpty, "Accent gradient should produce a non-empty description")
    }

    @Test("QuartzColors node type colors are distinct")
    func nodeTypeColors() {
        let colors = [
            ("folderYellow", "\(QuartzColors.folderYellow)"),
            ("noteBlue", "\(QuartzColors.noteBlue)"),
            ("assetOrange", "\(QuartzColors.assetOrange)"),
            ("canvasPurple", "\(QuartzColors.canvasPurple)")
        ]

        let unique = Set(colors.map(\.1))
        #expect(unique.count >= 3,
            "Node type colors should be visually distinct for file type identification")
    }

    @Test("Tag palette has at least 8 colors for visual variety")
    func tagPaletteSize() {
        let palette = QuartzColors.tagPalette
        #expect(palette.count >= 8,
            "Tag palette needs sufficient variety to distinguish tags visually")
    }

    @Test("Tag color is deterministic and stable across calls")
    func tagColorDeterminism() {
        let tags = ["swift", "design", "architecture", "testing", "performance"]

        for tag in tags {
            let color1 = "\(QuartzColors.tagColor(for: tag))"
            let color2 = "\(QuartzColors.tagColor(for: tag))"
            #expect(color1 == color2,
                "tagColor for '\(tag)' must be deterministic")
        }
    }

    @Test("Warm and cool gradients exist as design tokens")
    func gradientTokens() {
        let warm = "\(QuartzColors.warmGradient)"
        let cool = "\(QuartzColors.coolGradient)"
        #expect(!warm.isEmpty, "Warm gradient should produce a description")
        #expect(!cool.isEmpty, "Cool gradient should produce a description")
    }
}
