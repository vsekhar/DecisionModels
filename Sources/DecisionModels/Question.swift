/// A typed question value. Its `Answer` type is what the answers give back.
public protocol Question: Sendable {
    associatedtype Answer: DecisionModels.Answer
    /// The name the answer comes back under.
    var id: String { get }
    /// The wire-level question.
    var spec: QuestionSpec { get }
    /// Reads a record, with the quality the response reports.
    func answer(from record: AnswerRecord, quality: ProbabilityQuality) throws -> Answer
}

extension Question {
    public var id: String { spec.id }

    /// Reads a record on its own. The answer claims no better than a point
    /// estimate, because a record alone does not say.
    public func answer(from record: AnswerRecord) throws -> Answer {
        try answer(from: record, quality: .pointEstimate)
    }
}

/// Asks the model to name one option.
public struct Choose<Option: ChoiceOption>: Question {
    public let id: String
    public let instructions: State
    /// The options, kept so that ids map back to values.
    public let options: [Option]

    public init(_ id: String, _ instructions: State, among options: [Option]) {
        self.id = id
        self.instructions = instructions
        self.options = options
    }

    public init(_ id: String, _ instructions: State) where Option: CaseIterable {
        self.init(id, instructions, among: Array(Option.allCases))
    }

    public var spec: QuestionSpec {
        QuestionSpec(
            id: id,
            instructions: instructions,
            kind: .choice(options: options.map {
                QuestionSpec.OptionSpec(id: $0.optionID, criterion: $0.criterion)
            })
        )
    }

    public func answer(
        from record: AnswerRecord,
        quality: ProbabilityQuality
    ) throws -> Choice<Option> {
        try AnswerReader.choice(record, id: id, options: options, quality: quality)
    }
}

/// Asks the model to place the state on an ordered scale.
public struct Rate<Level: RatingLevel>: Question {
    public let id: String
    public let instructions: State

    public init(_ id: String, _ instructions: State, levels: Level.Type = Level.self) {
        self.id = id
        self.instructions = instructions
    }

    public var spec: QuestionSpec {
        QuestionSpec(
            id: id,
            instructions: instructions,
            kind: .rating(levels: Level.levels.map(\.criterion))
        )
    }

    public func answer(
        from record: AnswerRecord,
        quality: ProbabilityQuality
    ) throws -> Rating<Level> {
        try AnswerReader.rating(record, id: id, quality: quality)
    }
}

/// Asks the model a yes or no question.
public struct Verify: Question {
    public let id: String
    public let instructions: State
    public let ifTrue: Criterion?
    public let ifFalse: Criterion?

    public init(
        _ id: String,
        _ instructions: State,
        ifTrue: Criterion? = nil,
        ifFalse: Criterion? = nil
    ) {
        self.id = id
        self.instructions = instructions
        self.ifTrue = ifTrue
        self.ifFalse = ifFalse
    }

    public var spec: QuestionSpec {
        QuestionSpec(
            id: id,
            instructions: instructions,
            kind: .verdict(ifTrue: ifTrue, ifFalse: ifFalse)
        )
    }

    public func answer(
        from record: AnswerRecord,
        quality: ProbabilityQuality
    ) throws -> Verdict {
        try AnswerReader.verdict(record, id: id, quality: quality)
    }
}

/// Collects question values into a questionnaire.
///
/// The builder supports `if` and `for`.
@resultBuilder
public enum QuestionnaireBuilder {
    public static func buildExpression(_ question: some Question) -> [any Question] { [question] }

    public static func buildExpression(_ questions: [any Question]) -> [any Question] { questions }

    public static func buildBlock(_ parts: [any Question]...) -> [any Question] {
        parts.flatMap(\.self)
    }

    public static func buildOptional(_ part: [any Question]?) -> [any Question] { part ?? [] }

    public static func buildEither(first part: [any Question]) -> [any Question] { part }

    public static func buildEither(second part: [any Question]) -> [any Question] { part }

    public static func buildArray(_ parts: [[any Question]]) -> [any Question] {
        parts.flatMap(\.self)
    }

    public static func buildLimitedAvailability(_ part: [any Question]) -> [any Question] { part }
}
