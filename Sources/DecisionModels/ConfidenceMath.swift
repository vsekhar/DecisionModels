import Foundation

/// The confidence formulas of DESIGN.md section 6.1.
///
/// One implementation serves `AnswerRecord` and the typed answers. A
/// confidence the provider reports always wins over these numbers.
enum ConfidenceMath {
    /// Shannon entropy in nats.
    static func entropy(_ probabilities: some Sequence<Double>) -> Double {
        var total = 0.0
        for probability in probabilities where probability > 0 {
            total -= probability * log(probability)
        }
        return total
    }

    /// Choice confidence: `1 - H(p) / ln(n)`. One option means full
    /// confidence; no options means none.
    static func choiceConfidence(
        _ probabilities: some Sequence<Double>,
        optionCount: Int
    ) -> Double {
        guard optionCount > 0 else { return 0 }
        guard optionCount > 1 else { return 1 }
        return clamped(1 - entropy(probabilities) / log(Double(optionCount)))
    }

    /// The expected level index.
    static func expectedLevel(_ probabilities: [Int: Double]) -> Double {
        probabilities.reduce(0) { $0 + Double($1.key) * $1.value }
    }

    /// Rating confidence: `1 - sigma(p) / ((n - 1) / 2)`, over level indices.
    /// One level means full confidence; no levels means none.
    static func ratingConfidence(_ probabilities: [Int: Double], levelCount: Int) -> Double {
        guard levelCount > 0 else { return 0 }
        guard levelCount > 1 else { return 1 }
        let mean = expectedLevel(probabilities)
        let variance = probabilities.reduce(0) { total, entry in
            let deviation = Double(entry.key) - mean
            return total + entry.value * deviation * deviation
        }
        let spread = Double(levelCount - 1) / 2
        return clamped(1 - variance.squareRoot() / spread)
    }

    /// Verdict confidence: `abs(2p - 1)`.
    static func verdictConfidence(_ probability: Double) -> Double {
        clamped(abs(2 * probability - 1))
    }

    /// The number of levels a record covers, when only the record is at hand.
    static func inferredLevelCount(_ probabilities: [Int: Double]) -> Int {
        let highest = (probabilities.keys.max() ?? -1) + 1
        return max(highest, probabilities.count)
    }

    /// Scales probabilities so that they sum to one.
    static func normalized<Key>(_ probabilities: [Key: Double]) -> [Key: Double] {
        let total = probabilities.values.reduce(0, +)
        guard total > 0, abs(total - 1) > 1e-9 else { return probabilities }
        return probabilities.mapValues { $0 / total }
    }

    /// Keeps a value inside `0...1`. A value that is not a number becomes 0,
    /// so that no threshold ever passes it.
    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
