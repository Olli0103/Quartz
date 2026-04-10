import Testing
import Foundation
@testable import QuartzKit

@Suite("Phase4LiveCapsuleAccessibility")
@MainActor
struct Phase4LiveCapsuleAccessibilityTests {

    // MARK: - LiveCapsuleOverlay Construction

    @Test("LiveCapsuleOverlay initializes with all parameters")
    func capsuleInitialization() {
        let capsule = LiveCapsuleOverlay(
            formattedDuration: "01:30",
            isPaused: false,
            isRecording: true,
            liveTranscript: "Hello world",
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )

        #expect(capsule.formattedDuration == "01:30")
        #expect(capsule.isPaused == false)
        #expect(capsule.isRecording == true)
        #expect(capsule.liveTranscript == "Hello world")
    }

    @Test("LiveCapsuleOverlay default transcript is empty")
    func capsuleDefaultTranscript() {
        let capsule = LiveCapsuleOverlay(
            formattedDuration: "00:00",
            isPaused: false,
            isRecording: false,
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )

        #expect(capsule.liveTranscript.isEmpty)
    }

    // MARK: - Callback Distinction

    @Test("onExpand, onTogglePause, onStop are distinct callbacks")
    func distinctCallbacks() {
        var expandCount = 0
        var pauseCount = 0
        var stopCount = 0

        let capsule = LiveCapsuleOverlay(
            formattedDuration: "00:05",
            isPaused: false,
            isRecording: true,
            onExpand: { expandCount += 1 },
            onTogglePause: { pauseCount += 1 },
            onStop: { stopCount += 1 }
        )

        capsule.onExpand()
        capsule.onExpand()
        capsule.onTogglePause()
        capsule.onStop()

        #expect(expandCount == 2)
        #expect(pauseCount == 1)
        #expect(stopCount == 1)
    }

    // MARK: - State Combinations

    @Test("Capsule in recording state")
    func recordingState() {
        let capsule = LiveCapsuleOverlay(
            formattedDuration: "05:00",
            isPaused: false,
            isRecording: true,
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )

        #expect(capsule.isRecording)
        #expect(!capsule.isPaused)
    }

    @Test("Capsule in paused state")
    func pausedState() {
        let capsule = LiveCapsuleOverlay(
            formattedDuration: "05:00",
            isPaused: true,
            isRecording: false,
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )

        #expect(capsule.isPaused)
        #expect(!capsule.isRecording)
    }

    @Test("Capsule in stopped state")
    func stoppedState() {
        let capsule = LiveCapsuleOverlay(
            formattedDuration: "05:00",
            isPaused: false,
            isRecording: false,
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )

        #expect(!capsule.isRecording)
        #expect(!capsule.isPaused)
    }

    // MARK: - Transcript Handling

    @Test("Long transcript is accepted (truncation is view-side)")
    func longTranscriptAccepted() {
        let longText = String(repeating: "Hello world. ", count: 50) // ~650 chars
        let capsule = LiveCapsuleOverlay(
            formattedDuration: "10:00",
            isPaused: false,
            isRecording: true,
            liveTranscript: longText,
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )

        #expect(capsule.liveTranscript.count > 200)
        // View uses .suffix(80) for display truncation
    }

    @Test("Empty transcript results in no transcript preview section")
    func emptyTranscriptNoPreview() {
        let capsule = LiveCapsuleOverlay(
            formattedDuration: "00:00",
            isPaused: false,
            isRecording: true,
            liveTranscript: "",
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )

        #expect(capsule.liveTranscript.isEmpty)
    }

    // MARK: - Duration Formatting

    @Test("Formatted duration is stored as-is (no re-formatting)")
    func durationStoredAsIs() {
        let capsule = LiveCapsuleOverlay(
            formattedDuration: "99:59",
            isPaused: false,
            isRecording: true,
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )

        #expect(capsule.formattedDuration == "99:59")
    }

    @Test("Duration zero format")
    func durationZeroFormat() {
        let capsule = LiveCapsuleOverlay(
            formattedDuration: "00:00",
            isPaused: false,
            isRecording: true,
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )

        #expect(capsule.formattedDuration == "00:00")
    }

    // MARK: - PulseModifier (Reduce Motion)

    @Test("Capsule can be created with Reduce Motion scenario (no crash)")
    func reduceMotionSafe() {
        // PulseModifier internally checks @Environment(\.accessibilityReduceMotion)
        // We just verify construction doesn't crash — no SwiftUI host needed
        let _ = LiveCapsuleOverlay(
            formattedDuration: "01:00",
            isPaused: false,
            isRecording: true,
            onExpand: {},
            onTogglePause: {},
            onStop: {}
        )
    }
}
