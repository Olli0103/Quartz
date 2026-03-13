#if canImport(PencilKit) && canImport(UIKit)
import SwiftUI
import PencilKit

/// SwiftUI Wrapper für `PKCanvasView` – eingebettet als Block im Markdown-Editor.
///
/// Unterstützt Apple Pencil und Finger-Zeichnen.
/// Die Zeichnung wird als `PKDrawing` zurückgegeben.
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

/// Ein Zeichnungs-Block der inline zwischen Text-Paragraphen im Editor erscheint.
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
                Text("Drawing")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                if isEditing {
                    Button("Done") {
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

/// Rendert eine PKDrawing als statisches Bild.
struct DrawingThumbnailView: View {
    let drawing: PKDrawing

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
                            Text("Tap to draw")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                    }
                    Spacer()
                }
            } else {
                let scale = UITraitCollection.current.displayScale
                let image = drawing.image(
                    from: drawing.bounds,
                    scale: scale
                )
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(.background)
    }
}
#endif
