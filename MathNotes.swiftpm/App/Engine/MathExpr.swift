import Foundation

/// A parsed math expression.
/// Named `MathExpr` rather than `Expression` to avoid clashing with Foundation's `Expression`.
indirect enum MathExpr: Equatable {
    case number(Double)
    case variable(String)
    case negate(MathExpr)
    case add(MathExpr, MathExpr)
    case subtract(MathExpr, MathExpr)
    case multiply(MathExpr, MathExpr)
    case divide(MathExpr, MathExpr)
    case power(MathExpr, MathExpr)
    case function(String, MathExpr)

    /// Evaluates the expression; unknown variables and domain errors give NaN or infinity.
    func evaluate(_ values: [String: Double]) -> Double {
        switch self {
        case .number(let value): return value
        case .variable(let name): return values[name] ?? .nan
        case .negate(let operand): return -operand.evaluate(values)
        case .add(let lhs, let rhs): return lhs.evaluate(values) + rhs.evaluate(values)
        case .subtract(let lhs, let rhs): return lhs.evaluate(values) - rhs.evaluate(values)
        case .multiply(let lhs, let rhs): return lhs.evaluate(values) * rhs.evaluate(values)
        case .divide(let lhs, let rhs): return lhs.evaluate(values) / rhs.evaluate(values)
        case .power(let base, let exponent): return pow(base.evaluate(values), exponent.evaluate(values))
        case .function(let name, let argument): return MathFunctions.apply(name, to: argument.evaluate(values))
        }
    }

    var variables: Set<String> {
        switch self {
        case .number: return []
        case .variable(let name): return [name]
        case .negate(let operand), .function(_, let operand): return operand.variables
        case .add(let lhs, let rhs), .subtract(let lhs, let rhs), .multiply(let lhs, let rhs),
             .divide(let lhs, let rhs), .power(let lhs, let rhs):
            return lhs.variables.union(rhs.variables)
        }
    }
}

enum MathFunctions {
    static let names: Set<String> = [
        "sqrt", "cbrt", "sin", "cos", "tan", "asin", "acos", "atan", "arcsin", "arccos", "arctan",
        "sinh", "cosh", "tanh", "ln", "log", "exp", "abs",
    ]

    static let constants: [String: Double] = ["pi": Double.pi, "e": exp(1.0)]

    static let greekLetters: Set<String> = [
        "alpha", "beta", "gamma", "delta", "epsilon", "theta", "lambda", "mu", "nu", "rho",
        "sigma", "tau", "phi", "psi", "omega",
    ]

    static func apply(_ name: String, to x: Double) -> Double {
        switch name {
        case "sqrt": return x.squareRoot()
        case "cbrt": return cbrt(x)
        case "sin": return sin(x)
        case "cos": return cos(x)
        case "tan": return tan(x)
        case "asin", "arcsin": return asin(x)
        case "acos", "arccos": return acos(x)
        case "atan", "arctan": return atan(x)
        case "sinh": return sinh(x)
        case "cosh": return cosh(x)
        case "tanh": return tanh(x)
        case "ln": return log(x)
        case "log": return log10(x)
        case "exp": return exp(x)
        case "abs": return abs(x)
        default: return .nan
        }
    }
}

/// One handwritten math line: an expression, an equation, or a continuation ("= ...").
enum MathStatement: Equatable {
    case expression(MathExpr)
    /// A line starting with "=" that continues the previous line.
    case continuation(MathExpr)
    /// Two or more sides joined by "=".
    case equation([MathExpr])

    static func parse(_ text: String) throws -> MathStatement {
        let tokens = try MathTokenizer.tokenize(text)
        var sides: [[MathToken]] = [[]]
        for token in tokens {
            if token == .equals {
                sides.append([])
            } else {
                sides[sides.count - 1].append(token)
            }
        }
        if sides.count == 2 && sides[0].isEmpty {
            return .continuation(try MathParser.parse(sides[1]))
        }
        let expressions = try sides.map { tokens -> MathExpr in
            guard !tokens.isEmpty else { throw MathParseError.emptySide }
            return try MathParser.parse(tokens)
        }
        return expressions.count == 1 ? .expression(expressions[0]) : .equation(expressions)
    }
}

enum MathParseError: Error, Equatable {
    case emptySide
    case unexpectedCharacter(Character)
    case unexpectedToken
    case unexpectedEnd
    case missingParenthesis
    case invalidNumber(String)
}

enum MathToken: Equatable {
    case number(Double)
    case identifier(String)
    case op(Character)
    case leftParen
    case rightParen
    case comma
    case equals
}

enum MathTokenizer {
    private static let replacements: [(String, String)] = [
        ("\\cdot", "*"), ("\\times", "*"), ("×", "*"), ("·", "*"), ("⋅", "*"), ("÷", "/"),
        ("−", "-"), ("–", "-"), ("π", " pi "), ("√", " sqrt "), ("²", "^2"), ("³", "^3"),
    ]

