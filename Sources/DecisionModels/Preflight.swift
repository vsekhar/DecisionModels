/// Checks a request against a model before it goes out.
///
/// Every failure here is one the caller can see without a network call.
/// Sanity comes first: those are the caller's own mistakes, whatever the
/// model. The model's limits come after.
enum Preflight {
    static func check(
        _ questionnaire: Questionnaire,
        samples: Int,
        against capabilities: DecisionModelCapabilities
    ) throws {
        guard !questionnaire.specs.isEmpty else {
            throw DecisionError.invalidQuestion(id: "", reason: "The questionnaire has no questions.")
        }
        var ids: Set<String> = []
        for spec in questionnaire.specs {
            guard ids.insert(spec.id).inserted else {
                throw DecisionError.invalidQuestion(
                    id: spec.id, reason: "Two questions share the id."
                )
            }
            try checkSanity(spec)
        }

        if let limit = capabilities.maximumQuestionsPerRequest,
           questionnaire.specs.count > limit {
            throw DecisionError.unsupported(
                .tooManyQuestions(count: questionnaire.specs.count, limit: limit)
            )
        }
        for spec in questionnaire.specs {
            try checkFit(spec, against: capabilities)
        }
        if samples > 1, !capabilities.supportsRepeatedSamples {
            throw DecisionError.unsupported(.repeatedSamples)
        }
    }

    /// What is wrong with the question itself.
    private static func checkSanity(_ spec: QuestionSpec) throws {
        if case .null = spec.instructions {
            throw DecisionError.invalidQuestion(
                id: spec.id, reason: "The question has no instructions."
            )
        }
        switch spec.kind {
        case .choice(let options):
            guard !options.isEmpty else {
                throw DecisionError.invalidQuestion(
                    id: spec.id, reason: "A choice needs at least one option."
                )
            }
            var seen: Set<String> = []
            for option in options where !seen.insert(option.id).inserted {
                throw DecisionError.invalidQuestion(
                    id: spec.id, reason: "Two options share the id \(option.id)."
                )
            }
        case .rating(let levels):
            guard levels.count >= 2 else {
                throw DecisionError.invalidQuestion(
                    id: spec.id, reason: "A rating needs at least two levels."
                )
            }
        case .verdict:
            break
        }
    }

    /// What the model cannot take.
    private static func checkFit(
        _ spec: QuestionSpec,
        against capabilities: DecisionModelCapabilities
    ) throws {
        if !capabilities.structuredInstructions {
            guard case .text = spec.instructions else {
                throw DecisionError.unsupported(.structuredInstructions)
            }
        }
        switch spec.kind {
        case .choice(let options):
            if options.count > capabilities.maximumOptionsPerChoice {
                throw DecisionError.unsupported(.tooManyOptions(
                    id: spec.id,
                    count: options.count,
                    limit: capabilities.maximumOptionsPerChoice
                ))
            }
            try checkFit(criteria: options.map(\.criterion), against: capabilities)
        case .rating(let levels):
            if levels.count > capabilities.maximumLevelsPerRating {
                throw DecisionError.unsupported(.tooManyLevels(
                    id: spec.id,
                    count: levels.count,
                    limit: capabilities.maximumLevelsPerRating
                ))
            }
            try checkFit(criteria: levels, against: capabilities)
        case .verdict(let ifTrue, let ifFalse):
            try checkFit(criteria: [ifTrue, ifFalse].compactMap(\.self), against: capabilities)
        }
    }

    private static func checkFit(
        criteria: [Criterion],
        against capabilities: DecisionModelCapabilities
    ) throws {
        guard !capabilities.structuredCriteria else { return }
        for criterion in criteria where criterion.isStructured {
            throw DecisionError.unsupported(.structuredCriteria)
        }
    }
}

extension Criterion {
    /// Whether the criterion holds more than a summary. A model that reads
    /// only text would lose these fields.
    var isStructured: Bool {
        notFor != nil || !examples.isEmpty || !signals.isEmpty
    }
}
