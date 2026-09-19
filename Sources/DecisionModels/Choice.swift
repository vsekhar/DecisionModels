/// An answer that names one option out of many.
public struct Choice<Option: ChoiceOption>: Answer {
    /// The probability of every option.
    public let distribution: Distribution<Option>
    /// The option the model named, when it named one.
    public let reported: Option?
    /// The provider's own confidence, verbatim.
    public let reportedConfidence: Double?

    public init(
        distribution: Distribution<Option>,
        reported: Option? = nil,
        reportedConfidence: Double? = nil
    ) {
        self.distribution = distribution
        self.reported = reported
        self.reportedConfidence = reportedConfidence
    }

    /// Builds an answer that is sure.
    public init(certain: Option) {
        self.init(
            distribution: Distribution(probabilities: [certain: 1], quality: .pointEstimate),
            reported: certain
        )
    }

    /// The option the model named, or the most likely one.
    public var value: Option { reported ?? distribution.mostLikely }

    public var probabilities: [Option: Double] { distribution.probabilities }

    public var confidence: Double {
        reportedConfidence ?? ConfidenceMath.choiceConfidence(
            distribution.probabilities.values,
            optionCount: distribution.probabilities.count
        )
    }

    public var quality: ProbabilityQuality { distribution.quality }

    /// The probability of one option.
    public subscript(option: Option) -> Double {
        distribution.probabilities[option] ?? 0
    }

    /// The value, but only when the answer reaches the bar.
    public func value(ifAtLeast confidence: Double) -> Option? {
        self.confidence >= confidence ? value : nil
    }

    public var record: AnswerRecord {
        .choice(
            reported: value.optionID,
            probabilities: Dictionary(
                distribution.probabilities.map { ($0.key.optionID, $0.value) },
                uniquingKeysWith: +
            ),
            confidence: reportedConfidence
        )
    }
}

extension Choice: Codable where Option: Codable {}

extension Choice where Option: CaseIterable {
    /// Says nothing: every option equally likely, confidence zero.
    public static var uncertain: Choice {
        let options = Array(Option.allCases)
        let share = options.isEmpty ? 0 : 1 / Double(options.count)
        var probabilities: [Option: Double] = [:]
        for option in options { probabilities[option] = share }
        return Choice(
            distribution: Distribution(probabilities: probabilities, quality: .pointEstimate)
        )
    }
}
