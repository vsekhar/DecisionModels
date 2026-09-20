import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Sends a request, and sends it again while the failure says that helps.
///
/// Every HTTP provider goes through this client. It owns the rules that do
/// not depend on the service: the deadline, the budget for one attempt, the
/// waits between tries, the `Retry-After` cap, and cancellation. The
/// provider names the statuses worth sending again, and maps the final
/// reply to a `DecisionError` itself.
package struct HTTPClient: Sendable {
    private let transport: any HTTPTransport
    private let policy: RetryPolicy
    private let transient: @Sendable (Int) -> Bool
    private let sleep: @Sendable (Duration) async -> Void
    private let now: @Sendable () -> ContinuousClock.Instant

    /// Builds a client.
    ///
    /// `transient` names the statuses worth sending again. `sleep` and `now`
    /// are the real clock unless a test passes its own.
    package init(
        transport: any HTTPTransport,
        policy: RetryPolicy,
        transient: @escaping @Sendable (Int) -> Bool,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now }
    ) {
        self.transport = transport
        self.policy = policy
        self.transient = transient
        self.sleep = sleep
        self.now = now
    }

    // MARK: Sending

    /// Sends, and sends again while the failure says that helps.
    ///
    /// The timeout is what the caller waits for the answer, tries and waits
    /// counted in, so it becomes a deadline for the whole call and bounds
    /// every attempt and every pause under it. The policy's attempt timeout
    /// bounds each attempt on its own, so one hung attempt ends early and
    /// leaves time under the deadline for another.
    ///
    /// The reply that comes back is the last one: a 2xx, a transient status
    /// once the retries run out, or a status the predicate rejects. The
    /// caller maps a refused reply. A transport failure that outlasts the
    /// retries is `DecisionError.timeout` when the attempt timed out and
    /// `DecisionError.transport` otherwise. The caller's own cancellation
    /// travels as `CancellationError`.
    package func send(
        _ request: URLRequest,
        timeout: Duration? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let deadline = timeout.map { now() + $0 }
        var retries = 0
        while true {
            var attempt = request
            if let budget = try attemptBudget(before: deadline) {
                attempt.timeoutInterval = budget.timeInterval
            }
            do {
                let (data, response) = try await transport.send(attempt)
                let status = response.statusCode
                let worthAnotherTry = !(200..<300).contains(status) && transient(status)
                guard worthAnotherTry, retries < policy.maxRetries else { return (data, response) }
                retries += 1
                // A service that asks for a long wait still waits no longer
                // than the policy allows.
                let asked = Self.retryAfter(response) ?? policy.backoff(retry: retries)
                try await pause(min(asked, policy.maximumBackoff), until: deadline)
            } catch let error as DecisionError {
                throw error
            } catch {
                // The caller's own cancellation travels as itself.
                if let cancellation = Self.cancellation(error) { throw cancellation }
                guard retries < policy.maxRetries else {
                    throw Self.decisionError(transport: error)
                }
                retries += 1
                try await pause(policy.backoff(retry: retries), until: deadline)
            }
        }
    }

    /// How long the next attempt may take: the policy's attempt timeout or
    /// the time left before the deadline, whichever is less. With neither,
    /// the transport's own default stands.
    private func attemptBudget(before deadline: ContinuousClock.Instant?) throws -> Duration? {
        try [policy.attemptTimeout, deadline.map(left(until:))].compactMap { $0 }.min()
    }

    /// Waits between two tries, and gives up when the caller has.
    private func pause(
        _ duration: Duration,
        until deadline: ContinuousClock.Instant?
    ) async throws {
        try Task.checkCancellation()
        var wait = duration
        if let deadline { wait = min(wait, try left(until: deadline)) }
        await sleep(wait)
        try Task.checkCancellation()
    }

    /// How much of the caller's time is left. None left is a timeout.
    private func left(until deadline: ContinuousClock.Instant) throws -> Duration {
        let remaining = now().duration(to: deadline)
        guard remaining > .zero else { throw DecisionError.timeout }
        return remaining
    }

    // MARK: Failures

    /// Maps a failure that never reached the service.
    private static func decisionError(transport error: any Error) -> DecisionError {
        if let error = error as? URLError, error.code == .timedOut { return .timeout }
        return .transport(error)
    }

    /// The caller's own cancellation, when that is what went wrong.
    ///
    /// Cancellation is not a provider failure, so it travels as itself and
    /// `catch is CancellationError` works at the call site.
    private static func cancellation(_ error: any Error) -> CancellationError? {
        if error is CancellationError { return CancellationError() }
        if let error = error as? URLError, error.code == .cancelled { return CancellationError() }
        return nil
    }

    /// The `Retry-After` header, read as a count of seconds.
    ///
    /// A date, a negative count, or anything else that is not a number
    /// reads as no header.
    package static func retryAfter(_ response: HTTPURLResponse) -> Duration? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        guard let seconds = Double(header.trimmingCharacters(in: .whitespaces)),
            seconds.isFinite, seconds >= 0
        else { return nil }
        return .seconds(seconds)
    }
}

extension Duration {
    /// The duration as a count of seconds, for `URLRequest`.
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
