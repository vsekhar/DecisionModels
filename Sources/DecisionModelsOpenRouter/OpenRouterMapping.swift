import DecisionModels
import Foundation

/// Joins the framework types to the wire types.
///
/// Every field OpenRouter keeps, the provider keeps: the named choice, the
/// score, and the reported confidence travel verbatim.
enum OpenRouterMapping {
    // MARK: Out

    /// Renders every question, by id.
    static func questions(_ questionnaire: Questionnaire) -> [String: OpenRouterRequest.Question] {
        var wire: [String: OpenRouterRequest.Question] = [:]
        for spec in questionnaire.specs {
            wire[spec.id] = question(spec)
        }
        return wire
    }

    /// Renders one question.
    static func question(_ spec: QuestionSpec) -> OpenRouterRequest.Question {
        switch spec.kind {
        case .choice(let options):
            var criteria: [String: State] = [:]
            for option in options {
                criteria[option.id] = criterion(option.criterion, summaryKey: "what")
            }
            return OpenRouterRequest.Question(
                type: .choice, instructions: spec.instructions, criteria: .object(criteria)
            )
        case .rating(let levels):
            let criteria = levels.map { criterion($0, summaryKey: "summary") }
            return OpenRouterRequest.Question(
                type: .score, instructions: spec.instructions, criteria: .array(criteria)
            )
        case .verdict(let ifTrue, let ifFalse):
            var sides: [String: State] = [:]
            if let ifTrue { sides["true"] = criterion(ifTrue, summaryKey: "what") }
            if let ifFalse { sides["false"] = criterion(ifFalse, summaryKey: "what") }
            return OpenRouterRequest.Question(
                type: .noul,
                instructions: spec.instructions,
                criteria: sides.isEmpty ? nil : .object(sides)
            )
        }
    }

    /// Renders what an option, a level, or a side means.
    ///
    /// A criterion that holds nothing but its summary goes as a plain string.
    /// Anything richer goes as an object, and an empty field is left out.
    static func criterion(_ criterion: Criterion, summaryKey: String) -> State {
        let structured =
            criterion.notFor != nil || !criterion.examples.isEmpty || !criterion.signals.isEmpty
        guard structured else { return .text(criterion.summary) }

        var fields: [String: State] = [:]
        if !criterion.summary.isEmpty { fields[summaryKey] = .text(criterion.summary) }
        if let notFor = criterion.notFor, !notFor.isEmpty { fields["not_for"] = .text(notFor) }
        if !criterion.examples.isEmpty {
            fields["examples"] = .array(criterion.examples.map(State.text))
        }
        if !criterion.signals.isEmpty {
            fields["signals"] = .array(criterion.signals.map(State.text))
        }
        return .object(fields)
    }

    // MARK: Back

    /// Reads a successful reply. The request id is the body's `id`; an empty
    /// one counts as none.
    static func modelResponse(_ data: Data) throws -> ModelResponse {
        let body = try decode(OpenRouterResponse.self, from: data)
        return ModelResponse(
            answers: try answers(body.answers),
            usage: Usage(
                inputTokens: body.usage?.inputTokens ?? 0,
                outputTokens: body.usage?.outputTokens ?? 0,
                requests: 1
            ),
            requestID: body.id.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    /// Turns wire answers into records. The model behind the endpoint reports
    /// trained probabilities, so the whole response is calibrated.
    static func answers(_ wire: [String: OpenRouterAnswer]) throws -> Answers {
        var records: [String: AnswerRecord] = [:]
        for (id, answer) in wire {
            records[id] = try record(answer, id: id)
        }
        return Answers(records: records, quality: .calibrated)
    }

    /// Turns one wire answer into a record.
    static func record(_ answer: OpenRouterAnswer, id: String) throws -> AnswerRecord {
        switch answer {
        case .choice(let choice):
            return .choice(
                reported: choice.choice,
                probabilities: choice.probabilities,
                confidence: choice.confidence
            )
        case .score(let score):
            var probabilities: [Int: Double] = [:]
            for (key, probability) in score.probabilities {
                guard let index = Int(key) else {
                    throw DecisionError.malformedResponse(
                        "Question \(id) names the level \(key), which is not a whole number."
                    )
                }
                probabilities[index] = probability
            }
            return .rating(
                score: score.score, probabilities: probabilities, confidence: score.confidence
            )
        case .noul(let noul):
            return .verdict(probability: noul.noul)
        }
    }

    /// Decodes a body, and calls anything it cannot read a malformed response.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecisionError {
            throw error
        } catch {
            throw DecisionError.malformedResponse(
                "The reply is not the JSON this provider expects: \(error)"
            )
        }
    }
}
