import CoreGraphics

/// Splits handwriting into lines from the strokes' bounding boxes.
enum LineSegmenter {
    /// Groups stroke indices into lines, top to bottom. Strokes that nearly touch vertically
    /// (a fraction's numerator, bar and denominator) stay on the same line.
    static func group(_ bounds: [CGRect]) -> [[Int]] {
        guard !bounds.isEmpty else { return [] }
        let heights = bounds.map(\.height).sorted()
        let median = heights[heights.count / 2]
        let gap = min(max(median * 0.6, 6), 22)

        var groups: [[Int]] = []
        var bottom = -CGFloat.infinity
        for index in bounds.indices.sorted(by: { bounds[$0].minY < bounds[$1].minY }) {
            let rect = bounds[index]
            if groups.isEmpty || rect.minY > bottom + gap {
                groups.append([index])
                bottom = rect.maxY
            } else {
                groups[groups.count - 1].append(index)
                bottom = max(bottom, rect.maxY)
            }
        }
        return groups.map { $0.sorted() }
    }
}
