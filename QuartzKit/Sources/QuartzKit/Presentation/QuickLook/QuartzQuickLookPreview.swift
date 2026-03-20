import SwiftUI

#if os(iOS) || os(macOS)
import QuickLook

extension View {
    /// Presents system Quick Look when `item` is non-nil (e.g. after export). Set to `nil` to dismiss.
    public func quartzQuickLookPreview(_ item: Binding<URL?>) -> some View {
        quickLookPreview(item)
    }
}
#else
extension View {
    /// Quick Look is unavailable on this platform; no-op.
    public func quartzQuickLookPreview(_ item: Binding<URL?>) -> some View {
        self
    }
}
#endif
