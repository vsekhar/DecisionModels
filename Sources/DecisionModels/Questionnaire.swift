/// The questions of one request.
public struct Questionnaire: Sendable, Codable, Hashable {
    public var specs: [QuestionSpec]

    public init(_ specs: [QuestionSpec] = []) {
        self.specs = specs
    }

    public init(@QuestionnaireBuilder _ questions: () -> [any Question]) {
        self.specs = questions().map(\.spec)
    }

    public mutating func add(_ question: some Question) {
        specs.append(question.spec)
    }

    /// Renames every question, so `severity` becomes `bug.severity`.
    public func prefixed(_ prefix: String) -> Questionnaire {
        guard !prefix.isEmpty else { return self }
        return Questionnaire(specs.map { spec in
            var renamed = spec
            renamed.id = "\(prefix).\(spec.id)"
            return renamed
        })
    }
}
