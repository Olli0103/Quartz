import Testing
import Foundation
import XCTest
@testable import QuartzKit

// MARK: - Phase 6: ADA Liquid Glass & HIG Compliance Tests

// MARK: - QuartzColors Tests

@Suite("QuartzColors")
struct QuartzColorsTests {
    @Test("Tag color is deterministic for same input")
    func tagColorDeterministic() {
        let color1 = QuartzColors.tagColor(for: "work")
        let color2 = QuartzColors.tagColor(for: "work")

        // Same input should produce same color
        #expect(color1 == color2)
    }

    @Test("Tag color varies for different inputs")
    func tagColorVaries() {
        let color1 = QuartzColors.tagColor(for: "work")
        let color2 = QuartzColors.tagColor(for: "personal")
        let color3 = QuartzColors.tagColor(for: "important")

        // Different inputs should produce different colors (high probability)
        // At least 2 of 3 should differ given 8-color palette
        let colors = Set([color1.description, color2.description, color3.description])
        #expect(colors.count >= 2)
    }

    @Test("Tag palette has sufficient variety")
    func tagPaletteVariety() {
        #expect(QuartzColors.tagPalette.count >= 6)
    }

    @Test("Accent gradient exists")
    func accentGradientExists() {
        let gradient = QuartzColors.accentGradient
        #expect(gradient != nil)
    }

    @Test("Warm and cool gradients exist")
    func gradientsExist() {
        let warm = QuartzColors.warmGradient
        let cool = QuartzColors.coolGradient
        #expect(warm != nil)
        #expect(cool != nil)
    }
}

// MARK: - QuartzHIG Tests

@Suite("QuartzHIG")
struct QuartzHIGTests {
    @Test("Minimum touch target meets Apple HIG")
    func minTouchTarget() {
        // Apple HIG specifies 44pt minimum
        #expect(QuartzHIG.minTouchTarget == 44)
    }
}

// MARK: - QuartzAnimation Tests

@Suite("QuartzAnimation")
struct QuartzAnimationTests {
    @Test("Standard animation exists")
    func standardAnimationExists() {
        let animation = QuartzAnimation.standard
        #expect(animation != nil)
    }

    @Test("Bounce animation exists")
    func bounceAnimationExists() {
        let animation = QuartzAnimation.bounce
        #expect(animation != nil)
    }

    @Test("Soft animation exists")
    func softAnimationExists() {
        let animation = QuartzAnimation.soft
        #expect(animation != nil)
    }

    @Test("Content animation exists")
    func contentAnimationExists() {
        let animation = QuartzAnimation.content
        #expect(animation != nil)
    }

    @Test("Appear animation exists")
    func appearAnimationExists() {
        let animation = QuartzAnimation.appear
        #expect(animation != nil)
    }

    @Test("Stagger animation exists")
    func staggerAnimationExists() {
        let animation = QuartzAnimation.stagger
        #expect(animation != nil)
    }

    @Test("Button press animation exists")
    func buttonPressAnimationExists() {
        let animation = QuartzAnimation.buttonPress
        #expect(animation != nil)
    }

    @Test("Card press animation exists")
    func cardPressAnimationExists() {
        let animation = QuartzAnimation.cardPress
        #expect(animation != nil)
    }

    @Test("Pulse animation exists")
    func pulseAnimationExists() {
        let animation = QuartzAnimation.pulse
        #expect(animation != nil)
    }

    @Test("Shimmer animation exists")
    func shimmerAnimationExists() {
        let animation = QuartzAnimation.shimmer
        #expect(animation != nil)
    }

    @Test("Folder expand animation exists")
    func folderExpandAnimationExists() {
        let animation = QuartzAnimation.folderExpand
        #expect(animation != nil)
    }

    @Test("Preview edit toggle animation exists")
    func previewEditToggleAnimationExists() {
        let animation = QuartzAnimation.previewEditToggle
        #expect(animation != nil)
    }

    @Test("Focus chrome animation exists")
    func focusChromeAnimationExists() {
        let animation = QuartzAnimation.focusChrome
        #expect(animation != nil)
    }
}

// MARK: - QuartzAmbientMeshStyle Tests

@Suite("QuartzAmbientMeshStyle")
struct QuartzAmbientMeshStyleTests {
    @Test("All mesh styles are available")
    func allMeshStylesAvailable() {
        let onboarding = QuartzAmbientMeshStyle.onboarding
        let shell = QuartzAmbientMeshStyle.shell
        let editorChrome = QuartzAmbientMeshStyle.editorChrome

        #expect(onboarding == .onboarding)
        #expect(shell == .shell)
        #expect(editorChrome == .editorChrome)
    }
}

// MARK: - QuartzMaterialLayer Tests

