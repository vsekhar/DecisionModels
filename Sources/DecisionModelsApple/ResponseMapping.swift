#if canImport(FoundationModels)
import DecisionModels
import FoundationModels

/// What one generation said about one question.
enum QuestionOutcome: Sendable, Equatable {
    case choice(optionID: String)
    case rating(index: Int)
    case verdict(Bool)
}

/// Reads generated content into outcomes, then averages the draws into
/// answers.
///
/// Only the members that touch FoundationModels carry availability, so the
/// arithmetic stays testable on any OS.
enum ResponseMapping {
    /// Reads one generation: one outcome per question.
    ///
    /// A missing field, an option id the question does not list, and a level
    /// index off the scale are all malformed responses.
    @available(macOS 26, iOS 26, *)
    static func outcomes(
        from content: GeneratedContent,
        questionnaire: Questionnaire,
        fieldNames: [String: String]
    ) throws -> [String: QuestionOutcome] {
        var outcomes: [String: QuestionOutcome] = [:]
        for spec in questionnaire.specs {
            guard let field = fieldNames[spec.id] else {
                throw DecisionError.malformedResponse(
                    "Question \(spec.id) has no field in the schema."
                )
            }
            switch spec.kind {
            case .choice(let options):
                let optionID = try read(String.self, from: content, field: field, question: spec.id)
                guard options.contains(where: { $0.id == optionID }) else {
                    throw DecisionError.malformedResponse(
                        "Question \(spec.id) has no option named \(optionID)."
                    )
                }
                outcomes[spec.id] = .choice(optionID: optionID)
            case .rating(let levels):
                let index = try read(Int.self, from: content, field: field, question: spec.id)
                guard levels.indices.contains(index) else {
                    throw DecisionError.malformedResponse(
                        "Question \(spec.id) has no level at index \(index)."
                    )
                }
                outcomes[spec.id] = .rating(index: index)
            case .verdict:
                let flag = try read(Bool.self, from: content, field: field, question: spec.id)
                outcomes[spec.id] = .verdict(flag)
            }
        }
        return outcomes
    }

    /// Averages the draws into one answer per question.
    ///
    /// One draw gives one-hot probabilities and `.pointEstimate`. More draws
    /// give the empirical share of each option or level, and `.sampled`.
    static func answers(
        from draws: [[String: QuestionOutcome]],
        questionnaire: Questionnaire
    ) throws -> Answers {
        guard !draws.isEmpty else {
            throw DecisionError.malformedResponse("The model returned no draws.")
        }
        let total = Double(draws.count)
        var records: [String: AnswerRecord] = [:]
        for spec in questionnaire.specs {
            switch spec.kind {
            case .choice(let options):
                var counts: [String: Int] = [:]
                for option in options { counts[option.id] = 0 }
                for draw in draws {
                    guard case .choice(let optionID)? = draw[spec.id] else {
                        throw DecisionError.malformedResponse(
                            "Question \(spec.id) has no choice in the response."
                        )
                    }
                    guard let seen = counts[optionID] else {
                        throw DecisionError.malformedResponse(
                            "Question \(spec.id) has no option named \(optionID)."
                        )
                    }
                    counts[optionID] = seen + 1
                }
                // The first of a tie wins, so the same draws always name the
                // same option.
                var reported = options.first?.id ?? ""
                for option in options where (counts[option.id] ?? 0) > (counts[reported] ?? 0) {
                    reported = option.id
                }
                records[spec.id] = .choice(
                    reported: reported,
                    probabilities: counts.mapValues { Double($0) / total },
                    confidence: nil
                )
            case .rating(let levels):
                var counts: [Int: Int] = [:]
                for index in levels.indices { counts[index] = 0 }
                var sum = 0
                for draw in draws {
                    guard case .rating(let index)? = draw[spec.id] else {
                        throw DecisionError.malformedResponse(
                            "Question \(spec.id) has no rating in the response."
                        )
                    }
                    guard let seen = counts[index] else {
                        throw DecisionError.malformedResponse(
                            "Question \(spec.id) has no level at index \(index)."
                        )
                    }
                    counts[index] = seen + 1
                    sum += index
                }
                records[spec.id] = .rating(
                    score: Double(sum) / total,
                    probabilities: counts.mapValues { Double($0) / total },
                    confidence: nil
                )
            case .verdict:
                var yes = 0
                for draw in draws {
                    guard case .verdict(let flag)? = draw[spec.id] else {
                        throw DecisionError.malformedResponse(
                            "Question \(spec.id) has no verdict in the response."
                        )
                    }
                    if flag { yes += 1 }
                }
                records[spec.id] = .verdict(probability: Double(yes) / total)
            }
        }
        return Answers(
            records: records,
            quality: draws.count == 1 ? .pointEstimate : .sampled(count: draws.count)
        )
    }

    /// Reads one field, naming the question when it is not there.
    @available(macOS 26, iOS 26, *)
    private static func read<Value: ConvertibleFromGeneratedContent>(
        _ type: Value.Type,
        from content: GeneratedContent,
        field: String,
        question: String
    ) throws -> Value {
        do {
            return try content.value(type, forProperty: field)
        } catch {
            throw DecisionError.malformedResponse(
                "Question \(question) has no \(type) in the field \(field): \(error)."
            )
        }
    }
}
#endif
