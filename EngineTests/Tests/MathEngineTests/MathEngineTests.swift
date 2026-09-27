import CoreGraphics
import XCTest
@testable import MathEngine

final class ParserTests: XCTestCase {
    private func value(_ text: String, _ values: [String: Double] = [:]) throws -> Double {
        guard case .expression(let expression) = try MathStatement.parse(text) else {
            XCTFail("\(text) is not an expression")
            return .nan
        }
        return expression.evaluate(values)
    }

    func testArithmeticAndPrecedence() throws {
        XCTAssertEqual(try value("2*x+3", ["x": 2]), 7)
        XCTAssertEqual(try value("2+3*4"), 14)
        XCTAssertEqual(try value("2^3^2"), 512)
        XCTAssertEqual(try value("-x^2", ["x": 2]), -4)
        XCTAssertEqual(try value("2^-1"), 0.5)
        XCTAssertEqual(try value("(1+2)/(4-1)"), 1)
    }

    func testImplicitMultiplication() throws {
        XCTAssertEqual(try value("2x^2", ["x": 3]), 18)
        XCTAssertEqual(try value("3(x+1)", ["x": 1]), 6)
        XCTAssertEqual(try value("(x+1)(x-1)", ["x": 3]), 8)
        XCTAssertEqual(try value("xy", ["x": 2, "y": 5]), 10)
    }

    func testFunctionsConstantsAndUnicode() throws {
        XCTAssertEqual(try value("sqrt(16)"), 4)
        XCTAssertEqual(try value("sin(pi/2)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try value("ln(e)"), 1, accuracy: 1e-12)
        XCTAssertEqual(try value("3 × 4 − 2"), 10)
        XCTAssertEqual(try value("x²", ["x": 5]), 25)
        XCTAssertEqual(try value("2π"), 2 * .pi, accuracy: 1e-12)
        XCTAssertEqual(try value("x_1 + x_{2}", ["x_1": 1, "x_2": 2]), 3)
    }

    func testStatements() throws {
        XCTAssertEqual(try MathStatement.parse("= 2x"), .continuation(.multiply(.number(2), .variable("x"))))
        guard case .equation(let sides) = try MathStatement.parse("a = b = c") else { return XCTFail() }
        XCTAssertEqual(sides.count, 3)
        XCTAssertThrowsError(try MathStatement.parse("2 + "))
        XCTAssertThrowsError(try MathStatement.parse("(x+1"))
        XCTAssertThrowsError(try MathStatement.parse("x = "))
    }
}

final class StepCheckerTests: XCTestCase {
    private func verdicts(_ lines: [String?]) -> [StepVerdict] {
        let checkLines = lines.enumerated().map { index, text in
            CheckLine(expression: text, top: Double(index) * 40, bottom: Double(index) * 40 + 25)
        }
        return StepChecker.verdicts(for: checkLines)
    }

    func testExpressionSteps() {
        let result = verdicts(["(x+1)^2", "x^2+2*x+1", "x^2+1"])
        XCTAssertEqual(result[0], .unchecked)
        XCTAssertEqual(result[1], .valid)
        guard case .invalid = result[2] else { return XCTFail("\(result[2])") }
    }

    func testSignErrorHint() {
        let result = verdicts(["x-3", "3-x"])
        XCTAssertEqual(result[1], .invalid("Erreur de signe ?"))
    }

    func testContinuation() {
        let result = verdicts(["(x+1)^2", "= x^2+2*x+1", "= x^2+2*x"])
        XCTAssertEqual(result[1], .valid)
        guard case .invalid = result[2] else { return XCTFail("\(result[2])") }
    }

    func testLinearEquation() {
        let result = verdicts(["2*x+3=7", "2*x=4", "x=2", "x=3"])
        XCTAssertEqual(Array(result[1...2]), [.valid, .valid])
        guard case .invalid = result[3] else { return XCTFail("\(result[3])") }
    }

    func testLostSolution() {
        let result = verdicts(["x^2=4", "x=2"])
        XCTAssertEqual(result[1], .invalid("Solution perdue : x = -2"))
    }

    func testQuadraticFactoring() {
        let result = verdicts(["x^2-5*x+6=0", "(x-2)*(x-3)=0"])
        XCTAssertEqual(result[1], .valid)
    }

    func testDoubleRoot() {
        let result = verdicts(["x^2-4*x+4=0", "(x-2)^2=0", "x=2"])
        XCTAssertEqual(Array(result[1...2]), [.valid, .valid])
    }

    func testTwoVariables() {
        let result = verdicts(["y=2*x+1", "x=(y-1)/2", "x*y=1", "y=1/x"])
        XCTAssertEqual(result[1], .valid)
        XCTAssertEqual(result[3], .valid)
    }

    func testArithmeticWithinLine() {
        let result = verdicts(["2+3=5", nil, "2+2=5"])
        XCTAssertEqual(result[0], .valid)
        XCTAssertEqual(result[1], .unchecked)
        XCTAssertEqual(result[2], .invalid("Calcul faux : 4 ≠ 5"))
    }

    func testChainWithinLine() {
        XCTAssertEqual(verdicts(["A = 2*x+2*x = 4*x"])[0], .valid)
        guard case .invalid = verdicts(["A = 2*x+2*x = 5*x"])[0] else { return XCTFail() }
    }

    func testUnrelatedLinesAreNotMistakes() {
        XCTAssertEqual(verdicts(["2*x+1", "3*y-2"])[1], .unchecked)
        XCTAssertEqual(verdicts(["x=2", "t^2=9"])[1], .unchecked)
    }

    func testGapStartsNewCalculation() {
        let lines = [
            CheckLine(expression: "x^2=4", top: 0, bottom: 25),
            CheckLine(expression: "x=5", top: 300, bottom: 325),
        ]
        XCTAssertEqual(StepChecker.verdicts(for: lines)[1], .unchecked)
    }

    func testUserStartsNewBlock() {
        var lines = [
            CheckLine(expression: "x^2=4", top: 0, bottom: 25),
            CheckLine(expression: "x=5", top: 40, bottom: 65),
        ]
        guard case .invalid = StepChecker.verdicts(for: lines)[1] else { return XCTFail() }
        lines[1].startsNewBlock = true
        XCTAssertEqual(StepChecker.verdicts(for: lines)[1], .unchecked)
    }

    func testUnreadableLine() {
        XCTAssertEqual(verdicts(["x ≤ 3"])[0], .unreadable)
    }
}

final class LineSegmenterTests: XCTestCase {
    func testSeparatesLinesAndKeepsFractionsTogether() {
        let strokes = [
            CGRect(x: 0, y: 0, width: 20, height: 18),     // line 1: "2"
            CGRect(x: 30, y: 4, width: 14, height: 14),    // line 1: "x"
            CGRect(x: 0, y: 60, width: 14, height: 14),    // line 2: numerator
            CGRect(x: 0, y: 79, width: 20, height: 2),     // line 2: fraction bar
            CGRect(x: 0, y: 86, width: 14, height: 14),    // line 2: denominator
            CGRect(x: 30, y: 72, width: 14, height: 14),   // line 2: "x" next to the fraction
            CGRect(x: 0, y: 140, width: 18, height: 18),   // line 3
        ]
        XCTAssertEqual(LineSegmenter.group(strokes), [[0, 1], [2, 3, 4, 5], [6]])
    }
}
