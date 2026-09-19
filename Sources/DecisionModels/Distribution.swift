/// Probabilities over an answer space.
public struct Distribution<Value: Hashable & Sendable>: Sendable {
    /// The probability of every outcome. The values sum to one.
    public let probabilities: [Value: Double]
    /// How much the probabilities can be trusted.
    public let quality: ProbabilityQuality

    /// Builds a distribution. It needs at least one outcome.
    public init(probabilities: [Value: Double], quality: ProbabilityQuality) {
        precondition(!probabilities.isEmpty, "A distribution needs at least one outcome.")
        self.probabilities = probabilities
        self.quality = quality
    }

    /// The outcome with the highest probability.
    public var mostLikely: Value { ranked[0].0 }

    /// Every outcome, highest probability first. Ties order by description, so
    /// the order is stable.
    public var ranked: [(Value, Double)] {
        probabilities
            .map { ($0.key, $0.value) }
            .sorted { left, right in
                if left.1 != right.1 { return left.1 > right.1 }
                return String(describing: left.0) < String(describing: right.0)
            }
    }

    /// Shannon entropy in nats.
    public var entropy: Double {
        ConfidenceMath.entropy(probabilities.values)
    }
}

extension Distribution: Hashable {}

extension Distribution: Codable where Value: Codable {}
