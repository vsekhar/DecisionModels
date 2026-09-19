/// What a model gives back.
public struct ModelResponse: Sendable, Codable {
    /// Every answer, by question id.
    public let answers: Answers
    /// What the request cost.
    public let usage: Usage
    /// The provider's own id for the request, for support and logs.
    public let requestID: String?

    public init(answers: Answers, usage: Usage = .zero, requestID: String? = nil) {
        self.answers = answers
        self.usage = usage
        self.requestID = requestID
    }
}
