/// A Swift type that one request answers.
///
/// The macro writes the three members. A hand-written conformance works the
/// same way; see DESIGN.md section 12.
public protocol Decision: Askable, Sendable where Projection == Self {
    /// The questions, one per asked property.
    static var questions: Questionnaire { get }
    /// Reads a whole decision out of a response.
    init(answers: Answers) throws
    /// The wire-level answers this decision holds.
    var answers: Answers { get }
}

/// A decision nests in another decision: its questions take a dotted prefix
/// and its answers come back out of the same response.
extension Decision {
    public static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec] {
        let own: Questionnaire = Self.questions
        return own.prefixed(id).specs
    }

    public static func projection(in answers: Answers, id: String) throws -> Self {
        do {
            return try Self(answers: answers.scoped(to: id))
        } catch DecisionError.invalidQuestion(let inner, let reason) {
            // Name the question as the response knows it.
            throw DecisionError.invalidQuestion(id: "\(id).\(inner)", reason: reason)
        }
    }

    public static func read(_ projection: Self) -> Self {
        projection
    }

    public static func answers(from projection: Self, id: String) -> Answers {
        projection.answers.prefixed(id)
    }

    /// A plain decision is already its own answer.
    public static func certain(_ value: Self) -> Self {
        value
    }
}
