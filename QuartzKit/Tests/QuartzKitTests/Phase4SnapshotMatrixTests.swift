import XCTest
import SwiftUI
import Foundation
@testable import QuartzKit
import SnapshotTesting

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Cross-platform snapshot tests for Phase 4 UI surfaces.
///
/// Covers LiveCapsuleOverlay in all states (recording, paused, stopped,
/// with transcript, without transcript) across macOS, iOS, and iPadOS.
///
/// Uses `swift-snapshot-testing` with platform-suffixed baselines.
/// Baselines are auto-generated on first run per platform via `record: .missing`.
/// To regenerate all baselines, run on each target platform (macOS, iOS Simulator, iPad Simulator).
final class Phase4SnapshotMatrixTests: XCTestCase {

    // MARK: - Platform Suffix

    private var platformSuffix: String {
        #if os(macOS)
        return "macOS"
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #elseif os(visionOS)
        return "visionOS"
        #else
        return "unknown"
        #endif
    }

    // MARK: - LiveCapsuleOverlay States

    @MainActor
    func testLiveCapsuleRecordingState() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "01:30",
            isPaused: false,
            isRecording: true,
            liveTranscript: "",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 360, height: 70)

        assertViewSnapshot(view, named: "LiveCapsule_Recording_\(platformSuffix)")
    }

    @MainActor
    func testLiveCapsulePausedState() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "05:15",
            isPaused: true,
            isRecording: false,
            liveTranscript: "",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 360, height: 70)

        assertViewSnapshot(view, named: "LiveCapsule_Paused_\(platformSuffix)")
    }

    @MainActor
    func testLiveCapsuleStoppedState() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "10:00",
            isPaused: false,
            isRecording: false,
            liveTranscript: "",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 360, height: 70)

        assertViewSnapshot(view, named: "LiveCapsule_Stopped_\(platformSuffix)")
    }

    // MARK: - LiveCapsuleOverlay with Transcript

    @MainActor
    func testLiveCapsuleWithTranscript() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "02:45",
            isPaused: false,
            isRecording: true,
            liveTranscript: "So the next step is to finalize the API design and share it with the team by Friday.",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 360, height: 100)

        assertViewSnapshot(view, named: "LiveCapsule_WithTranscript_\(platformSuffix)")
    }

    @MainActor
    func testLiveCapsuleWithLongTranscript() {
        let longText = String(repeating: "Meeting discussion about quarterly goals. ", count: 10)
        let view = LiveCapsuleOverlay(
            formattedDuration: "15:00",
            isPaused: false,
            isRecording: true,
            liveTranscript: longText,
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 360, height: 100)

        assertViewSnapshot(view, named: "LiveCapsule_LongTranscript_\(platformSuffix)")
    }

    // MARK: - Dark Mode

    @MainActor
    func testLiveCapsuleRecordingDarkMode() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "03:00",
            isPaused: false,
            isRecording: true,
            liveTranscript: "Discussing the roadmap for next quarter.",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 360, height: 100)
        .preferredColorScheme(.dark)

        assertViewSnapshot(view, named: "LiveCapsule_Recording_DarkMode_\(platformSuffix)")
    }

    @MainActor
    func testLiveCapsulePausedDarkMode() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "07:30",
            isPaused: true,
            isRecording: false,
            liveTranscript: "",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 360, height: 70)
        .preferredColorScheme(.dark)

        assertViewSnapshot(view, named: "LiveCapsule_Paused_DarkMode_\(platformSuffix)")
    }

    // MARK: - Platform Width Variants

    @MainActor
    func testLiveCapsuleCompactWidth() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "00:30",
            isPaused: false,
            isRecording: true,
            liveTranscript: "Quick note capture on iPhone.",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 300, height: 100)

        assertViewSnapshot(view, named: "LiveCapsule_CompactWidth_\(platformSuffix)")
    }

    @MainActor
    func testLiveCapsuleRegularWidth() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "20:00",
            isPaused: false,
            isRecording: true,
            liveTranscript: "Extended meeting recording on iPad or Mac with wider layout.",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 500, height: 100)

        assertViewSnapshot(view, named: "LiveCapsule_RegularWidth_\(platformSuffix)")
    }

    // MARK: - Dynamic Type Variant

    @MainActor
    func testLiveCapsuleLargeDynamicType() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "05:00",
            isPaused: false,
            isRecording: true,
            liveTranscript: "Testing large text accessibility.",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 400, height: 120)
        .environment(\.dynamicTypeSize, .xxxLarge)

        assertViewSnapshot(view, named: "LiveCapsule_LargeDynamicType_\(platformSuffix)")
    }

    // MARK: - Zero Duration Edge Case

    @MainActor
    func testLiveCapsuleZeroDuration() {
        let view = LiveCapsuleOverlay(
            formattedDuration: "00:00",
            isPaused: false,
            isRecording: true,
            liveTranscript: "",
            onExpand: {}, onTogglePause: {}, onStop: {}
        )
        .frame(width: 360, height: 70)

        assertViewSnapshot(view, named: "LiveCapsule_ZeroDuration_\(platformSuffix)")
    }

    // MARK: - Helpers

    @MainActor
    private func assertViewSnapshot<V: View>(
        _ view: V,
        named name: String,
        record: SnapshotTestingConfiguration.Record? = .missing,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        #if canImport(UIKit)
        let controller = UIHostingController(rootView: view)
        controller.view.frame = UIScreen.main.bounds
        controller.view.layoutIfNeeded()
        assertSnapshot(
            of: controller,
            as: .image,
            named: name,
            record: record,
            file: file,
            testName: testName,
            line: line
        )
        #elseif canImport(AppKit)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        hostingView.layoutSubtreeIfNeeded()
        assertSnapshot(
            of: hostingView,
            as: .image,
            named: name,
            record: record,
            file: file,
            testName: testName,
            line: line
        )
        #endif
    }
}
