#if canImport(PencilKit) && canImport(UIKit)
import SwiftUI
import PencilKit

/// SwiftUI wrapper for `PKCanvasView` – embedded as a block in the Markdown editor.
///
/// Supports Apple Pencil and finger drawing.
/// The drawing is returned as a `PKDrawing`.
public struct DrawingCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var isToolPickerVisible: Bool
    let onDrawingChanged: ((PKDrawing) -> Void)?

    public init(
        drawing: Binding<PKDrawing>,
        isToolPickerVisible: Binding<Bool> = .constant(true),
        onDrawingChanged: ((PKDrawing) -> Void)? = nil
    ) {
        self._drawing = drawing
        self._isToolPickerVisible = isToolPickerVisible
        self.onDrawingChanged = onDrawingChanged
    }

    public func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.minimumZoomScale = 1.0
        canvas.maximumZoomScale = 3.0

        // Tool Picker
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        context.coordinator.toolPicker = toolPicker

        if isToolPickerVisible {
            canvas.becomeFirstResponder()
        }

        return canvas
    }

    public func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }

        if let toolPicker = context.coordinator.toolPicker {
            toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvas)
            if isToolPickerVisible {
                canvas.becomeFirstResponder()
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: DrawingCanvasView
        var toolPicker: PKToolPicker?

        init(_ parent: DrawingCanvasView) {
            self.parent = parent
        }

        public func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
            parent.onDrawingChanged?(canvasView.drawing)
        }
    }
}

// MARK: - Drawing Block View

/// A drawing block that appears inline between text paragraphs in the editor.
public struct DrawingBlockView: View {
    @State private var drawing: PKDrawing
    @State private var isEditing: Bool = false
    @State private var showToolPicker: Bool = false

    let drawingID: String
    let initialDrawing: PKDrawing
    let height: CGFloat
    let onSave: (PKDrawing) -> Void

    public init(
        drawingID: String,
        initialDrawing: PKDrawing = PKDrawing(),
        height: CGFloat = 300,
        onSave: @escaping (PKDrawing) -> Void
    ) {
        self.drawingID = drawingID
        self._drawing = State(initialValue: initialDrawing)
        self.initialDrawing = initialDrawing
        self.height = height
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Image(systemName: "pencil.tip.crop.circle")
                    .foregroundStyle(.secondary)
                Text(String(localized: "Drawing", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                if isEditing {
                    Button(String(localized: "Done", bundle: .module)) {
                        isEditing = false
                        showToolPicker = false
                        onSave(drawing)
                    }
                    .font(.caption.bold())
                } else {
                    Button {
                        isEditing = true
                        showToolPicker = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .accessibilityLabel(String(localized: "Edit drawing", bundle: .module))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.fill.quaternary)

            // Canvas
            if isEditing {
                DrawingCanvasView(
                    drawing: $drawing,
                    isToolPickerVisible: $showToolPicker
                )
                .frame(height: height)
            } else {
                // Static rendering
                DrawingThumbnailView(drawing: drawing)
                    .frame(height: height)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                        showToolPicker = true
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Drawing Thumbnail

/// Renders a PKDrawing as a static image (async, off-main-thread).
struct DrawingThumbnailView: View {
    let drawing: PKDrawing
    @State private var renderedImage: UIImage?

    var body: some View {
        GeometryReader { geometry in
            if drawing.bounds.isEmpty {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "hand.draw")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text(String(localized: "Tap to draw", bundle: .module))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    Spacer()
                }
            } else if let renderedImage {
                Image(uiImage: renderedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                ProgressView()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(.background)
        .task(id: drawing.bounds) {
            guard !drawing.bounds.isEmpty else { return }
            let drawingCopy = drawing
            let img = await Task.detached(priority: .userInitiated) {
                drawingCopy.image(from: drawingCopy.bounds, scale: 2.0)
            }.value
            renderedImage = img
        }
    }
}
#else

import SwiftUI

/// Fallback view for platforms without PencilKit (macOS).
///
/// Shows an informative placeholder explaining that drawing
/// is only available on iPad with Apple Pencil.
/// Init signature matches the iOS version for cross-platform call-site compatibility.
public struct DrawingBlockView: View {
    let drawingID: String
    let height: CGFloat
    // onSave is accepted but unused on macOS – keeps the API surface identical.
    private let onSave: ((Data) -> Void)?

    public init(
        drawingID: String,
        initialDrawing: Data? = nil,
        height: CGFloat = 300,
        onSave: ((Data) -> Void)? = nil
    ) {
        self.drawingID = drawingID
        self.height = height
        self.onSave = onSave
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "pencil.tip.crop.circle")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text(String(localized: "Drawing", bundle: .module))
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            Text(String(localized: "Drawing is available on iPad with Apple Pencil.", bundle: .module))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.fill.quaternary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
    }
}

#endif
