/// Every answer of one response, by question id.
public struct Answers: Sendable, Codable, Hashable {
    public var records: [String: AnswerRecord]
    /// How much the probabilities can be trusted.
    public var quality: ProbabilityQuality

    public init(records: [String: AnswerRecord] = [:], quality: ProbabilityQuality) {
        self.records = records
        self.quality = quality
    }

    /// Reads the answer a typed question asks for.
    public subscript<Q: Question>(_ question: Q) -> Q.Answer {
        get throws {
            try question.answer(from: record(question.id), quality: quality)
        }
    }

    /// Reads a choice over an enum, mapping ids back through `CaseIterable`.
    public func choice<O: ChoiceOption & CaseIterable>(
        _ id: String,
        as type: O.Type = O.self
    ) throws -> Choice<O> {
        try AnswerReader.choice(record(id), id: id, options: Array(O.allCases), quality: quality)
    }

    /// Reads a rating over a level enum.
    public func rating<L: RatingLevel>(
        _ id: String,
        as type: L.Type = L.self
    ) throws -> Rating<L> {
        try AnswerReader.rating(record(id), id: id, quality: quality)
    }

    /// Reads a yes or no answer.
    public func verdict(_ id: String) throws -> Verdict {
        try AnswerReader.verdict(record(id), id: id, quality: quality)
    }

    /// Keeps the answers of one nested decision, so `bug.severity` becomes
    /// `severity`.
    public func scoped(to prefix: String) -> Answers {
        guard !prefix.isEmpty else { return self }
        let head = "\(prefix)."
        var scoped: [String: AnswerRecord] = [:]
        for (id, record) in records where id.hasPrefix(head) {
            scoped[String(id.dropFirst(head.count))] = record
        }
        return Answers(records: scoped, quality: quality)
    }

    /// Renames every answer, so `severity` becomes `bug.severity`.
    public func prefixed(_ prefix: String) -> Answers {
        guard !prefix.isEmpty else { return self }
        var prefixed: [String: AnswerRecord] = [:]
        for (id, record) in records { prefixed["\(prefix).\(id)"] = record }
        return Answers(records: prefixed, quality: quality)
    }

    private func record(_ id: String) throws -> AnswerRecord {
        guard let record = records[id] else {
            throw DecisionError.invalidQuestion(id: id, reason: "The response holds no answer.")
        }
        return record
    }
}
