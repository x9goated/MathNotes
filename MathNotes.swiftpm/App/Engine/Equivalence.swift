import Foundation

/// Numerical equivalence checks: two expressions are compared at random points,
/// two equations by comparing their solution sets.
enum Equivalence {
    enum Result: Equatable {
        case equivalent
        case different(hint: String?)
        case unknown
    }

    // MARK: Expressions

    static func compare(_ a: MathExpr, _ b: MathExpr) -> Result {
        let variables = a.variables.union(b.variables).sorted()
        let samples = sample(a, b, variables: variables)
        guard samples.count >= 4 else { return .unknown }
        if samples.allSatisfy({ close($0.0, $0.1) }) { return .equivalent }
        return .different(hint: hint(for: samples, hasVariables: !variables.isEmpty))
    }

    /// Evaluates both expressions at the same random points, keeping only points where both are defined.
    private static func sample(_ a: MathExpr, _ b: MathExpr, variables: [String]) -> [(Double, Double)] {
        var generator = SplitMix64(seed: 0x5EED)
        var samples: [(Double, Double)] = []
        // The positive range helps with sqrt / ln domains.
        for range in [-4.0...4.0, 0.1...5.0] {
            for _ in 0..<24 {
                var values: [String: Double] = [:]
                for name in variables { values[name] = generator.next(in: range) }
                let x = a.evaluate(values), y = b.evaluate(values)
                if x.isFinite && y.isFinite { samples.append((x, y)) }
            }
            if samples.count >= 12 { break }
        }
        return samples
    }

    private static func hint(for samples: [(Double, Double)], hasVariables: Bool) -> String? {
        guard hasVariables else {
            return "Calcul faux : \(format(samples[0].0)) ≠ \(format(samples[0].1))"
        }
        if samples.allSatisfy({ close($0.0, -$0.1) }) {
            return "Erreur de signe ?"
        }
        let differences = samples.map { $0.1 - $0.0 }
        if differences.allSatisfy({ close($0, differences[0]) }) {
            return "Écart constant de \(format(differences[0])) avec la ligne précédente"
        }
        let ratios = samples.filter { abs($0.0) > 1e-9 }.map { $0.1 / $0.0 }
        if ratios.count >= 4, ratios.allSatisfy({ close($0, ratios[0]) }) {
            return "Multiplié par \(format(ratios[0])) par rapport à la ligne précédente"
        }
        return nil
    }

    // MARK: Equations

    static func compareEquations(_ first: (MathExpr, MathExpr), _ second: (MathExpr, MathExpr)) -> Result {
        let f1 = MathExpr.subtract(first.0, first.1)
        let f2 = MathExpr.subtract(second.0, second.1)
        let vars1 = f1.variables, vars2 = f2.variables
        let variables = vars1.union(vars2).sorted()

        if variables.isEmpty {
            let holds1 = close(first.0.evaluate([:]), first.1.evaluate([:]))
            let holds2 = close(second.0.evaluate([:]), second.1.evaluate([:]))
            return holds1 == holds2 ? .equivalent : .different(hint: nil)
        }
        // Unrelated equations (a new problem) can't be compared.
        if !vars1.isEmpty && !vars2.isEmpty && vars1.isDisjoint(with: vars2) { return .unknown }

        if areProportional(f1, f2, variables: variables) { return .equivalent }

        // Compare solution sets along one variable, with the others fixed at random values.
        let unknown = variables.first { vars1.contains($0) && vars2.contains($0) } ?? variables[0]
        let others = variables.filter { $0 != unknown }
        var generator = SplitMix64(seed: 0xC0FFEE)
        var comparedSomething = false
        for _ in 0..<(others.isEmpty ? 1 : 4) {
            var fixed: [String: Double] = [:]
            for name in others { fixed[name] = generator.next(in: 0.5...3.0) }
            let roots1 = RootFinder.roots(of: f1, in: unknown, fixed: fixed)
            let roots2 = RootFinder.roots(of: f2, in: unknown, fixed: fixed)
            if roots1 == .finite([]) && roots2 == .finite([]) { continue }
            comparedSomething = true
            if !RootFinder.same(roots1, roots2) {
                return .different(hint: others.isEmpty ? solutionHint(roots1, roots2, variable: unknown) : nil)
            }
        }
        return comparedSomething ? .equivalent : .unknown
    }

    /// True when f2 = k·f1 for a constant k ≠ 0 (adding to both sides, multiplying by a constant...).
    private static func areProportional(_ f1: MathExpr, _ f2: MathExpr, variables: [String]) -> Bool {
        var generator = SplitMix64(seed: 0xFACE)
        var ratios: [Double] = []
        var bothZero = 0
        for _ in 0..<32 {
            var values: [String: Double] = [:]
            for name in variables { values[name] = generator.next(in: -4.0...4.0) }
            let y1 = f1.evaluate(values), y2 = f2.evaluate(values)
            guard y1.isFinite && y2.isFinite else { continue }
            if abs(y1) < 1e-12 && abs(y2) < 1e-12 {
                bothZero += 1
            } else if abs(y1) > 1e-9 {
                ratios.append(y2 / y1)
            } else {
                return false
            }
        }
        if ratios.isEmpty { return bothZero >= 4 }
        return ratios.count >= 4 && abs(ratios[0]) > 1e-9 && ratios.allSatisfy { close($0, ratios[0]) }
    }

