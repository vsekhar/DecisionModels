/// One answer on the wire.
public enum AnswerRecord: Sendable, Codable, Hashable {
    case choice(reported: String, probabilities: [String: Double], confidence: Double?)
    case rating(score: Double, probabilities: [Int: Double], confidence: Double?)
    case verdict(probability: Double)

    /// The provider's confidence, or the number the section 6.1 formula gives.
    ///
    /// A record does not know the full answer space. When it lists only some
    /// options or levels, this number is an estimate; the typed answer knows
    /// the whole scale and is exact.
    public var confidence: Double {
        switch self {
        case .choice(_, let probabilities, let confidence):
            return confidence ?? ConfidenceMath.choiceConfidence(
                ConfidenceMath.normalized(probabilities).values,
                optionCount: probabilities.count
            )
        case .rating(_, let probabilities, let confidence):
            return confidence ?? ConfidenceMath.ratingConfidence(
                ConfidenceMath.normalized(probabilities),
                levelCount: ConfidenceMath.inferredLevelCount(probabilities)
            )
        case .verdict(let probability):
            return ConfidenceMath.verdictConfidence(probability)
        }
    }
}
