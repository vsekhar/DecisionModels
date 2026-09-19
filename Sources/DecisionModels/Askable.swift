/// A type a question can ask for.
///
/// The declared property type picks the question kind at type-check time, so
/// `@Ask` expands to the same code for every property. See DESIGN.md 5.2.
public protocol Askable {
    /// The rich answer, such as `Choice<Self>`, that `$name` holds.
    associatedtype Projection: Sendable
    /// The wire questions this type asks under `id`.
    static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec]
    /// Reads the rich answer out of a response.
    static func projection(in answers: Answers, id: String) throws -> Projection
    /// Reduces the rich answer to the plain value.
    static func read(_ projection: Projection) -> Self
    /// The wire answers this property contributes under `id`.
    static func answers(from projection: Projection, id: String) -> Answers
}

/// A leaf answers one question, so it contributes one record. A nested
/// decision overrides this with its own, prefixed, answers.
extension Askable where Projection: Answer {
    public static func answers(from projection: Projection, id: String) -> Answers {
        Answers(records: [id: projection.record], quality: projection.quality)
    }
}

// MARK: Choice

/// An options enum asks one choice over its cases. The concrete type carries
/// `typealias Projection = Choice<Self>`; a default in a protocol extension
/// cannot be overridden by a refining protocol.
///
/// The typealias is the whole switch. A `RatingLevel` enum that declares
/// `Choice<Self>` asks a choice and loses its order; the `@Levels` macro
/// always writes `Rating<Self>`, so only hand-written conformances can get
/// this wrong.
extension Askable where Self: ChoiceOption & CaseIterable, Projection == Choice<Self> {
    public static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec] {
        [Choose<Self>(id, inquiry.instructions).spec]
    }

    public static func projection(in answers: Answers, id: String) throws -> Choice<Self> {
        try answers.choice(id, as: Self.self)
    }

    public static func read(_ projection: Choice<Self>) -> Self {
        projection.value
    }

    /// The answer a plain value stands for: this option, with no doubt.
    public static func certain(_ value: Self) -> Choice<Self> {
        Choice(certain: value)
    }
}

// MARK: Rating

/// A levels enum asks one rating over its cases, low to high.
extension Askable where Self: RatingLevel, Projection == Rating<Self> {
    public static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec] {
        [Rate<Self>(id, inquiry.instructions).spec]
    }

    public static func projection(in answers: Answers, id: String) throws -> Rating<Self> {
        try answers.rating(id, as: Self.self)
    }

    public static func read(_ projection: Rating<Self>) -> Self {
        projection.value
    }

    /// The answer a plain value stands for: this level, with no doubt.
    public static func certain(_ value: Self) -> Rating<Self> {
        Rating(certain: value)
    }
}

// MARK: Verdict

extension Bool: Askable {
    public typealias Projection = Verdict

    public static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec] {
        [Verify(id, inquiry.instructions, ifTrue: inquiry.ifTrue, ifFalse: inquiry.ifFalse).spec]
    }

    public static func projection(in answers: Answers, id: String) throws -> Verdict {
        try answers.verdict(id)
    }

    public static func read(_ projection: Verdict) -> Bool {
        projection.value
    }

    /// The answer a plain value stands for: this verdict, with no doubt.
    public static func certain(_ value: Bool) -> Verdict {
        Verdict(certain: value)
    }
}

// MARK: Optional

/// An optional asks the same question as its wrapped type. Only the optional
/// has the two-argument `read`, so a threshold on a plain property fails to
/// compile, which is the diagnostic we want.
extension Optional: Askable where Wrapped: Askable {
    public typealias Projection = Wrapped.Projection

    public static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec] {
        Wrapped.questions(id: id, inquiry)
    }

    public static func projection(in answers: Answers, id: String) throws -> Wrapped.Projection {
        try Wrapped.projection(in: answers, id: id)
    }

    public static func read(_ projection: Wrapped.Projection) -> Wrapped? {
        Wrapped.read(projection)
    }

    public static func answers(from projection: Wrapped.Projection, id: String) -> Answers {
        Wrapped.answers(from: projection, id: id)
    }
}

extension Optional where Wrapped: Askable, Wrapped.Projection: Answer {
    /// The value, or `nil` when the answer does not reach the bar.
    public static func read(
        _ projection: Wrapped.Projection,
        minimumConfidence: Double
    ) -> Wrapped? {
        projection.confidence >= minimumConfidence ? Wrapped.read(projection) : nil
    }
}

/// A `nil` plain value stores the uncertain answer, which gates back to `nil`.
/// Each kind keeps its own uncertain form, so the three extensions below stay
/// apart by the projection type, as `questions` and `read` do.
extension Optional where Wrapped: Askable & ChoiceOption & CaseIterable,
                         Wrapped.Projection == Choice<Wrapped> {
    public static func certain(_ value: Wrapped?) -> Choice<Wrapped> {
        value.map { Choice(certain: $0) } ?? .uncertain
    }
}

extension Optional where Wrapped: Askable & RatingLevel,
                         Wrapped.Projection == Rating<Wrapped> {
    public static func certain(_ value: Wrapped?) -> Rating<Wrapped> {
        value.map { Rating(certain: $0) } ?? .uncertain
    }
}

extension Optional where Wrapped == Bool {
    public static func certain(_ value: Bool?) -> Verdict {
        value.map { Verdict(certain: $0) } ?? .uncertain
    }
}
