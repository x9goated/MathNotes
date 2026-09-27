import SwiftUI
import PencilKit

/// PencilKit canvas for SwiftUI: Apple Pencil writes, fingers scroll.
struct CanvasView: UIViewRepresentable {
    let drawingData: Data
    let onDrawingChange: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChange: onDrawingChange)
    }

    func makeUIView(context: Context) -> NoteCanvasView {
        let canvas = NoteCanvasView()
        canvas.drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        // .default follows the system "Only Draw with Apple Pencil" setting
        // and the "Draw with Finger" toggle in the tool picker.
        canvas.drawingPolicy = .default
        canvas.backgroundColor = .systemBackground
        canvas.alwaysBounceVertical = true
        canvas.delegate = context.coordinator

        let toolPicker = context.coordinator.toolPicker
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        return canvas
    }

    func updateUIView(_ canvas: NoteCanvasView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        let onDrawingChange: (Data) -> Void

        init(onDrawingChange: @escaping (Data) -> Void) {
            self.onDrawingChange = onDrawingChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            (canvasView as? NoteCanvasView)?.growContentIfNeeded()
            onDrawingChange(canvasView.drawing.dataRepresentation())
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // Bring the tool picker back if something else took focus (e.g. renaming the note).
            if !canvasView.isFirstResponder {
                canvasView.becomeFirstResponder()
            }
        }
    }
}

/// A page that keeps growing downwards as you write.
final class NoteCanvasView: PKCanvasView {
    private var lastLayoutSize: CGSize = .zero

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // The tool picker is only shown while the canvas is first responder.
        if window != nil {
            becomeFirstResponder()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastLayoutSize {
            lastLayoutSize = bounds.size
            growContentIfNeeded()
        }
    }

    /// Keeps at least one empty screen below the lowest stroke.
    func growContentIfNeeded() {
        let drawingBottom = drawing.bounds.isNull ? 0 : drawing.bounds.maxY
        let height = max(bounds.height * 2, drawingBottom + bounds.height)
        contentSize = CGSize(width: bounds.width, height: height)
    }
}
