/// Turns wire records into typed answers, and completes wire records against
/// the questions that asked for them.
///
/// The reader rejects what a provider must never send: probabilities that
/// are empty, negative, not finite, or sum to zero; a reported confidence
/// outside `0...1`; option ids or level indices the question does not know;
/// a record whose kind does not match the question. Every rejection throws
/// a `DecisionError`. Nothing here traps.
///
/// The typed readers and the wire-level `resolved` calls share one set of
/// checks, so the two paths cannot drift apart.
enum AnswerReader {
    // MARK: Typed answers

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
        let completed = try completed(
            probabilities, reported: reported, optionIDs: options.map(\.optionID), id: id
        )
        var mapped: [Option: Double] = [:]
        for option in options { mapped[option] = completed[option.optionID] ?? 0 }
        return Choice(
            distribution: Distribution(
                probabilities: ConfidenceMath.normalized(mapped), quality: quality
            ),
            reported: byID[reported],
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
        let completed = try completed(probabilities, score: score, levelCount: levels.count, id: id)
        var mapped: [Level: Double] = [:]
        for (index, level) in levels.enumerated() { mapped[level] = completed[index] ?? 0 }
        return Rating(
            distribution: Distribution(
                probabilities: ConfidenceMath.normalized(mapped), quality: quality
            ),
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
        return Verdict(probability: try validatedProbability(probability, id: id), quality: quality)
    }

    // MARK: Wire records

    /// Completes every record of a response against the question that asked
    /// for it, so that each record covers the whole answer space.
    ///
    /// A record with no question, and a record whose kind does not match its
    /// question, are malformed. A question with no record stays absent: a
    /// `@Decision` enum decodes only the chosen case's arguments, so a
    /// response may leave the others out, and `Answers` reports the gap as
    /// `invalidQuestion` when a read needs it.
    static func resolved(_ answers: Answers, against questionnaire: Questionnaire) throws -> Answers {
        var records: [String: AnswerRecord] = [:]
        for spec in questionnaire.specs {
            guard let record = answers.records[spec.id] else { continue }
            records[spec.id] = try resolved(record, against: spec)
        }
        for id in answers.records.keys.sorted() where records[id] == nil {
            throw DecisionError.malformedResponse("Question \(id) was not asked.")
        }
        return Answers(records: records, quality: answers.quality)
    }

    /// Completes one record against its question. The provider's numbers
    /// stay as they are; every option or level the record leaves out comes
    /// in at zero.
    static func resolved(_ record: AnswerRecord, against spec: QuestionSpec) throws -> AnswerRecord {
        let id = spec.id
        switch (spec.kind, record) {
        case (.choice(let options), .choice(let reported, let probabilities, let confidence)):
            return .choice(
                reported: reported,
                probabilities: try completed(
                    probabilities, reported: reported, optionIDs: options.map(\.id), id: id
                ),
                confidence: try validatedConfidence(confidence, id: id)
            )
        case (.rating(let levels), .rating(let score, let probabilities, let confidence)):
            return .rating(
                score: score,
                probabilities: try completed(
                    probabilities, score: score, levelCount: levels.count, id: id
                ),
                confidence: try validatedConfidence(confidence, id: id)
            )
        case (.verdict, .verdict(let probability)):
            return .verdict(probability: try validatedProbability(probability, id: id))
        default:
            throw DecisionError.malformedResponse(
                "Question \(id) expects \(spec.kind.kindName), but the record holds \(record.kindName)."
            )
        }
    }

    // MARK: Checks both paths share

    /// Checks a choice's probabilities and reported option against the option
    /// ids, and adds every option the record leaves out at zero. Two options
    /// with one id are an invalid question.
    static func completed(
        _ probabilities: [String: Double],
        reported: String,
        optionIDs: [String],
        id: String
    ) throws -> [String: Double] {
        var completed: [String: Double] = [:]
        for optionID in optionIDs {
            guard completed.updateValue(0, forKey: optionID) == nil else {
                throw DecisionError.invalidQuestion(
                    id: id, reason: "Two options share the id \(optionID)."
                )
            }
        }
        for (optionID, probability) in try validated(probabilities, id: id) {
            guard completed[optionID] != nil else {
                throw DecisionError.malformedResponse(
                    "Question \(id) has no option named \(optionID)."
                )
            }
            completed[optionID] = probability
        }
        guard completed[reported] != nil else {
            throw DecisionError.malformedResponse(
                "Question \(id) has no option named \(reported)."
            )
        }
        return completed
    }

    /// Checks a rating's score and probabilities against a scale of
    /// `levelCount` levels, and adds every level the record leaves out at
    /// zero.
    static func completed(
        _ probabilities: [Int: Double],
        score: Double,
        levelCount: Int,
        id: String
    ) throws -> [Int: Double] {
        // The score is an expected level index, so it lives on the scale.
        let top = Double(levelCount - 1)
        guard score.isFinite, score >= -1e-9, score <= top + 1e-9 else {
            throw DecisionError.malformedResponse(
                "Question \(id) has a score outside 0...\(levelCount - 1)."
            )
        }
        var completed: [Int: Double] = [:]
        for index in 0..<levelCount { completed[index] = 0 }
        for (index, probability) in try validated(probabilities, id: id) {
            guard completed[index] != nil else {
                throw DecisionError.malformedResponse(
                    "Question \(id) has no level at index \(index)."
                )
            }
            completed[index] = probability
        }
        return completed
    }

    /// Checks a verdict's probability.
    static func validatedProbability(_ probability: Double, id: String) throws -> Double {
        guard probability.isFinite, (0...1).contains(probability) else {
            throw DecisionError.malformedResponse(
                "Question \(id) has a probability outside 0...1."
            )
        }
        return probability
    }

    /// Checks a probability map: not empty, every value finite and at least
    /// zero, the sum above zero. It does not rescale; the typed readers do
    /// that when they build a `Distribution`.
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
        return probabilities
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

extension QuestionSpec.Kind {
    /// The name of the kind, for error messages.
    var kindName: String {
        switch self {
        case .choice: "a choice"
        case .rating: "a rating"
        case .verdict: "a verdict"
        }
    }
}