    private static func solutionHint(_ before: RootFinder.RootSet, _ after: RootFinder.RootSet, variable: String) -> String? {
        guard case .finite(let old) = before, case .finite(let new) = after else { return nil }
        let lost = old.filter { root in !new.contains { close($0, root, tolerance: 1e-5) } }
        let extra = new.filter { root in !old.contains { close($0, root, tolerance: 1e-5) } }
        if !lost.isEmpty {
            return "Solution perdue : \(variable) = \(lost.map(format).joined(separator: ", "))"
        }
        if !extra.isEmpty {
            return "Solution en trop : \(variable) = \(extra.map(format).joined(separator: ", "))"
        }
        return nil
    }

    // MARK: Helpers

    static func close(_ a: Double, _ b: Double, tolerance: Double = 1e-7) -> Bool {
        abs(a - b) <= tolerance * max(1, abs(a), abs(b))
    }

    static func format(_ value: Double) -> String {
        if abs(value - value.rounded()) < 1e-9 { return String(Int(value.rounded())) }
        return String(format: "%.4g", value)
    }
}

/// Finds the real roots of f(t) = 0 on [-50, 50] by scanning for sign changes and touching points.
enum RootFinder {
    enum RootSet: Equatable {
        case finite([Double])
        /// The equation holds for every value (an identity).
        case everything
    }

    static func roots(of f: MathExpr, in variable: String, fixed: [String: Double]) -> RootSet {
        var values = fixed
        func eval(_ t: Double) -> Double {
            values[variable] = t
            return f.evaluate(values)
        }

        let lower = -50.0, step = 0.02
        let count = 5001
        let ts = (0..<count).map { lower + Double($0) * step }
        let ys = ts.map(eval)

        let finite = ys.filter(\.isFinite)
        if finite.count > count / 2 && finite.filter({ abs($0) < 1e-9 }).count > finite.count * 9 / 10 {
            return .everything
        }

        var found: [Double] = []
        for i in 0..<count {
            let y = ys[i]
            guard y.isFinite else { continue }
            if y == 0 { found.append(ts[i]); continue }
            if i + 1 < count, ys[i + 1].isFinite, y * ys[i + 1] < 0,
               let root = bisect(eval, ts[i], ts[i + 1]) {
                found.append(root)
            }
            // Touching roots such as (x - 2)^2 = 0 don't change sign.
            if i > 0, i + 1 < count, ys[i - 1].isFinite, ys[i + 1].isFinite,
               abs(y) <= abs(ys[i - 1]), abs(y) <= abs(ys[i + 1]), abs(y) < 0.5,
               ys[i - 1] * ys[i + 1] > 0,
               let root = minimizeAbs(eval, ts[i - 1], ts[i + 1]) {
                found.append(root)
            }
        }
        return .finite(deduplicate(found))
    }

    static func same(_ a: RootSet, _ b: RootSet) -> Bool {
        switch (a, b) {
        case (.everything, .everything): return true
        case (.finite(let x), .finite(let y)):
            return x.count == y.count && zip(x, y).allSatisfy { Equivalence.close($0, $1, tolerance: 1e-5) }
        default: return false
        }
    }

    private static func bisect(_ f: (Double) -> Double, _ a: Double, _ b: Double) -> Double? {
        var lo = a, hi = b
        var fLo = f(lo)
        for _ in 0..<80 {
            let mid = (lo + hi) / 2
            let fMid = f(mid)
            guard fMid.isFinite else { return nil }
            if fMid == 0 { return mid }
            if (fLo < 0) == (fMid < 0) {
                lo = mid
                fLo = fMid
            } else {
                hi = mid
            }
        }
        let root = (lo + hi) / 2
        // A sign change across a pole (like 1/x at 0) is not a root.
        return abs(f(root)) < 1e-6 ? root : nil
    }

    private static func minimizeAbs(_ f: (Double) -> Double, _ a: Double, _ b: Double) -> Double? {
        var lo = a, hi = b
        for _ in 0..<120 {
            let m1 = lo + (hi - lo) / 3, m2 = hi - (hi - lo) / 3
            if abs(f(m1)) < abs(f(m2)) { hi = m2 } else { lo = m1 }
        }
        let t = (lo + hi) / 2
        let y = f(t)
        return y.isFinite && abs(y) < 1e-8 ? t : nil
    }

    private static func deduplicate(_ roots: [Double]) -> [Double] {
        var result: [Double] = []
        for root in roots.sorted() where !result.contains(where: { Equivalence.close($0, root, tolerance: 1e-5) }) {
            result.append(abs(root) < 1e-9 ? 0 : root)
        }
        return result
    }
}

/// Small deterministic random generator, so a step always gets the same verdict.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
