import PencilKit
import SwiftUI

/// Splits a note's handwriting into lines, has Claude transcribe new lines, and checks each step.
@MainActor
@Observable
final class NoteAnalyzer {
    private(set) var verdicts: [MathLine.ID: StepVerdict] = [:]
    private(set) var isAnalyzing = false
    var errorMessage: String?

    private let noteID: Note.ID
    private let store: NoteStore
    @ObservationIgnored private var pendingAnalysis: Task<Void, Never>?
    @ObservationIgnored private var latestDrawing: PKDrawing?
    @ObservationIgnored private var needsAnotherPass = false

    init(noteID: Note.ID, store: NoteStore) {
        self.noteID = noteID
        self.store = store
    }

    var lines: [MathLine] {
        store.note(id: noteID)?.lines ?? []
    }

    static var hasAPIKey: Bool {
        Keychain.read(Keychain.apiKeyAccount) != nil
    }

    private var autoAnalyze: Bool {
        UserDefaults.standard.object(forKey: "autoAnalyze") as? Bool ?? true
    }

    /// Called after each stroke: analyzes once the pen has rested for a moment.
    func drawingDidChange(_ drawing: PKDrawing) {
        latestDrawing = drawing
        pendingAnalysis?.cancel()
        guard autoAnalyze else { return }
        pendingAnalysis = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.analyze()
        }
    }

    func analyzeNow() {
        pendingAnalysis?.cancel()
        Task { await analyze() }
    }

    func toggleNewBlock(_ lineID: MathLine.ID) {
        store.update(noteID) { note in
            guard let index = note.lines.firstIndex(where: { $0.id == lineID }) else { return }
            note.lines[index].startsNewBlock.toggle()
        }
        refreshVerdicts()
    }

    /// Lets the user fix a transcription by hand.
    func correct(_ lineID: MathLine.ID, kind: MathLine.Kind, latex: String, expression: String) {
        store.update(noteID) { note in
            guard let index = note.lines.firstIndex(where: { $0.id == lineID }) else { return }
            note.lines[index].recognized = true
            note.lines[index].kind = kind
            note.lines[index].latex = latex
            note.lines[index].expression = expression
        }
        refreshVerdicts()
    }

    func refreshVerdicts() {
        let lines = self.lines
        let checks = lines.map { line in
            CheckLine(
                expression: line.recognized && line.kind == .math ? line.expression : nil,
                top: Double(line.rect.minY),
                bottom: Double(line.rect.maxY),
                startsNewBlock: line.startsNewBlock
            )
        }
        verdicts = Dictionary(uniqueKeysWithValues: zip(lines.map(\.id), StepChecker.verdicts(for: checks)))
    }

    // MARK: Analysis

    private func analyze() async {
        guard !isAnalyzing else {
            needsAnotherPass = true
            return
        }
        let drawing: PKDrawing
        if let latestDrawing {
            drawing = latestDrawing
        } else {
            let data = store.note(id: noteID)?.drawingData ?? Data()
            drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
        }

        var lines = segment(drawing)
        store.updateLines(lines, for: noteID)
        refreshVerdicts()

        let toRecognize = lines.indices.filter { !lines[$0].recognized }
        guard !toRecognize.isEmpty else { return }
        guard let apiKey = Keychain.read(Keychain.apiKeyAccount) else {
            errorMessage = "Ajoute ta clé API Claude dans les Réglages pour reconnaître ton écriture."
            return
        }

        isAnalyzing = true
        do {
            // A few lines per request keeps each request small.
            for start in stride(from: 0, to: toRecognize.count, by: 10) {
                let batch = Array(toRecognize[start..<min(start + 10, toRecognize.count)])
                let images = batch.compactMap { Self.image(of: drawing, strokesOf: lines[$0]) }
                guard images.count == batch.count else { continue }
                let results = try await ClaudeClient(apiKey: apiKey).recognize(lineImages: images)
                for (index, result) in zip(batch, results) {
                    lines[index].recognized = true
                    lines[index].kind = result.kind == "text" ? .text : .math
                    lines[index].latex = result.latex
                    lines[index].expression = result.expression
                }
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isAnalyzing = false

        // The drawing may have changed during the request: only fill in lines that still exist.
        let transcribed = Dictionary(lines.filter(\.recognized).map { ($0.signature, $0) }, uniquingKeysWith: { first, _ in first })
        store.update(noteID) { note in
            for index in note.lines.indices where !note.lines[index].recognized {
                guard let result = transcribed[note.lines[index].signature] else { continue }
                note.lines[index].recognized = true
                note.lines[index].kind = result.kind
                note.lines[index].latex = result.latex
                note.lines[index].expression = result.expression
            }
        }
        refreshVerdicts()

        if needsAnotherPass {
            needsAnotherPass = false
            await analyze()
        }
    }

    /// Groups strokes into lines, reusing the transcription of lines that didn't change.
    private func segment(_ drawing: PKDrawing) -> [MathLine] {
        let strokes = drawing.strokes
        let existing = Dictionary(lines.map { ($0.signature, $0) }, uniquingKeysWith: { first, _ in first })
        return LineSegmenter.group(strokes.map(\.renderBounds)).map { group in
            let lineStrokes = group.map { strokes[$0] }
            let rect = lineStrokes.map(\.renderBounds).reduce(CGRect.null) { $0.union($1) }
            let signature = Self.signature(of: lineStrokes)
            var line = existing[signature] ?? MathLine(signature: signature, rect: rect)
            line.rect = rect
            return line
        }
    }

    private static func signature(of strokes: [PKStroke]) -> String {
        var text = ""
        for stroke in strokes {
            let bounds = stroke.renderBounds
            text += "\(Int(bounds.minX.rounded())),\(Int(bounds.minY.rounded())),"
            text += "\(Int(bounds.width.rounded())),\(Int(bounds.height.rounded())),\(stroke.path.count);"
        }
        // FNV-1a: stable across launches, unlike Swift's Hasher.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// Renders one line's ink in black on white, the way Claude sees it.
    private static func image(of drawing: PKDrawing, strokesOf line: MathLine) -> Data? {
        let area = line.rect.insetBy(dx: -12, dy: -12)
        guard area.width > 0, area.height > 0 else { return nil }
        let lineStrokes = drawing.strokes.filter { area.contains($0.renderBounds) }
        let scale = min(2, 1600 / area.width)

        var ink: UIImage?
        // Light appearance so black ink doesn't turn white in dark mode.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = PKDrawing(strokes: lineStrokes).image(from: area, scale: scale)
        }
        guard let ink else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: area.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: area.size))
            ink.draw(at: .zero)
        }
        return image.pngData()
    }
}
