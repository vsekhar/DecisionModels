/// How often to send again, how long to wait between tries, and how long
/// one try may take.
///
/// The provider retries a rate limit, an overload, and a transport failure.
/// It cuts off an attempt that runs past `attemptTimeout` and retries it
/// like a transport failure, so a hung connection costs one attempt, not
/// the whole call; when the retries run out, the call ends in
/// `DecisionError.timeout`. It never retries a bad key or a request the
/// service refused, because sending those again cannot help.
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
    /// The longest one attempt may take before the provider gives up on it
    /// and sends again. The caller's `DecisionRequest.timeout` still bounds
    /// the whole call, so an attempt gets this or the time left, whichever
    /// is less. `nil`, not zero, turns the cap off: each attempt then runs
    /// until the caller's deadline or, with no deadline, for the transport's
    /// own default.
    public var attemptTimeout: Duration?

    public init(
        maxRetries: Int = 3,
        initialBackoff: Duration = .milliseconds(500),
        maximumBackoff: Duration = .seconds(8),
        multiplier: Double = 2,
        attemptTimeout: Duration? = .seconds(10)
    ) {
        self.maxRetries = maxRetries
        self.initialBackoff = initialBackoff
        self.maximumBackoff = maximumBackoff
        self.multiplier = multiplier
        self.attemptTimeout = attemptTimeout
    }

    /// Three retries, half a second, doubling, up to eight seconds, and ten
    /// seconds an attempt.
    public static let `default` = RetryPolicy()

    /// One try and no more. The attempt still stops after ten seconds, or
    /// sooner under the caller's timeout.
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
