/// An answer that places the state on an ordered scale.
public struct Rating<Level: RatingLevel>: Answer {
    /// The probability of every level.
    public let distribution: Distribution<Level>
    /// The expected level index, `0...(count - 1)`.
    public let score: Double
    /// The provider's own confidence, verbatim.
    public let reportedConfidence: Double?

    public init(
        distribution: Distribution<Level>,
        score: Double? = nil,
        reportedConfidence: Double? = nil
    ) {
        self.distribution = distribution
        self.score = score ?? ConfidenceMath.expectedLevel(
            Rating.indexed(distribution.probabilities)
        )
        self.reportedConfidence = reportedConfidence
    }

    /// Builds an answer that is sure.
    public init(certain: Level) {
        var probabilities: [Level: Double] = [:]
        for level in Level.levels { probabilities[level] = 0 }
        probabilities[certain] = 1
        self.init(
            distribution: Distribution(probabilities: probabilities, quality: .pointEstimate),
            score: Double(certain.levelIndex)
        )
    }

    /// Says nothing: every level equally likely, confidence zero.
    public static var uncertain: Rating {
        let levels = Level.levels
        let share = levels.isEmpty ? 0 : 1 / Double(levels.count)
        var probabilities: [Level: Double] = [:]
        for level in levels { probabilities[level] = share }
        return Rating(
            distribution: Distribution(probabilities: probabilities, quality: .pointEstimate),
            reportedConfidence: 0
        )
    }

    /// The most likely level. It can differ from `score` on a two-peaked
    /// distribution.
    public var value: Level { distribution.mostLikely }

    /// The score on a `0...1` scale, for composite scoring.
    public var normalized: Double {
        let count = Level.levels.count
        guard count > 1 else { return 0 }
        return score / Double(count - 1)
    }

    public var probabilities: [Level: Double] { distribution.probabilities }

    public var confidence: Double {
        reportedConfidence ?? ConfidenceMath.ratingConfidence(
            Rating.indexed(distribution.probabilities),
            levelCount: Level.levels.count
        )
    }

    public var quality: ProbabilityQuality { distribution.quality }

    /// What every level means.
    public var legend: [Level: Criterion] {
        var legend: [Level: Criterion] = [:]
        for level in Level.levels { legend[level] = level.criterion }
        return legend
    }

    /// The value, but only when the answer reaches the bar.
    public func value(ifAtLeast confidence: Double) -> Level? {
        self.confidence >= confidence ? value : nil
    }

    public var record: AnswerRecord {
        .rating(
            score: score,
            probabilities: Rating.indexed(distribution.probabilities),
            confidence: reportedConfidence
        )
    }

    private static func indexed(_ probabilities: [Level: Double]) -> [Int: Double] {
        var indexed: [Int: Double] = [:]
        for (level, probability) in probabilities { indexed[level.levelIndex] = probability }
        return indexed
    }
}

extension Rating: Codable where Level: Codable {}
