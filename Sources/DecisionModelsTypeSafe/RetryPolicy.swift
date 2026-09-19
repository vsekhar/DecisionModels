/// How often to send again, and how long to wait between tries.
///
/// The provider retries a rate limit, an overload, and a transport failure.
/// It never retries a bad key or a request the service refused, because
/// sending those again cannot help.
public struct RetryPolicy: Sendable {
    /// How many more times to send after the first try.
    public var maxRetries: Int
    /// The wait before the first retry.
    public var initialBackoff: Duration
    /// The longest wait between two tries. It bounds a wait the service asks
    /// for with `Retry-After` as well, so a long header cannot park the call.
    public var maximumBackoff: Duration
    /// What each wait multiplies by.
    public var multiplier: Double

    public init(
        maxRetries: Int = 3,
        initialBackoff: Duration = .milliseconds(500),
        maximumBackoff: Duration = .seconds(8),
        multiplier: Double = 2
    ) {
        self.maxRetries = maxRetries
        self.initialBackoff = initialBackoff
        self.maximumBackoff = maximumBackoff
        self.multiplier = multiplier
    }

    /// Three retries, half a second, doubling, up to eight seconds.
    public static let `default` = RetryPolicy()

    /// One try and no more.
    public static let none = RetryPolicy(maxRetries: 0)

    /// The wait before retry number `retry`, counting from one.
    func backoff(retry: Int) -> Duration {
        guard retry >= 1 else { return .zero }
        var wait = initialBackoff
        for _ in 1..<retry {
            wait = wait * multiplier
            if wait >= maximumBackoff { return maximumBackoff }
        }
        return min(wait, maximumBackoff)
    }
}
