/// A model that answers a questionnaire about some state.
///
/// One method, one forward pass. There is no conversation and no streaming.
public protocol DecisionModel: Sendable {
    /// Who answers.
    var identity: DecisionModelIdentity { get }
    /// What the model can do. The session checks every request against it.
    var capabilities: DecisionModelCapabilities { get }
    /// Whether the model can answer now.
    var availability: DecisionModelAvailability { get async }
    /// Answers every question of the request in one pass.
    func decide(_ request: DecisionRequest) async throws -> ModelResponse
    /// Gets the model ready. The default does nothing.
    func prewarm() async
}

extension DecisionModel {
    public func prewarm() async {}
}

/// Which model answered.
public struct DecisionModelIdentity: Sendable, Codable, Hashable {
    /// The provider, such as `typesafe`, `apple`, or `test`.
    public var provider: String
    /// The model, such as `jev-1.13.0` or `on-device`.
    public var name: String

    public init(provider: String, name: String) {
        self.provider = provider
        self.name = name
    }
}
