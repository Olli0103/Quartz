#if os(iOS)
import SwiftUI
import VisionKit

/// Presents the document scanner. Returns scanned images.
public struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onScanComplete: @MainActor @Sendable ([UIImage]) -> Void

    public init(
        isPresented: Binding<Bool>,
        onScanComplete: @escaping @MainActor @Sendable ([UIImage]) -> Void
    ) {
        self._isPresented = isPresented
        self.onScanComplete = onScanComplete
    }

    public func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    public func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    public func makeCoordinator() -> Coordinator {
        let onComplete = onScanComplete
        let binding = _isPresented
        return Coordinator(onScanComplete: onComplete, dismiss: { @MainActor in
            binding.wrappedValue = false
        })
    }

    public class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanComplete: @MainActor @Sendable ([UIImage]) -> Void
        let dismiss: @MainActor @Sendable () -> Void

        init(
            onScanComplete: @escaping @MainActor @Sendable ([UIImage]) -> Void,
            dismiss: @escaping @MainActor @Sendable () -> Void
        ) {
            self.onScanComplete = onScanComplete
            self.dismiss = dismiss
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            let onScanComplete = onScanComplete
            let dismiss = dismiss
            Task { @MainActor in
                onScanComplete(images)
                dismiss()
            }
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            let dismiss = dismiss
            Task { @MainActor in
                dismiss()
            }
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            let dismiss = dismiss
            Task { @MainActor in
                dismiss()
            }
        }
    }
}
#endif
