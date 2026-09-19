/// A yes or no answer with the probability behind it.
public struct Verdict: Answer, Codable, Hashable {
    /// P(yes).
    public let probability: Double
    /// How much the probability can be trusted.
    public let quality: ProbabilityQuality

    public init(probability: Double, quality: ProbabilityQuality = .pointEstimate) {
        self.probability = probability
        self.quality = quality
    }

    /// Builds an answer that is sure.
    public init(certain: Bool) {
        self.init(probability: certain ? 1 : 0, quality: .pointEstimate)
    }

    /// Says nothing: probability one half.
    public static var uncertain: Verdict {
        Verdict(probability: 0.5, quality: .pointEstimate)
    }

    public var value: Bool { probability >= 0.5 }

    public var confidence: Double { ConfidenceMath.verdictConfidence(probability) }

    /// Answers yes only when the probability reaches the bar.
    public func isTrue(atLeast probability: Double) -> Bool {
        self.probability >= probability
    }

    public var record: AnswerRecord { .verdict(probability: probability) }
}
