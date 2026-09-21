/// One answer on the wire.
public enum AnswerRecord: Sendable, Codable, Hashable {
    case choice(reported: String, probabilities: [String: Double], confidence: Double?)
    case rating(score: Double, probabilities: [Int: Double], confidence: Double?)
    case verdict(probability: Double)

    /// The provider's confidence, or the number the section 6.1 formula gives.
    ///
    /// The formula needs the size of the answer space, which a record does
    /// not carry. A record the session returns lists every option or level
    /// of its question, absent ones at zero, so the number is exact. A
    /// record from anywhere else may list only the options or levels the
    /// provider saw; then the count is a guess from the record and the
    /// number is an estimate. Read such a record through its question to
    /// get the exact value.
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
