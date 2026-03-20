import SwiftUI

#if os(iOS)
import QuickLook
import UIKit

extension View {
    /// Presents system Quick Look when `item` is non-nil (e.g. after export). Set to `nil` to dismiss.
    public func quartzQuickLookPreview(_ item: Binding<URL?>) -> some View {
        fullScreenCover(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            onDismiss: { item.wrappedValue = nil }
        ) {
            if let url = item.wrappedValue {
                QuickLookPreviewControllerRepresentable(url: url)
                    .ignoresSafeArea()
            }
        }
    }
}

private struct QuickLookPreviewControllerRepresentable: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        context.coordinator.url = url
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL?

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            url == nil ? 0 : 1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url! as NSURL
        }
    }
}

#elseif os(macOS)
import AppKit
import QuickLookUI

extension View {
    /// Presents system Quick Look when `item` is non-nil (e.g. after export). Set to `nil` to dismiss.
    public func quartzQuickLookPreview(_ item: Binding<URL?>) -> some View {
        sheet(
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            )
        ) {
            if let url = item.wrappedValue {
                QuickLookPreviewPanelRepresentable(url: url) {
                    item.wrappedValue = nil
                }
                .frame(minWidth: 480, minHeight: 360)
            }
        }
    }
}

private struct QuickLookPreviewPanelRepresentable: NSViewRepresentable {
    let url: URL
    let onDismiss: () -> Void

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero)!
        view.autoresizingMask = [.width, .height]
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as QLPreviewItem
    }
}

#else
extension View {
    /// Quick Look is unavailable on this platform (e.g. visionOS); no-op.
    public func quartzQuickLookPreview(_ item: Binding<URL?>) -> some View {
        self
    }
}
#endif
