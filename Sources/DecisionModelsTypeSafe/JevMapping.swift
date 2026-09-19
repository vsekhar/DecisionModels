import DecisionModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Joins the framework types to the wire types.
///
/// Every field the service keeps, the provider keeps: the named choice, the
/// score, and the reported confidence travel verbatim.
enum JevMapping {
    // MARK: Out

    /// Renders every question, by id.
    static func questions(_ questionnaire: Questionnaire) -> [String: JevRequest.Question] {
        var wire: [String: JevRequest.Question] = [:]
        for spec in questionnaire.specs {
            wire[spec.id] = question(spec)
        }
        return wire
    }

    /// Renders one question.
    static func question(_ spec: QuestionSpec) -> JevRequest.Question {
        switch spec.kind {
        case .choice(let options):
            var criteria: [String: State] = [:]
            for option in options {
                criteria[option.id] = criterion(option.criterion, summaryKey: "what")
            }
            return JevRequest.Question(
                type: .choice, instructions: spec.instructions, criteria: .object(criteria)
            )
        case .rating(let levels):
            let criteria = levels.map { criterion($0, summaryKey: "summary") }
            return JevRequest.Question(
                type: .score, instructions: spec.instructions, criteria: .array(criteria)
            )
        case .verdict(let ifTrue, let ifFalse):
            var sides: [String: State] = [:]
            if let ifTrue { sides["true"] = criterion(ifTrue, summaryKey: "what") }
            if let ifFalse { sides["false"] = criterion(ifFalse, summaryKey: "what") }
            return JevRequest.Question(
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

    /// Reads a successful reply.
    static func modelResponse(data: Data, response: HTTPURLResponse) throws -> ModelResponse {
        let body = try decode(JevResponse.self, from: data)
        return ModelResponse(
            answers: try answers(body.answers),
            usage: Usage(
                inputTokens: body.usage?.inputTokens ?? 0,
                outputTokens: body.usage?.outputTokens ?? 0,
                requests: 1
            ),
            requestID: JevError.requestID(response)
        )
    }

    /// Turns wire answers into records. Jev reports trained probabilities, so
    /// the whole response is calibrated.
    static func answers(_ wire: [String: JevAnswer]) throws -> Answers {
        var records: [String: AnswerRecord] = [:]
        for (id, answer) in wire {
            records[id] = try record(answer, id: id)
        }
        return Answers(records: records, quality: .calibrated)
    }

    /// Turns one wire answer into a record.
    static func record(_ answer: JevAnswer, id: String) throws -> AnswerRecord {
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

    /// Reads the model list.
    static func modelCards(_ data: Data) throws -> [ModelCard] {
        try decode(JevModelList.self, from: data).models.map {
            ModelCard(name: $0.name, description: $0.description, releaseDate: $0.releaseDate)
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
