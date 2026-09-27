import SwiftUI
import SwiftMath

/// Renders LaTeX natively with SwiftMath.
struct MathView: UIViewRepresentable {
    let latex: String
    var fontSize: CGFloat = 20

    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.labelMode = .display
        label.textAlignment = .left
        label.setContentHuggingPriority(.required, for: .vertical)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    func updateUIView(_ label: MTMathUILabel, context: Context) {
        label.latex = latex
        label.fontSize = fontSize
        label.textColor = UIColor.label
        label.invalidateIntrinsicContentSize()
    }
}
