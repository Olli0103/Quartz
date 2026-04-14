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
/// Missing baselines are a hard failure in normal runs; opt into recording with
/// `QUARTZ_RECORD_PHASE4_SNAPSHOTS=1` only when intentionally refreshing fixtures.
final class Phase4SnapshotMatrixTests: XCTestCase {

    override func invokeTest() {
        withSnapshotTesting(record: snapshotRecordMode) {
            super.invokeTest()
        }
    }

    // MARK: - Platform Suffix

    @MainActor
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

    private var snapshotRecordMode: SnapshotTestingConfiguration.Record {
        if ProcessInfo.processInfo.environment["QUARTZ_RECORD_PHASE4_SNAPSHOTS"] == "1" {
            return .all
        }
        if UserDefaults.standard.bool(forKey: "QUARTZ_RECORD_PHASE4_SNAPSHOTS") {
            return .all
        }
        if FileManager.default.fileExists(atPath: snapshotRecordFlagPath.path) {
            return .all
        }
        return .never
    }

    private var snapshotRecordFlagPath: URL {
        URL(filePath: "/tmp/quartz_record_phase4_snapshots.flag")
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
        .frame(width: 360, height: 70, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_Recording_\(platformSuffix)",
            canvasSize: CGSize(width: 360, height: 70)
        )
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
        .frame(width: 360, height: 70, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_Paused_\(platformSuffix)",
            canvasSize: CGSize(width: 360, height: 70)
        )
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
        .frame(width: 360, height: 70, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_Stopped_\(platformSuffix)",
            canvasSize: CGSize(width: 360, height: 70)
        )
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
        .frame(width: 360, height: 100, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_WithTranscript_\(platformSuffix)",
            canvasSize: CGSize(width: 360, height: 100)
        )
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
        .frame(width: 360, height: 100, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_LongTranscript_\(platformSuffix)",
            canvasSize: CGSize(width: 360, height: 100)
        )
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
        .frame(width: 360, height: 100, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_Recording_DarkMode_\(platformSuffix)",
            canvasSize: CGSize(width: 360, height: 100),
            colorScheme: .dark
        )
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
        .frame(width: 360, height: 70, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_Paused_DarkMode_\(platformSuffix)",
            canvasSize: CGSize(width: 360, height: 70),
            colorScheme: .dark
        )
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
        .frame(width: 300, height: 100, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_CompactWidth_\(platformSuffix)",
            canvasSize: CGSize(width: 300, height: 100)
        )
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
        .frame(width: 500, height: 100, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_RegularWidth_\(platformSuffix)",
            canvasSize: CGSize(width: 500, height: 100)
        )
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
        .frame(width: 400, height: 120, alignment: .topLeading)
        .environment(\.dynamicTypeSize, .xxxLarge)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_LargeDynamicType_\(platformSuffix)",
            canvasSize: CGSize(width: 400, height: 120)
        )
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
        .frame(width: 360, height: 70, alignment: .topLeading)

        assertViewSnapshot(
            view,
            named: "LiveCapsule_ZeroDuration_\(platformSuffix)",
            canvasSize: CGSize(width: 360, height: 70)
        )
    }

    func testCommittedBaselinesExistForMaciPhoneAndiPad() throws {
        guard snapshotRecordMode == .never else {
            throw XCTSkip("Baseline existence is validated on assertion runs, not while refreshing fixtures.")
        }

        let expectedNames = [
            "testLiveCapsuleRecordingState.LiveCapsule_Recording",
            "testLiveCapsulePausedState.LiveCapsule_Paused",
            "testLiveCapsuleStoppedState.LiveCapsule_Stopped",
            "testLiveCapsuleWithTranscript.LiveCapsule_WithTranscript",
            "testLiveCapsuleWithLongTranscript.LiveCapsule_LongTranscript",
            "testLiveCapsuleRecordingDarkMode.LiveCapsule_Recording_DarkMode",
            "testLiveCapsulePausedDarkMode.LiveCapsule_Paused_DarkMode",
            "testLiveCapsuleCompactWidth.LiveCapsule_CompactWidth",
            "testLiveCapsuleRegularWidth.LiveCapsule_RegularWidth",
            "testLiveCapsuleLargeDynamicType.LiveCapsule_LargeDynamicType",
            "testLiveCapsuleZeroDuration.LiveCapsule_ZeroDuration",
        ]
        let platforms = ["macOS", "iOS", "iPadOS"]
        let snapshotDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__/Phase4SnapshotMatrixTests")

        for expectedName in expectedNames {
            for platform in platforms {
                let fileURL = snapshotDirectory.appendingPathComponent("\(expectedName)_\(platform).png")
                XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path),
                              "Missing committed Phase 4 snapshot baseline: \(fileURL.lastPathComponent)")
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func assertViewSnapshot<V: View>(
        _ view: V,
        named name: String,
        canvasSize: CGSize,
        colorScheme: ColorScheme = .light,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line
    ) {
        let configuredView = view.preferredColorScheme(colorScheme)
        #if canImport(UIKit)
        let controller = UIHostingController(rootView: configuredView)
        controller.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        controller.view.frame = CGRect(origin: .zero, size: canvasSize)
        controller.view.layoutIfNeeded()
        assertSnapshot(
            of: controller,
            as: .image,
            named: name,
            file: file,
            testName: testName,
            line: line
        )
        #elseif canImport(AppKit)
        let snapshotImage = makeRetinaSnapshotImage(
            rootView: configuredView,
            colorScheme: colorScheme,
            canvasSize: canvasSize
        )
        assertSnapshot(
            of: snapshotImage,
            as: .image,
            named: name,
            file: file,
            testName: testName,
            line: line
        )
        #endif
    }
}
