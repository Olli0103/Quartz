import SwiftUI

#if canImport(AppKit)
import AppKit

final class RetinaSnapshotWindow: NSWindow {
    override var backingScaleFactor: CGFloat { 2 }
}

@MainActor
func makeRetinaSnapshotImage<Content: View>(
    rootView: Content,
    colorScheme: ColorScheme,
    canvasSize: CGSize
) -> NSImage {
    let scale: CGFloat = 2
    let hostingView = NSHostingView(rootView: rootView)
    let container = NSView(frame: NSRect(origin: .zero, size: canvasSize))
    let window = RetinaSnapshotWindow(
        contentRect: NSRect(origin: .zero, size: canvasSize),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )

    hostingView.appearance = NSAppearance(
        named: colorScheme == .dark ? .darkAqua : .aqua
    )
    hostingView.frame = container.bounds
    hostingView.wantsLayer = true
    hostingView.layer?.contentsScale = scale

    container.wantsLayer = true
    container.layer?.contentsScale = scale
    container.addSubview(hostingView)
    window.contentView = container
    window.displayIfNeeded()
    container.layoutSubtreeIfNeeded()
    hostingView.layoutSubtreeIfNeeded()

    let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(canvasSize.width * scale),
        pixelsHigh: Int(canvasSize.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmapRep.size = canvasSize

    let context = NSGraphicsContext(bitmapImageRep: bitmapRep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    container.cacheDisplay(in: container.bounds, to: bitmapRep)
    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: canvasSize)
    image.addRepresentation(bitmapRep)
    return image
}
#endif
