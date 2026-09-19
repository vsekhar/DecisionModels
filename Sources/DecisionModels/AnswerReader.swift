/// Turns wire records into typed answers.
///
/// The reader rejects what a provider must never send: probabilities that
/// are empty, negative, not finite, or sum to zero; a reported confidence
/// outside `0...1`; option ids the question does not know. Every rejection
/// throws a `DecisionError`. Nothing here traps.
enum AnswerReader {
    static func choice<Option: ChoiceOption>(
        _ record: AnswerRecord,
        id: String,
        options: [Option],
        quality: ProbabilityQuality
    ) throws -> Choice<Option> {
        guard case .choice(let reported, let probabilities, let confidence) = record else {
            throw DecisionError.malformedResponse(
                "Question \(id) expects a choice, but the record holds \(record.kindName)."
            )
        }
        guard !options.isEmpty else {
            throw DecisionError.invalidQuestion(id: id, reason: "The question has no options.")
        }
        var byID: [String: Option] = [:]
        for option in options {
            guard byID.updateValue(option, forKey: option.optionID) == nil else {
                throw DecisionError.invalidQuestion(
                    id: id,
                    reason: "Two options share the id \(option.optionID)."
                )
            }
        }
        var mapped: [Option: Double] = [:]
        for option in options { mapped[option] = 0 }
        for (optionID, probability) in try validated(probabilities, id: id) {
            guard let option = byID[optionID] else {
                throw DecisionError.malformedResponse(
                    "Question \(id) has no option named \(optionID)."
                )
            }
            mapped[option] = probability
        }
        guard let named = byID[reported] else {
            throw DecisionError.malformedResponse(
                "Question \(id) has no option named \(reported)."
            )
        }
        return Choice(
            distribution: Distribution(probabilities: mapped, quality: quality),
            reported: named,
            reportedConfidence: try validatedConfidence(confidence, id: id)
        )
    }

    static func rating<Level: RatingLevel>(
        _ record: AnswerRecord,
        id: String,
        quality: ProbabilityQuality
    ) throws -> Rating<Level> {
        guard case .rating(let score, let probabilities, let confidence) = record else {
            throw DecisionError.malformedResponse(
                "Question \(id) expects a rating, but the record holds \(record.kindName)."
            )
        }
        let levels = Level.levels
        guard !levels.isEmpty else {
            throw DecisionError.invalidQuestion(id: id, reason: "The scale has no levels.")
        }
        guard score.isFinite else {
            throw DecisionError.malformedResponse("Question \(id) has a score that is not a number.")
        }
        var mapped: [Level: Double] = [:]
        for level in levels { mapped[level] = 0 }
        for (index, probability) in try validated(probabilities, id: id) {
            guard levels.indices.contains(index) else {
                throw DecisionError.malformedResponse(
                    "Question \(id) has no level at index \(index)."
                )
            }
            mapped[levels[index]] = probability
        }
        return Rating(
            distribution: Distribution(probabilities: mapped, quality: quality),
            score: score,
            reportedConfidence: try validatedConfidence(confidence, id: id)
        )
    }

    static func verdict(
        _ record: AnswerRecord,
        id: String,
        quality: ProbabilityQuality
    ) throws -> Verdict {
        guard case .verdict(let probability) = record else {
            throw DecisionError.malformedResponse(
                "Question \(id) expects a verdict, but the record holds \(record.kindName)."
            )
        }
        guard probability.isFinite, (0...1).contains(probability) else {
            throw DecisionError.malformedResponse(
                "Question \(id) has a probability outside 0...1."
            )
        }
        return Verdict(probability: probability, quality: quality)
    }

    /// Checks a probability map and scales it so that it sums to one.
    static func validated<Key>(_ probabilities: [Key: Double], id: String) throws -> [Key: Double] {
        guard !probabilities.isEmpty else {
            throw DecisionError.malformedResponse("Question \(id) has no probabilities.")
        }
        for probability in probabilities.values where !(probability.isFinite && probability >= 0) {
            throw DecisionError.malformedResponse(
                "Question \(id) has a probability that is negative or not a number."
            )
        }
        guard probabilities.values.reduce(0, +) > 0 else {
            throw DecisionError.malformedResponse("Question \(id) has probabilities that sum to zero.")
        }
        return ConfidenceMath.normalized(probabilities)
    }

    /// Checks a reported confidence, when there is one.
    static func validatedConfidence(_ confidence: Double?, id: String) throws -> Double? {
        guard let confidence else { return nil }
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw DecisionError.malformedResponse(
                "Question \(id) reports a confidence outside 0...1."
            )
        }
        return confidence
    }
}

extension AnswerRecord {
    /// The name of the case, for error messages.
    var kindName: String {
        switch self {
        case .choice: "a choice"
        case .rating: "a rating"
        case .verdict: "a verdict"
        }
    }
}
