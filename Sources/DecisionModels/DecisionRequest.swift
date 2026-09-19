/// One request: every question, asked about one state.
public struct DecisionRequest: Sendable, Codable, Hashable {
    /// The material to judge.
    public let state: State
    /// The questions. A model answers them all in one pass.
    public let questionnaire: Questionnaire
    /// How many draws to take. One is a single pass.
    public let samples: Int
    /// How long the caller waits. `nil` leaves it to the provider.
    public let timeout: Duration?
    /// Tags for records and logs. A cache or a replay keys on the state,
    /// the questionnaire, and the samples, never on these.
    public let metadata: [String: String]

    public init(
        state: State,
        questionnaire: Questionnaire,
        samples: Int = 1,
        timeout: Duration? = nil,
        metadata: [String: String] = [:]
    ) {
        self.state = state
        self.questionnaire = questionnaire
        self.samples = samples
        self.timeout = timeout
        self.metadata = metadata
    }
}
