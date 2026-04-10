import Testing
import Foundation
@testable import QuartzKit

@Suite("Phase4HardwareCapability")
struct Phase4HardwareCapabilityTests {

    @Test("HardwareCapability.hasMicrophone returns Bool without crash")
    func hasMicrophoneReturns() {
        let result = HardwareCapability.hasMicrophone
        // On CI (macOS) this may be true or false depending on hardware;
        // we just verify it doesn't crash and returns a Bool.
        #expect(result == true || result == false)
    }

    @Test("HardwareCapability.hasSpeechRecognition returns Bool without crash")
    func hasSpeechRecognitionReturns() {
        let result = HardwareCapability.hasSpeechRecognition
        #expect(result == true || result == false)
    }

    @Test("HardwareCapability.hasSpeechRecognition(for:) with English locale")
    func hasSpeechRecognitionForEnglish() {
        let result = HardwareCapability.hasSpeechRecognition(for: Locale(identifier: "en-US"))
        #expect(result == true || result == false)
    }

    @Test("HardwareCapability.hasSpeechRecognition(for:) with exotic locale returns false")
    func hasSpeechRecognitionForExotic() {
        // Klingon locale should not be supported
        let result = HardwareCapability.hasSpeechRecognition(for: Locale(identifier: "tlh"))
        #expect(result == false)
    }

    @Test("HardwareCapability.hasDocumentScanner returns Bool on this platform")
    func hasDocumentScannerReturns() {
        let result = HardwareCapability.hasDocumentScanner
        #if os(macOS)
        // VNDocumentCameraViewController not available on macOS
        #expect(result == false)
        #else
        #expect(result == true || result == false)
        #endif
    }

    @Test("HardwareCapability.hasPencilKit returns true on iOS/macOS")
    func hasPencilKitReturns() {
        let result = HardwareCapability.hasPencilKit
        #if os(iOS) || os(macOS)
        #expect(result == true)
        #else
        #expect(result == false)
        #endif
    }

    @Test("HardwareCapability.hasCamera returns Bool without crash")
    func hasCameraReturns() {
        let result = HardwareCapability.hasCamera
        #expect(result == true || result == false)
    }

    @Test("All capability checks are deterministic across calls")
    func capabilityChecksDeterministic() {
        let mic1 = HardwareCapability.hasMicrophone
        let mic2 = HardwareCapability.hasMicrophone
        #expect(mic1 == mic2)

        let pencil1 = HardwareCapability.hasPencilKit
        let pencil2 = HardwareCapability.hasPencilKit
        #expect(pencil1 == pencil2)
    }
}