    static func tokenize(_ input: String) throws -> [MathToken] {
        var text = input
        for (from, to) in replacements {
            text = text.replacingOccurrences(of: from, with: to)
        }
        let chars = Array(text)
        var tokens: [MathToken] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if isDigit(c) || (c == "." && i + 1 < chars.count && isDigit(chars[i + 1])) {
                var j = i
                while j < chars.count, isDigit(chars[j]) || chars[j] == "." { j += 1 }
                let literal = String(chars[i..<j])
                guard let value = Double(literal) else { throw MathParseError.invalidNumber(literal) }
                tokens.append(.number(value))
                i = j
            } else if c.isLetter {
                var j = i
                while j < chars.count, chars[j].isLetter { j += 1 }
                var name = String(chars[i..<j])
                // Subscripts: x_1, x_n, x_{12}
                if j < chars.count, chars[j] == "_" {
                    var k = j + 1
                    var subscriptText = ""
                    if k < chars.count, chars[k] == "{" {
                        k += 1
                        while k < chars.count, chars[k] != "}" { subscriptText.append(chars[k]); k += 1 }
                        k += 1
                    } else {
                        while k < chars.count, chars[k].isLetter || isDigit(chars[k]) { subscriptText.append(chars[k]); k += 1 }
                    }
                    if !subscriptText.isEmpty {
                        name += "_" + subscriptText
                        j = k
                    }
                }
                tokens.append(.identifier(name))
                i = j
            } else {
                switch c {
                case "+", "-", "*", "/", "^": tokens.append(.op(c))
                case "(", "[", "{": tokens.append(.leftParen)
                case ")", "]", "}": tokens.append(.rightParen)
                case ",", ";": tokens.append(.comma)
                case "=": tokens.append(.equals)
                default: throw MathParseError.unexpectedCharacter(c)
                }
                i += 1
            }
        }
        return tokens
    }

    private static func isDigit(_ c: Character) -> Bool {
        c >= "0" && c <= "9"
    }
}

/// Recursive-descent parser with implicit multiplication ("2x", "3(x+1)", "(a+b)(a-b)").
struct MathParser {
    private let tokens: [MathToken]
    private var index = 0

    private init(tokens: [MathToken]) {
        self.tokens = tokens
    }

    static func parse(_ tokens: [MathToken]) throws -> MathExpr {
        var parser = MathParser(tokens: tokens)
        let expression = try parser.parseSum()
        guard parser.index == tokens.count else { throw MathParseError.unexpectedToken }
        return expression
    }

    private var peek: MathToken? {
        index < tokens.count ? tokens[index] : nil
    }

    private mutating func next() -> MathToken? {
        defer { index += 1 }
        return peek
    }

    private mutating func parseSum() throws -> MathExpr {
        var lhs = try parseProduct()
        while case .op(let c)? = peek, c == "+" || c == "-" {
            index += 1
            let rhs = try parseProduct()
            lhs = c == "+" ? .add(lhs, rhs) : .subtract(lhs, rhs)
        }
        return lhs
    }

    private mutating func parseProduct() throws -> MathExpr {
        var lhs = try parseUnary()
        while true {
            if case .op(let c)? = peek, c == "*" || c == "/" {
                index += 1
                let rhs = try parseUnary()
                lhs = c == "*" ? .multiply(lhs, rhs) : .divide(lhs, rhs)
            } else if startsOperand(peek) {
                lhs = .multiply(lhs, try parsePower())
            } else {
                return lhs
            }
        }
    }

    private mutating func parseUnary() throws -> MathExpr {
        if case .op(let c)? = peek, c == "-" || c == "+" {
            index += 1
            let operand = try parseUnary()
            return c == "-" ? .negate(operand) : operand
        }
        return try parsePower()
    }

    private mutating func parsePower() throws -> MathExpr {
        let base = try parsePrimary()
        if case .op(let c)? = peek, c == "^" {
            index += 1
            // Right-associative, and allows a sign: 2^-1, a^b^c.
            return .power(base, try parseUnary())
        }
        return base
    }

    private mutating func parsePrimary() throws -> MathExpr {
        guard let token = next() else { throw MathParseError.unexpectedEnd }
        switch token {
        case .number(let value):
            return .number(value)
        case .leftParen:
            let inner = try parseSum()
            guard next() == .rightParen else { throw MathParseError.missingParenthesis }
            return inner
        case .identifier(let name):
            return try parseIdentifier(name)
        default:
            throw MathParseError.unexpectedToken
        }
    }

    private mutating func parseIdentifier(_ name: String) throws -> MathExpr {
        if MathFunctions.names.contains(name) {
            if peek == .leftParen {
                index += 1
                let argument = try parseSum()
                guard next() == .rightParen else { throw MathParseError.missingParenthesis }
                return .function(name, argument)
            }
            // "sin x", "sqrt x"
            return .function(name, try parsePower())
        }
        if let value = MathFunctions.constants[name] {
            return .number(value)
        }
        if name.count == 1 || name.contains("_") || MathFunctions.greekLetters.contains(name) {
            return .variable(name)
        }
        // "xy" means x * y
        let factors: [MathExpr] = name.map { letter in
            let single = String(letter)
            return MathFunctions.constants[single].map(MathExpr.number) ?? .variable(single)
        }
        return factors.dropFirst().reduce(factors[0]) { .multiply($0, $1) }
    }

    private func startsOperand(_ token: MathToken?) -> Bool {
        switch token {
        case .number?, .identifier?, .leftParen?: return true
        default: return false
        }
    }
}
