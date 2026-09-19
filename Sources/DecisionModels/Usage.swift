/// What requests cost. Sessions add these up.
public struct Usage: Sendable, Codable, Hashable, AdditiveArithmetic {
    public var inputTokens: Int
    public var outputTokens: Int
    public var requests: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, requests: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.requests = requests
    }

    /// Nothing spent yet.
    public static let zero = Usage()

    public static func + (left: Usage, right: Usage) -> Usage {
        Usage(
            inputTokens: left.inputTokens + right.inputTokens,
            outputTokens: left.outputTokens + right.outputTokens,
            requests: left.requests + right.requests
        )
    }

    public static func - (left: Usage, right: Usage) -> Usage {
        Usage(
            inputTokens: left.inputTokens - right.inputTokens,
            outputTokens: left.outputTokens - right.outputTokens,
            requests: left.requests - right.requests
        )
    }
}
