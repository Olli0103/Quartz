import Foundation
import AVFoundation
#if canImport(Speech)
import Speech
#endif
#if canImport(VisionKit) && canImport(UIKit)
import VisionKit
#endif

/// Hardware capability checks for gating audio/scan UI features.
///
/// Each check is safe to call on any platform — returns false when
/// the capability is unavailable.
///
/// - Linear: OLL-61 (Hardware capability gating tests)
public enum HardwareCapability {

    /// Whether a microphone is available for recording.
    public static var hasMicrophone: Bool {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        return !(session.availableInputs?.isEmpty ?? true)
        #elseif os(macOS)
        return !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices.isEmpty
        #else
        return false
        #endif
    }

    /// Whether speech recognition is available for any locale.
    public static var hasSpeechRecognition: Bool {
        #if canImport(Speech)
        return SFSpeechRecognizer()?.isAvailable ?? false
        #else
        return false
        #endif
    }

    /// Whether speech recognition is available for a specific locale.
    public static func hasSpeechRecognition(for locale: Locale) -> Bool {
        #if canImport(Speech)
        return SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
        #else
        return false
        #endif
    }

    /// Whether the device supports VisionKit document scanning.
    public static var hasDocumentScanner: Bool {
        #if canImport(VisionKit) && os(iOS)
        return VNDocumentCameraViewController.isSupported
        #else
        return false
        #endif
    }

    /// Whether PencilKit is available on this platform.
    public static var hasPencilKit: Bool {
        #if canImport(PencilKit) && (os(iOS) || os(macOS))
        return true
        #else
        return false
        #endif
    }

    /// Whether a camera is available.
    public static var hasCamera: Bool {
        #if os(iOS)
        return UIImagePickerController.isSourceTypeAvailable(.camera)
        #elseif os(macOS)
        return !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices.isEmpty
        #else
        return false
        #endif
    }
}
