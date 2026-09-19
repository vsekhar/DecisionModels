/// What one `@Ask` marker says about a question.
///
/// The macro turns its arguments into this value and hands it to `Askable`,
/// which picks the question kind from the declared type.
public struct Inquiry: Sendable {
    /// What to judge. A text, or a structured object where the model takes one.
    public var instructions: State
    /// What a yes means.
    public var ifTrue: Criterion?
    /// What a no means.
    public var ifFalse: Criterion?

    public init(
        _ instructions: State = .null,
        ifTrue: Criterion? = nil,
        ifFalse: Criterion? = nil
    ) {
        self.instructions = instructions
        self.ifTrue = ifTrue
        self.ifFalse = ifFalse
    }
}
