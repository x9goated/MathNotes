import Foundation
import CoreGraphics

enum PaperStyle: String, Codable, CaseIterable, Identifiable {
    case blank, lined, grid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blank: "Blanc"
        case .lined: "Lignes"
        case .grid: "Quadrillage"
        }
    }

    var symbolName: String {
        switch self {
        case .blank: "doc"
        case .lined: "text.justify"
        case .grid: "squareshape.split.3x3"
        }
    }
}

/// One handwritten line of a note, with its transcription.
struct MathLine: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case math, text
    }

    var id = UUID()
    /// Identifies the strokes of the line, so an unchanged line is never sent for recognition twice.
    var signature: String
    /// Position of the line on the canvas.
    var rect: CGRect
    var recognized = false
    var kind = Kind.math
    var latex = ""
    /// Plain calculator syntax ("2*x+3=7") used by the step checker.
    var expression = ""
    /// Set by the user: this line starts a new calculation.
    var startsNewBlock = false
}

struct Note: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var updatedAt = Date()
    /// PencilKit drawing, serialized with `PKDrawing.dataRepresentation()`.
    var drawingData = Data()
    var paper = PaperStyle.grid
    var lines: [MathLine] = []

    func matches(_ query: String) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || lines.contains { $0.latex.localizedCaseInsensitiveContains(query) }
    }
}

extension Note {
    // Notes saved by earlier versions of the app don't have `paper` and `lines`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        drawingData = try container.decode(Data.self, forKey: .drawingData)
        paper = try container.decodeIfPresent(PaperStyle.self, forKey: .paper) ?? .grid
        lines = try container.decodeIfPresent([MathLine].self, forKey: .lines) ?? []
    }
}
