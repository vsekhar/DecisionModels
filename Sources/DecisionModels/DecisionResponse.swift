/// A decision with everything the call learned about it.
public struct DecisionResponse<D: Decision>: Sendable {
    /// The decision itself.
    public let decision: D
    /// The wire-level answers, by question id.
    public let answers: Answers
    /// What this call cost.
    public let usage: Usage
    /// Which model answered.
    public let model: DecisionModelIdentity
    /// The provider's own id for the request.
    public let requestID: String?
    /// How long the call took, from check to decoded value.
    public let duration: Duration

    public init(
        decision: D,
        answers: Answers,
        usage: Usage,
        model: DecisionModelIdentity,
        requestID: String?,
        duration: Duration
    ) {
        self.decision = decision
        self.answers = answers
        self.usage = usage
        self.model = model
        self.requestID = requestID
        self.duration = duration
    }
}
