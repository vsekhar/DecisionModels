/// What to do with an answer, given its confidence.
public enum ConfidenceBand: Sendable {
    case act, confirm, escalate
}

/// One typed answer to one question.
public protocol Answer: Sendable {
    associatedtype Value
    /// The value the model named.
    var value: Value { get }
    /// One number in `0...1`. See DESIGN.md section 6.1.
    var confidence: Double { get }
    /// How much the probabilities can be trusted.
    var quality: ProbabilityQuality { get }
    /// The wire-level form.
    var record: AnswerRecord { get }
}

extension Answer {
    /// Sorts the answer into one of the three bands.
    ///
    /// Confidence below `low` escalates. Below `high` it asks for
    /// confirmation. Otherwise the code can act.
    public func band(escalateBelow low: Double, confirmBelow high: Double) -> ConfidenceBand {
        if confidence < low { return .escalate }
        if confidence < high { return .confirm }
        return .act
    }
}
