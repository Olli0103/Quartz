#if os(iOS)
import SwiftUI
import VisionKit

/// Presents the document scanner. Returns scanned images.
public struct DocumentScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onScanComplete: ([UIImage]) -> Void

    public init(isPresented: Binding<Bool>, onScanComplete: @escaping ([UIImage]) -> Void) {
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
        Coordinator(self)
    }

    public class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(_ parent: DocumentScannerView) {
            self.parent = parent
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            parent.onScanComplete(images)
            parent.isPresented = false
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.isPresented = false
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.isPresented = false
        }
    }
}
#endif
