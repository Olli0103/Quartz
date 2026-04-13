import XCTest
import SwiftUI
import Foundation
@testable import QuartzKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
final class Phase4LiveCapsuleAccessibilityTests: XCTestCase {

    func testRenderedCapsuleMaterializesAccessibilityTree() {
        let view = makeCapsule(
            duration: "01:30",
            isPaused: false,
            isRecording: true,
            transcript: "Live transcript preview for accessibility validation."
        )

        #if canImport(AppKit)
        let hostingView = hostAppKitView(view, size: NSSize(width: 360, height: 120))
        XCTAssertNotNil(hostingView.accessibilityRole(),
                        "Live capsule must expose an accessibility role when rendered on macOS")
        XCTAssertGreaterThan(hostingView.fittingSize.width, 180,
                             "Live capsule must lay out to a meaningful width when rendered on macOS")
        XCTAssertGreaterThan(hostingView.fittingSize.height, 44,
                             "Live capsule must lay out to a meaningful height when rendered on macOS")
        #elseif canImport(UIKit)
        let controller = hostUIKitView(view, size: CGSize(width: 360, height: 120))
        let axCount = controller.view.accessibilityElementCount()
        let elements = collectAccessibleElements(from: controller.view)
        XCTAssertTrue(axCount > 0 || !elements.isEmpty,
                      "Live capsule must expose accessibility elements when rendered on iOS")
        #endif
    }

    func testTranscriptPreviewExpandsRenderedHeight() {
        let compact = makeCapsule(duration: "00:45", isPaused: false, isRecording: true)
        let expanded = makeCapsule(
            duration: "00:45",
            isPaused: false,
            isRecording: true,
            transcript: "Transcript preview should add a second rendered row for VoiceOver context."
        )

        #if canImport(AppKit)
        let compactView = hostAppKitView(compact, size: NSSize(width: 360, height: 80))
        let expandedView = hostAppKitView(expanded, size: NSSize(width: 360, height: 120))
        XCTAssertGreaterThan(expandedView.fittingSize.height, compactView.fittingSize.height,
                             "Transcript preview should increase rendered capsule height")
        #elseif canImport(UIKit)
        let compactController = hostUIKitView(compact, size: CGSize(width: 360, height: 80))
        let expandedController = hostUIKitView(expanded, size: CGSize(width: 360, height: 120))
        let compactHeight = compactController.view.intrinsicContentSize.height
        let expandedHeight = expandedController.view.intrinsicContentSize.height
        XCTAssertGreaterThan(expandedHeight, compactHeight,
                             "Transcript preview should increase rendered capsule height")
        #endif
    }

    func testAccessibilityDynamicTypeLayoutRemainsBounded() {
        let view = makeCapsule(
            duration: "12:05",
            isPaused: false,
            isRecording: true,
            transcript: "Accessibility sizing should remain legible without clipping the live capsule."
        )
        .environment(\.dynamicTypeSize, .accessibility3)

        #if canImport(AppKit)
        let hostingView = hostAppKitView(view, size: NSSize(width: 420, height: 180))
        XCTAssertGreaterThan(hostingView.fittingSize.height, 70,
                             "Accessibility Dynamic Type should expand the layout")
        XCTAssertLessThan(hostingView.fittingSize.height, 220,
                          "Accessibility Dynamic Type should remain bounded for the floating capsule")
        #elseif canImport(UIKit)
        let controller = hostUIKitView(view, size: CGSize(width: 420, height: 180))
        let height = controller.view.intrinsicContentSize.height
        XCTAssertGreaterThan(height, 70,
                             "Accessibility Dynamic Type should expand the layout")
        XCTAssertLessThan(height, 220,
                          "Accessibility Dynamic Type should remain bounded for the floating capsule")
        #endif
    }

    func testCallbacksRemainDistinct() {
        var expandCount = 0
        var pauseCount = 0
        var stopCount = 0

        let capsule = LiveCapsuleOverlay(
            formattedDuration: "00:20",
            isPaused: false,
            isRecording: true,
            liveTranscript: "",
            onExpand: { expandCount += 1 },
            onTogglePause: { pauseCount += 1 },
            onStop: { stopCount += 1 }
        )

        capsule.onExpand()
        capsule.onTogglePause()
        capsule.onStop()

        XCTAssertEqual(expandCount, 1)
        XCTAssertEqual(pauseCount, 1)
        XCTAssertEqual(stopCount, 1)
    }

