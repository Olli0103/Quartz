#if os(iOS)
import SwiftUI
import VisionKit

/// Holder for closures that must be invoked on main; marked @unchecked Sendable for DispatchQueue.main.async.
private final class DocumentScannerClosureHolder: @unchecked Sendable {
    let onScanComplete: ([UIImage]) -> Void
    let dismiss: () -> Void
    init(onScanComplete: @escaping ([UIImage]) -> Void, dismiss: @escaping () -> Void) {
        self.onScanComplete = onScanComplete
        self.dismiss = dismiss
    }
}

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
        let onComplete = onScanComplete
        let binding = _isPresented
        return Coordinator(onScanComplete: onComplete, dismiss: { binding.wrappedValue = false })
    }

    public class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onScanComplete: ([UIImage]) -> Void
        let dismiss: () -> Void

        init(onScanComplete: @escaping ([UIImage]) -> Void, dismiss: @escaping () -> Void) {
            self.onScanComplete = onScanComplete
            self.dismiss = dismiss
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            let holder = DocumentScannerClosureHolder(onScanComplete: onScanComplete, dismiss: dismiss)
            DispatchQueue.main.async {
                holder.onScanComplete(images)
                holder.dismiss()
            }
        }

        public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            let holder = DocumentScannerClosureHolder(onScanComplete: { _ in }, dismiss: dismiss)
            DispatchQueue.main.async {
                holder.dismiss()
            }
        }

        public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            let holder = DocumentScannerClosureHolder(onScanComplete: { _ in }, dismiss: dismiss)
            DispatchQueue.main.async {
                holder.dismiss()
            }
        }
    }
}
#endif
