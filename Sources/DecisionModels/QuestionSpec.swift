/// One question on the wire.
public struct QuestionSpec: Sendable, Codable, Hashable {
    /// The name the answer comes back under.
    public var id: String
    /// What to judge. A text or a structured object.
    public var instructions: State
    /// The shape of the answer space.
    public var kind: Kind

    public init(id: String, instructions: State, kind: Kind) {
        self.id = id
        self.instructions = instructions
        self.kind = kind
    }

    public enum Kind: Sendable, Codable, Hashable {
        case choice(options: [OptionSpec])
        case rating(levels: [Criterion])
        case verdict(ifTrue: Criterion?, ifFalse: Criterion?)
    }

    public struct OptionSpec: Sendable, Codable, Hashable {
        public var id: String
        public var criterion: Criterion

        public init(id: String, criterion: Criterion) {
            self.id = id
            self.criterion = criterion
        }
    }
}
