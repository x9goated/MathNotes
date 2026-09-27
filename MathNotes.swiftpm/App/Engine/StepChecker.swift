import Foundation

enum StepVerdict: Equatable {
    case valid
    case invalid(String)
    /// Nothing to compare with (first line of a calculation, text, new problem...).
    case unchecked
    /// The transcription couldn't be parsed.
    case unreadable
}

/// A recognized line, as the checker sees it.
struct CheckLine {
    /// Plain-syntax math ("2*x+3=7"), or nil for text lines.
    var expression: String?
    var top: Double
    var bottom: Double
    /// Set by the user to start a new calculation on this line.
    var startsNewBlock = false
}

/// Checks each line of a calculation against the previous one, like a teacher reading the steps.
enum StepChecker {
    static func verdicts(for lines: [CheckLine]) -> [StepVerdict] {
        let heights = lines.map { $0.bottom - $0.top }.sorted()
        let medianHeight = heights.isEmpty ? 0 : heights[heights.count / 2]
        var verdicts: [StepVerdict] = []
        var previous: MathStatement?
        var previousBottom: Double?

        for line in lines {
            defer { previousBottom = line.bottom }
            // A big vertical gap means a new calculation.
            if let bottom = previousBottom, line.top - bottom > max(2 * medianHeight, 40) {
                previous = nil
            }
            if line.startsNewBlock {
                previous = nil
            }
            guard let text = line.expression, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
                // Text ("donc", "Exercice 2"...) keeps the calculation going.
                verdicts.append(.unchecked)
                continue
            }
            guard let statement = try? MathStatement.parse(text) else {
                verdicts.append(.unreadable)
                previous = nil
                continue
            }
            verdicts.append(check(statement, after: previous))
            previous = statement
        }
        return verdicts
    }

    static func check(_ statement: MathStatement, after previous: MathStatement?) -> StepVerdict {
        let inner = checkWithinLine(statement)
        if case .invalid = inner { return inner }
        let step = previous.map { compare($0, statement) } ?? .unchecked
        if case .invalid = step { return step }
        return step == .valid || inner == .valid ? .valid : .unchecked
    }

    /// "2 + 3 = 5" or chains like "A = 2x + 2x = 4x" can be checked on their own.
    private static func checkWithinLine(_ statement: MathStatement) -> StepVerdict {
        guard case .equation(let sides) = statement else { return .unchecked }
        let hasVariables = sides.contains { !$0.variables.isEmpty }
        // In "A = 2x + 2x = 4x" the first side is often just a name, so start at the second side.
        let first = hasVariables ? 1 : 0
        guard sides.count - first >= 2 else { return .unchecked }
        var verdict = StepVerdict.unchecked
        for i in first..<(sides.count - 1) {
            switch Equivalence.compare(sides[i], sides[i + 1]) {
            case .equivalent: verdict = .valid
            case .different(let hint): return .invalid(hint ?? "Les deux membres ne sont pas égaux")
            case .unknown: break
            }
        }
        return verdict
    }

    private static func compare(_ previous: MathStatement, _ current: MathStatement) -> StepVerdict {
        switch (previous, current) {
        case (_, .continuation(let expression)):
            return verdict(for: lastSide(of: previous), expression)
        case (.expression(let a), .expression(let b)), (.continuation(let a), .expression(let b)):
            return verdict(for: a, b)
        case (.equation(let before), .equation(let after)) where before.count == 2 && after.count == 2:
            switch Equivalence.compareEquations((before[0], before[1]), (after[0], after[1])) {
            case .equivalent: return .valid
            case .different(let hint): return .invalid(hint ?? "Cette équation n'est pas équivalente à la précédente")
            case .unknown: return .unchecked
            }
        default:
            return .unchecked
        }
    }

    private static func verdict(for previous: MathExpr, _ current: MathExpr) -> StepVerdict {
        switch Equivalence.compare(previous, current) {
        case .equivalent:
            return .valid
        case .different(let hint):
            // Unrelated expressions are probably a new problem, not a mistake.
            let before = previous.variables, after = current.variables
            if !before.isEmpty && !after.isEmpty && before.isDisjoint(with: after) { return .unchecked }
            if !before.isEmpty && after.isEmpty && hint == nil { return .unchecked }
            return .invalid(hint ?? "Pas égal à la ligne précédente")
        case .unknown:
            return .unchecked
        }
    }

    private static func lastSide(of statement: MathStatement) -> MathExpr {
        switch statement {
        case .expression(let e), .continuation(let e): return e
        case .equation(let sides): return sides[sides.count - 1]
        }
    }
}
