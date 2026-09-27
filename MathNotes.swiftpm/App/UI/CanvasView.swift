import SwiftUI
import PencilKit

/// A ✓ / ✗ badge shown next to a handwritten line.
struct LineMarker: Equatable {
    enum State {
        case pending, valid, invalid, unreadable

        var symbolName: String {
            switch self {
            case .pending: "ellipsis.circle"
            case .valid: "checkmark.circle.fill"
            case .invalid: "xmark.circle.fill"
            case .unreadable: "questionmark.circle"
            }
        }

        var color: UIColor {
            switch self {
            case .pending, .unreadable: .secondaryLabel
            case .valid: .systemGreen
            case .invalid: .systemRed
            }
        }
    }

    let id: UUID
    let rect: CGRect
    let state: State
}

/// PencilKit canvas for SwiftUI: Apple Pencil writes, fingers scroll.
struct CanvasView: UIViewRepresentable {
    let drawingData: Data
    let paper: PaperStyle
    let markers: [LineMarker]
    let onDrawingChange: (PKDrawing) -> Void
    let onMarkerTap: (UUID) -> Void

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
        updateUIView(canvas, context: context)
        return canvas
    }

    func updateUIView(_ canvas: NoteCanvasView, context: Context) {
        context.coordinator.onDrawingChange = onDrawingChange
        canvas.onMarkerTap = onMarkerTap
        canvas.paper = paper
        canvas.showMarkers(markers)
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        var onDrawingChange: (PKDrawing) -> Void

        init(onDrawingChange: @escaping (PKDrawing) -> Void) {
            self.onDrawingChange = onDrawingChange
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            (canvasView as? NoteCanvasView)?.growContentIfNeeded()
            onDrawingChange(canvasView.drawing)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            // Bring the tool picker back if something else took focus (e.g. renaming the note).
            if !canvasView.isFirstResponder {
                canvasView.becomeFirstResponder()
            }
        }
    }
}

/// A page that keeps growing downwards as you write, on blank, lined or grid paper.
final class NoteCanvasView: PKCanvasView {
    var onMarkerTap: ((UUID) -> Void)?

    var paper = PaperStyle.blank {
        didSet {
            if paper != oldValue { paperView.backgroundColor = Self.pattern(for: paper) }
        }
    }

    private let paperView = UIView()
    private var lastLayoutSize: CGSize = .zero
    private var markers: [LineMarker] = []
    private var markerButtons: [UUID: UIButton] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        paperView.isUserInteractionEnabled = false
        paperView.backgroundColor = Self.pattern(for: paper)
        insertSubview(paperView, at: 0)
    }

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
            layoutMarkers()
        }
    }

    /// Keeps at least one empty screen below the lowest stroke.
    func growContentIfNeeded() {
        let drawingBottom = drawing.bounds.isNull ? 0 : drawing.bounds.maxY
        let height = max(bounds.height * 2, drawingBottom + bounds.height)
        contentSize = CGSize(width: bounds.width, height: height)
        paperView.frame = CGRect(origin: .zero, size: contentSize)
        sendSubviewToBack(paperView)
    }

    // MARK: Markers

    func showMarkers(_ newMarkers: [LineMarker]) {
        guard newMarkers != markers else { return }
        markers = newMarkers
        let ids = Set(newMarkers.map(\.id))
        for (id, button) in markerButtons where !ids.contains(id) {
            button.removeFromSuperview()
            markerButtons[id] = nil
        }
        layoutMarkers()
    }

    private func layoutMarkers() {
        let configuration = UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        for marker in markers {
            let button = markerButtons[marker.id] ?? makeMarkerButton(for: marker.id)
            button.setImage(UIImage(systemName: marker.state.symbolName, withConfiguration: configuration), for: .normal)
            button.tintColor = marker.state.color
            let x = min(marker.rect.maxX + 10, bounds.width - 40)
            button.frame = CGRect(x: x, y: marker.rect.midY - 16, width: 32, height: 32)
        }
    }

    private func makeMarkerButton(for id: UUID) -> UIButton {
        let button = UIButton(type: .system)
        button.addAction(UIAction { [weak self] _ in self?.onMarkerTap?(id) }, for: .primaryActionTriggered)
        addSubview(button)
        markerButtons[id] = button
        return button
    }

    // MARK: Paper

    private static func pattern(for style: PaperStyle) -> UIColor {
        guard style != .blank else { return .clear }
        let spacing: CGFloat = style == .grid ? 32 : 40
        let size = CGSize(width: spacing, height: spacing)
        let tile = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemGray.withAlphaComponent(0.25).setFill()
            context.fill(CGRect(x: 0, y: spacing - 1, width: spacing, height: 1))
            if style == .grid {
                context.fill(CGRect(x: spacing - 1, y: 0, width: 1, height: spacing))
            }
        }
        return UIColor(patternImage: tile)
    }
}