    func testSourceDeclaresVoiceOverLabelsTraitsAndHints() throws {
        let content = try sourceContents()

        XCTAssertTrue(content.contains(".accessibilityElement(children: .contain)"),
                      "Capsule container must preserve child controls for VoiceOver navigation")
        XCTAssertTrue(content.contains(".accessibilityLabel(accessibilityDescription)"),
                      "Capsule must expose a descriptive accessibility label")
        XCTAssertTrue(content.contains(".accessibilityValue(formattedDuration)"),
                      "Capsule must expose the formatted duration as the accessibility value")
        XCTAssertTrue(content.contains("Expand to full view"),
                      "Expand affordance must be labeled for VoiceOver")
        XCTAssertTrue(content.contains("Pause recording"),
                      "Pause affordance must be labeled for VoiceOver")
        XCTAssertTrue(content.contains("Resume recording"),
                      "Resume affordance must be labeled for VoiceOver")
        XCTAssertTrue(content.contains("Stop recording"),
                      "Stop affordance must be labeled for VoiceOver")
        XCTAssertTrue(content.contains("Stops recording and processes audio"),
                      "Stop affordance must provide an accessibility hint")
        XCTAssertTrue(content.contains(".accessibilityAddTraits(.updatesFrequently)"),
                      "Transcript preview must announce itself as frequently updating")
    }

    func testSourceUsesReduceMotionDrivenSpringAnimationOnly() throws {
        let content = try sourceContents()
        let pulseSection = try XCTUnwrap(content.components(separatedBy: "private struct PulseModifier").last)

        XCTAssertTrue(content.contains("@Environment(\\.accessibilityReduceMotion)"),
                      "Live capsule must read the Reduce Motion environment")
        XCTAssertTrue(content.contains("PulseModifier(isActive: !reduceMotion && isRecording && !isPaused)"),
                      "Pulse activation must be gated by Reduce Motion and recording state")
        XCTAssertTrue(pulseSection.contains(".spring"),
                      "Pulse animation must use spring timing")
        XCTAssertFalse(pulseSection.contains(".linear"),
                       "Pulse animation must not use linear timing")
        XCTAssertFalse(pulseSection.contains(".easeInOut"),
                       "Pulse animation must not use easeInOut timing")
    }

    func testSourcePreservesTranscriptLegibilityAtLargeSizes() throws {
        let content = try sourceContents()

        XCTAssertTrue(content.contains("String(liveTranscript.suffix(80))"),
                      "Transcript preview must prefer the newest text for live updates")
        XCTAssertTrue(content.contains(".lineLimit(1)"),
                      "Transcript preview must remain single-line in the capsule")
        XCTAssertTrue(content.contains(".truncationMode(.head)"),
                      "Transcript preview must keep the newest words visible")
        XCTAssertTrue(content.contains("design: .monospaced"),
                      "Timer digits must use a monospaced design to prevent layout jitter")
        XCTAssertTrue(content.contains(".contentTransition(.numericText())"),
                      "Timer updates should use numeric transitions for stable announcements")
    }

    func testSourceUsesMaterialAndSemanticForegroundStyles() throws {
        let content = try sourceContents()

        XCTAssertTrue(content.contains(".background(.ultraThinMaterial"),
                      "Capsule must use system material so Reduce Transparency can adapt it")
        XCTAssertTrue(content.contains(".foregroundStyle(.primary)"),
                      "Primary content must use semantic foreground styles")
        XCTAssertTrue(content.contains(".foregroundStyle(.secondary)"),
                      "Secondary content must use semantic foreground styles")
        XCTAssertFalse(content.contains("Color.black"),
                       "Live capsule must not hardcode black text")
        XCTAssertFalse(content.contains("Color.white"),
                       "Live capsule must not hardcode white text outside the stop glyph treatment")
    }

    private func makeCapsule(
        duration: String,
        isPaused: Bool,
        isRecording: Bool,
        transcript: String = ""
    ) -> some View {
        LiveCapsuleOverlay(
            formattedDuration: duration,
            isPaused: isPaused,
            isRecording: isRecording,
            liveTranscript: transcript,
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )
        .frame(width: 360)
    }

    private func sourceContents() throws -> String {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/QuartzKit/Presentation/Audio/LiveCapsuleOverlay.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    #if canImport(AppKit)
    private func hostAppKitView<V: View>(_ view: V, size: NSSize) -> NSHostingView<V> {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        return hostingView
    }

    #elseif canImport(UIKit)
    private func hostUIKitView<V: View>(_ view: V, size: CGSize) -> UIHostingController<V> {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.layoutIfNeeded()
        return controller
    }

    private func collectAccessibleElements(from view: UIView) -> [NSObject] {
        var result: [NSObject] = []
        if let elements = view.accessibilityElements as? [NSObject] {
            result.append(contentsOf: elements)
        }
        for subview in view.subviews {
            result.append(contentsOf: collectAccessibleElements(from: subview))
        }
        return result
    }
    #endif
}
