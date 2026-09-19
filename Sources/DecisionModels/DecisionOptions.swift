/// How one call runs.
///
/// A session holds one of these as its defaults. A value passed to a call
/// replaces the session's entirely, as `GenerationOptions` does in Foundation
/// Models; copy `session.options` to change one field.
public struct DecisionOptions: Sendable {
    /// How long the caller waits.
    public var timeout: Duration?
    /// How many draws to take, at least one. More than one needs a model
    /// that repeats.
    public var samples: Int
    /// The floor for the response. A worse response throws.
    public var minimumProbabilityQuality: ProbabilityQuality?
    /// Tags that travel with the request into records and logs.
    public var metadata: [String: String]

    public init(
        timeout: Duration? = nil,
        samples: Int = 1,
        minimumProbabilityQuality: ProbabilityQuality? = nil,
        metadata: [String: String] = [:]
    ) {
        precondition(samples >= 1, "A call takes at least one sample.")
        self.timeout = timeout
        self.samples = samples
        self.minimumProbabilityQuality = minimumProbabilityQuality
        self.metadata = metadata
    }
}
