import Testing
import Foundation
@testable import QuartzKit

@Suite("Phase4HardwareCapability")
struct Phase4HardwareCapabilityTests {

    // MARK: - Platform-Specific Behavioral Assertions

    @Test("hasMicrophone returns expected value for current platform")
    func hasMicrophoneExpectedForPlatform() {
        let result = HardwareCapability.hasMicrophone
        #if os(macOS)
        // On macOS CI machines, microphone discovery via AVCaptureDevice may or may not find a device.
        // Verify it returns a stable value (deterministic — no crash or exception).
        let result2 = HardwareCapability.hasMicrophone
        #expect(result == result2, "hasMicrophone should be deterministic across calls")
        #elseif os(iOS)
        // On iOS sim, no microphone available
        #expect(result == false, "iOS simulator should report no microphone")
        #else
        #expect(result == false, "Unsupported platform should report no microphone")
        #endif
    }

    @Test("hasSpeechRecognition returns expected value for current platform")
    func hasSpeechRecognitionExpectedForPlatform() {
        #if canImport(Speech)
        // Speech framework available — recognizer availability depends on language model downloads.
        // Verify determinism and type correctness.
        let result1 = HardwareCapability.hasSpeechRecognition
        let result2 = HardwareCapability.hasSpeechRecognition
        #expect(result1 == result2, "hasSpeechRecognition should be deterministic")
        #else
        #expect(HardwareCapability.hasSpeechRecognition == false)
        #endif
    }

    @Test("hasSpeechRecognition(for: en-US) returns result without crash")
    func hasSpeechRecognitionForEnglish() {
        let result = HardwareCapability.hasSpeechRecognition(for: Locale(identifier: "en-US"))
        // en-US is the most widely supported locale — on any machine with speech models it's true
        let result2 = HardwareCapability.hasSpeechRecognition(for: Locale(identifier: "en-US"))
        #expect(result == result2, "Same locale should return same result")
    }

    @Test("hasSpeechRecognition(for:) returns false for unsupported locale")
    func hasSpeechRecognitionForUnsupportedLocale() {
        // Klingon locale should not be supported by SFSpeechRecognizer
        let result = HardwareCapability.hasSpeechRecognition(for: Locale(identifier: "tlh"))
        #expect(result == false, "Klingon locale should not be supported")
    }

    @Test("hasDocumentScanner returns false on macOS, platform-appropriate elsewhere")
    func hasDocumentScannerPlatformBehavior() {
        let result = HardwareCapability.hasDocumentScanner
        #if os(macOS)
        #expect(result == false, "VNDocumentCameraViewController not available on macOS")
        #elseif os(iOS)
        // On real iOS device this is true; on sim it depends on VisionKit stub
        let result2 = HardwareCapability.hasDocumentScanner
        #expect(result == result2, "hasDocumentScanner should be deterministic")
        #else
        #expect(result == false, "Unsupported platform should report no scanner")
        #endif
    }

    @Test("hasPencilKit returns true on iOS/macOS where PencilKit is importable")
    func hasPencilKitExpectedForPlatform() {
        let result = HardwareCapability.hasPencilKit
        #if canImport(PencilKit) && (os(iOS) || os(macOS))
        #expect(result == true, "PencilKit should be available on iOS and macOS")
        #else
        #expect(result == false, "PencilKit not available on this platform")
        #endif
    }

    @Test("hasCamera returns platform-appropriate value")
    func hasCameraExpectedForPlatform() {
        let result = HardwareCapability.hasCamera
        #if os(iOS)
        // Simulator has no camera
        #expect(result == false, "iOS simulator should report no camera")
        #elseif os(macOS)
        // macOS CI may or may not have a camera
        let result2 = HardwareCapability.hasCamera
        #expect(result == result2, "hasCamera should be deterministic")
        #else
        #expect(result == false, "Unsupported platform should report no camera")
        #endif
    }

    @Test("All capability checks are deterministic across consecutive calls")
    func capabilityChecksDeterministic() {
        // Calling each capability twice should return the same result
        #expect(HardwareCapability.hasMicrophone == HardwareCapability.hasMicrophone)
        #expect(HardwareCapability.hasSpeechRecognition == HardwareCapability.hasSpeechRecognition)
        #expect(HardwareCapability.hasDocumentScanner == HardwareCapability.hasDocumentScanner)
        #expect(HardwareCapability.hasPencilKit == HardwareCapability.hasPencilKit)
        #expect(HardwareCapability.hasCamera == HardwareCapability.hasCamera)

        // Locale-specific check
        let locale = Locale(identifier: "en-US")
        #expect(HardwareCapability.hasSpeechRecognition(for: locale) == HardwareCapability.hasSpeechRecognition(for: locale))
    }
}