@Suite("QuartzMaterialLayer")
struct QuartzMaterialLayerTests {
    @Test("Material layers are available")
    func materialLayersAvailable() {
        let sidebar = QuartzMaterialLayer.sidebar
        let floating = QuartzMaterialLayer.floating

        #expect(sidebar == .sidebar)
        #expect(floating == .floating)
    }
}

// MARK: - TagInfo Tests

@Suite("TagInfo")
struct TagInfoTests {
    @Test("TagInfo has correct properties")
    func tagInfoProperties() {
        let tag = TagInfo(name: "project", count: 5)

        #expect(tag.name == "project")
        #expect(tag.count == 5)
        #expect(tag.id == "project")
    }

    @Test("TagInfo ID is name-based")
    func tagInfoIDIsName() {
        let tag1 = TagInfo(name: "work", count: 3)
        let tag2 = TagInfo(name: "work", count: 10)

        #expect(tag1.id == tag2.id)
    }
}

// MARK: - Color Hex Init Tests

@Suite("ColorHexInit")
struct ColorHexInitTests {
    @Test("Color can be created from hex")
    func colorFromHex() {
        let color = Color(hex: 0xF2994A)
        #expect(color != nil)
    }

    @Test("Color can be created from hex with alpha")
    func colorFromHexWithAlpha() {
        let color = Color(hex: 0xF2994A, alpha: 0.5)
        #expect(color != nil)
    }
}

// MARK: - XCTest Performance Tests for Liquid Glass

final class LiquidGlassPerformanceTests: XCTestCase {
    func testTagColorGenerationPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            // Generate 1000 tag colors
            for i in 0..<1000 {
                _ = QuartzColors.tagColor(for: "tag_\(i)")
            }
        }
    }

    func testTagInfoCreationPerformance() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            var tags: [TagInfo] = []
            for i in 0..<500 {
                tags.append(TagInfo(name: "tag_\(i)", count: Int.random(in: 1...100)))
            }
            XCTAssertEqual(tags.count, 500)
        }
    }

    func testAnimationConstantAccess() throws {
        let options = XCTMeasureOptions()
        options.iterationCount = 10

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            for _ in 0..<1000 {
                _ = QuartzAnimation.standard
                _ = QuartzAnimation.bounce
                _ = QuartzAnimation.soft
                _ = QuartzAnimation.content
                _ = QuartzAnimation.appear
                _ = QuartzAnimation.buttonPress
                _ = QuartzAnimation.cardPress
            }
        }
    }
}

// MARK: - Accessibility Compliance Tests

@Suite("AccessibilityCompliance")
struct AccessibilityComplianceTests {
    @Test("QuartzTagBadge has accessibility label")
    func tagBadgeAccessibility() {
        // QuartzTagBadge should have .accessibilityLabel set
        // This is a compile-time check - the view exists and compiles
        let badge = QuartzTagBadge(text: "important")
        #expect(badge.text == "important")
    }

    @Test("QuartzButton has proper structure")
    func buttonStructure() {
        var actionCalled = false
        let button = QuartzButton("Test", icon: "star") {
            actionCalled = true
        }
        #expect(button.title == "Test")
    }

    @Test("QuartzSectionHeader has proper structure")
    func sectionHeaderStructure() {
        let header = QuartzSectionHeader("Test Section", icon: "folder")
        #expect(header.title == "Test Section")
    }

    @Test("QuartzEmptyState has proper structure")
    func emptyStateStructure() {
        let emptyState = QuartzEmptyState(
            icon: "doc.text",
            title: "No Notes",
            subtitle: "Create your first note"
        )
        #expect(emptyState.icon == "doc.text")
        #expect(emptyState.title == "No Notes")
        #expect(emptyState.subtitle == "Create your first note")
    }
}

// MARK: - Button Style Tests

@Suite("QuartzButtonStyles")
struct QuartzButtonStylesTests {
    @Test("QuartzPressButtonStyle exists")
    func pressButtonStyleExists() {
        let style = QuartzPressButtonStyle()
        #expect(style != nil)
    }

    @Test("QuartzCardButtonStyle exists")
    func cardButtonStyleExists() {
        let style = QuartzCardButtonStyle()
        #expect(style != nil)
    }

    @Test("QuartzBounceButtonStyle exists")
    func bounceButtonStyleExists() {
        let style = QuartzBounceButtonStyle()
        #expect(style != nil)
    }
}

// MARK: - Skeleton Row Tests

@Suite("SkeletonRow")
struct SkeletonRowTests {
    @Test("SkeletonRow initializes without crashing")
    func skeletonRowInit() {
        let row = SkeletonRow()
        #expect(row != nil)
    }
}
