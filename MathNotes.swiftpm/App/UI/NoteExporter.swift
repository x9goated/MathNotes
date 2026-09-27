import PencilKit
import SwiftUI

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, png, svg, latex

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdf: "PDF"
        case .png: "Image PNG"
        case .svg: "Image SVG"
        case .latex: "LaTeX (.tex)"
        }
    }

    var fileExtension: String {
        self == .latex ? "tex" : rawValue
    }
}

enum ExportError: LocalizedError {
    case emptyNote

    var errorDescription: String? {
        "Cette note est vide."
    }
}

/// Writes a note to a temporary file in the requested format.
@MainActor
enum NoteExporter {
    static func export(_ note: Note, as format: ExportFormat) throws -> URL {
        let drawing = (try? PKDrawing(data: note.drawingData)) ?? PKDrawing()
        let data: Data
        switch format {
        case .pdf: data = try pdf(of: drawing)
        case .png: data = try png(of: drawing)
        case .svg: data = try svg(of: drawing)
        case .latex: data = Data(latex(of: note).utf8)
        }
        let name = note.title.components(separatedBy: CharacterSet(charactersIn: "/\\:?*\"<>|")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name.isEmpty ? "Note" : name)
            .appendingPathExtension(format.fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// The written area of the note, starting at the top-left of the page.
    private static func pageArea(of drawing: PKDrawing) throws -> CGRect {
        let bounds = drawing.bounds
        guard !bounds.isNull, !bounds.isEmpty else { throw ExportError.emptyNote }
        return CGRect(x: 0, y: 0, width: max(bounds.maxX + 40, 600), height: bounds.maxY + 40)
    }

    private static func lightImage(of drawing: PKDrawing, in rect: CGRect, scale: CGFloat) -> UIImage {
        var image = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: rect, scale: scale)
        }
        return image
    }

    private static func png(of drawing: PKDrawing) throws -> Data {
        let area = try pageArea(of: drawing)
        let ink = lightImage(of: drawing, in: area, scale: 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: area.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: area.size))
            ink.draw(at: .zero)
        }
        guard let data = image.pngData() else { throw ExportError.emptyNote }
        return data
    }

    /// A4 pages, the note scaled to the page width.
    private static func pdf(of drawing: PKDrawing) throws -> Data {
        let area = try pageArea(of: drawing)
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let scale = page.width / area.width
        let sliceHeight = page.height / scale
        let pageCount = max(1, Int((area.height / sliceHeight).rounded(.up)))

        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            for index in 0..<pageCount {
                context.beginPage()
                let slice = CGRect(x: 0, y: CGFloat(index) * sliceHeight, width: area.width, height: sliceHeight)
                lightImage(of: drawing, in: slice, scale: 2).draw(in: page)
            }
        }
    }

    private static func svg(of drawing: PKDrawing) throws -> Data {
        let area = try pageArea(of: drawing)
        let light = UITraitCollection(userInterfaceStyle: .light)
        var svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(Int(area.width))" height="\(Int(area.height))" \
        viewBox="0 0 \(Int(area.width)) \(Int(area.height))">
        <rect width="100%" height="100%" fill="white"/>

        """
        for stroke in drawing.strokes {
            let points = stroke.path.interpolatedPoints(by: .distance(2)).map { $0.location.applying(stroke.transform) }
            guard !points.isEmpty else { continue }
            let widths = stroke.path.map { $0.size.width }
            let width = widths.reduce(0, +) / CGFloat(max(widths.count, 1))

            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
            stroke.ink.color.resolvedColor(with: light).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let color = String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
            let opacity = stroke.ink.inkType == .marker ? min(alpha, 0.4) : alpha

            let coordinates = points.map { String(format: "%.1f,%.1f", $0.x, $0.y) }.joined(separator: " ")
            svg += "<polyline points=\"\(coordinates)\" fill=\"none\" stroke=\"\(color)\" "
            svg += "stroke-opacity=\"\(String(format: "%.2f", opacity))\" stroke-width=\"\(String(format: "%.1f", width))\" "
            svg += "stroke-linecap=\"round\" stroke-linejoin=\"round\"/>\n"
        }
        svg += "</svg>\n"
        return Data(svg.utf8)
    }

    private static func latex(of note: Note) -> String {
        var body = ""
        for line in note.lines where line.recognized {
            switch line.kind {
            case .math: body += "\\[ \(line.latex) \\]\n\n"
            case .text: body += "\(line.latex)\n\n"
            }
        }
        return """
        \\documentclass{article}
        \\usepackage[utf8]{inputenc}
        \\usepackage[T1]{fontenc}
        \\usepackage{amsmath,amssymb}

        \\begin{document}

        \\section*{\(note.title)}

        \(body)\\end{document}

        """
    }
}

/// Presents the system share sheet for a file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ExportedFile: Identifiable {
    let url: URL
    var id: URL { url }
}
