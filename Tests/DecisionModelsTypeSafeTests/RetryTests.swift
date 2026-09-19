import DecisionModels
import Foundation
import Testing

@testable import DecisionModelsTypeSafe

@Suite("Jev retries")
struct RetryTests {
    /// Sends one request against a script and gives back the error, when
    /// there is one, with what the model did.
    private func run(
        _ replies: [Reply],
        retry: RetryPolicy = .default
    ) async -> (error: (any Error)?, transport: ScriptedTransport, clock: FakeClock) {
        let fake = harness(replies, retry: retry)
        do {
            _ = try await fake.model.decide(
                DecisionRequest(state: ticket, questionnaire: triage())
            )
            return (nil, fake.transport, fake.clock)
        } catch {
            return (error, fake.transport, fake.clock)
        }
    }

    @Test("A rate limit twice, then an answer")
    func retriesThenSucceeds() async throws {
        let outcome = await run([.status(429), .status(429), .ok(sampleResponse)])
        #expect(outcome.error == nil)
        #expect(outcome.transport.sent.count == 3)
        #expect(outcome.clock.waited == [.milliseconds(500), .seconds(1)])
    }

    @Test("A rate limit that never lets up ends in rateLimited")
    func rateLimited() async throws {
        let policy = RetryPolicy.default
        let outcome = await run(Array(repeating: .status(429), count: policy.maxRetries + 1))
        guard case .rateLimited(let after)? = outcome.error as? DecisionError else {
            Issue.record("Expected a rate limit, got \(String(describing: outcome.error)).")
            return
        }
        #expect(after == nil)
        #expect(outcome.transport.sent.count == policy.maxRetries + 1)
        #expect(outcome.clock.waited == [.milliseconds(500), .seconds(1), .seconds(2)])
    }

    @Test("A Retry-After header sets the wait")
    func honoursRetryAfter() async throws {
        let outcome = await run([
            .status(429, headers: ["Retry-After": "2"]),
            .ok(sampleResponse),
        ])
        #expect(outcome.error == nil)
        #expect(outcome.clock.waited == [.seconds(2)])
    }

    @Test("A long Retry-After waits no longer than the policy allows")
    func capsRetryAfter() async throws {
        let outcome = await run([
            .status(429, headers: ["Retry-After": "3600"]),
            .ok(sampleResponse),
        ])
        #expect(outcome.error == nil)
        #expect(outcome.clock.waited == [RetryPolicy.default.maximumBackoff])
    }

    @Test("A Retry-After header rides along when the retries run out")
    func reportsRetryAfter() async throws {
        let outcome = await run(
            Array(repeating: .status(429, headers: ["Retry-After": "30"]), count: 4)
        )
        guard case .rateLimited(let after)? = outcome.error as? DecisionError else {
            Issue.record("Expected a rate limit, got \(String(describing: outcome.error)).")
            return
        }
        #expect(after == .seconds(30))
    }

    @Test("An overload that never lets up ends in overloaded")
    func overloaded() async throws {
        let outcome = await run(Array(repeating: .status(529), count: 4))
        guard case .overloaded? = outcome.error as? DecisionError else {
            Issue.record("Expected an overload, got \(String(describing: outcome.error)).")
            return
        }
        #expect(outcome.transport.sent.count == 4)
        #expect(outcome.clock.waited.count == 3)
    }

    @Test("An overload that lets up answers")
    func overloadThenSucceeds() async throws {
        let outcome = await run([.status(529), .ok(sampleResponse)])
        #expect(outcome.error == nil)
        #expect(outcome.transport.sent.count == 2)
    }

    @Test("A bad key is not worth sending again")
    func unauthorized() async throws {
        let outcome = await run([.status(401, body: #"{"message": "invalid api key"}"#)])
        guard case .unauthorized? = outcome.error as? DecisionError else {
            Issue.record("Expected unauthorized, got \(String(describing: outcome.error)).")
            return
        }
        #expect(outcome.transport.sent.count == 1)
        #expect(outcome.clock.waited.isEmpty)
    }

    @Test("A refused request names what the service said")
    func invalidQuestion() async throws {
        let outcome = await run([
            .status(422, body: #"{"message": "criteria must hold at least two levels"}"#)
        ])
        guard case .invalidQuestion(let id, let reason)? = outcome.error as? DecisionError else {
            Issue.record("Expected an invalid question, got \(String(describing: outcome.error)).")
            return
        }
        #expect(id.isEmpty)
        #expect(reason == "criteria must hold at least two levels")
        #expect(outcome.transport.sent.count == 1)
        #expect(outcome.clock.waited.isEmpty)
    }

    @Test("A nested error message comes through too")
    func nestedErrorMessage() async throws {
        let outcome = await run([
            .status(422, body: #"{"error": {"type": "validation", "message": "unknown question type"}}"#)
        ])
        guard case .invalidQuestion(_, let reason)? = outcome.error as? DecisionError else {
            Issue.record("Expected an invalid question, got \(String(describing: outcome.error)).")
            return
        }
        #expect(reason == "unknown question type")
    }

    @Test("Any other status travels as a transport failure")
    func otherStatus() async throws {
        let outcome = await run([.status(503, body: "gateway is down")])
        guard case .transport(let underlying)? = outcome.error as? DecisionError else {
            Issue.record("Expected a transport failure, got \(String(describing: outcome.error)).")
            return
        }
        let server = try #require(underlying as? JevServerError)
        #expect(server.status == 503)
        #expect(server.message == "gateway is down")
        #expect(outcome.transport.sent.count == 1)
    }

    @Test("A transport failure is worth sending again")
    func retriesTransportFailures() async throws {
        let outcome = await run([.failure(), .ok(sampleResponse)])
        #expect(outcome.error == nil)
        #expect(outcome.transport.sent.count == 2)
        #expect(outcome.clock.waited == [.milliseconds(500)])
    }

    @Test("A transport failure that keeps coming back is a transport error")
    func givesUpOnTransportFailures() async throws {
        let outcome = await run(Array(repeating: .failure(), count: 4))
        guard case .transport? = outcome.error as? DecisionError else {
            Issue.record("Expected a transport failure, got \(String(describing: outcome.error)).")
            return
        }
        #expect(outcome.transport.sent.count == 4)
    }

    @Test("A timeout is a timeout, not a transport failure")
    func timeout() async throws {
        let outcome = await run([.failure(.timedOut)], retry: .none)
        guard case .timeout? = outcome.error as? DecisionError else {
            Issue.record("Expected a timeout, got \(String(describing: outcome.error)).")
            return
        }
        #expect(outcome.transport.sent.count == 1)
    }

    @Test("A policy of none sends once")
    func noRetries() async throws {
        let outcome = await run([.status(429)], retry: .none)
        guard case .rateLimited? = outcome.error as? DecisionError else {
            Issue.record("Expected a rate limit, got \(String(describing: outcome.error)).")
            return
        }
        #expect(outcome.transport.sent.count == 1)
        #expect(outcome.clock.waited.isEmpty)
    }

    @Test("The backoff doubles and then stops growing")
    func backoffCeiling() {
        let policy = RetryPolicy.default
        #expect(policy.backoff(retry: 1) == .milliseconds(500))
        #expect(policy.backoff(retry: 2) == .seconds(1))
        #expect(policy.backoff(retry: 3) == .seconds(2))
        #expect(policy.backoff(retry: 5) == .seconds(8))
        #expect(policy.backoff(retry: 50) == .seconds(8))
        #expect(policy.backoff(retry: 0) == .zero)
    }

    @Test("A timeout on the request becomes the timeout of the call")
    func passesTheTimeout() async throws {
        let fake = harness([.ok(sampleResponse)])
        _ = try await fake.model.decide(
            DecisionRequest(state: ticket, questionnaire: triage(), timeout: .milliseconds(2500))
        )
        let sent = try #require(fake.transport.sent.first)
        #expect(isClose(sent.timeoutInterval, 2.5))
    }

    @Test("The timeout bounds the whole call, not one attempt")
    func timeoutBoundsTheWholeCall() async throws {
        // Every attempt times out. However many run, none of them and no
        // wait between them may pass the deadline.
        let fake = harness(Array(repeating: .failure(.timedOut), count: 4))
        do {
            _ = try await fake.model.decide(
                DecisionRequest(state: ticket, questionnaire: triage(), timeout: .seconds(5))
            )
            Issue.record("The call should give up.")
        } catch let error as DecisionError {
            guard case .timeout = error else {
                Issue.record("Expected a timeout, got \(error).")
                return
            }
        }
        #expect(fake.clock.elapsed <= .seconds(5))
        #expect(fake.transport.sent.allSatisfy { $0.timeoutInterval <= 5 })
    }

    @Test("A wait never runs past the caller's deadline")
    func capsThePauseAtTheDeadline() async throws {
        let fake = harness([.status(429, headers: ["Retry-After": "8"]), .ok(sampleResponse)])
        do {
            _ = try await fake.model.decide(
                DecisionRequest(state: ticket, questionnaire: triage(), timeout: .seconds(2))
            )
            Issue.record("The call should give up.")
        } catch let error as DecisionError {
            guard case .timeout = error else {
                Issue.record("Expected a timeout, got \(error).")
                return
            }
        }
        #expect(fake.clock.waited == [.seconds(2)])
        #expect(fake.clock.elapsed <= .seconds(2))
        #expect(fake.transport.sent.count == 1)
    }

    @Test("A hung attempt is cut off and the next one answers")
    func attemptTimeoutLetsTheRetryAnswer() async throws {
        let fake = harness([.failure(.timedOut), .ok(sampleResponse)])
        _ = try await fake.model.decide(
            DecisionRequest(state: ticket, questionnaire: triage(), timeout: .seconds(60))
        )
        #expect(fake.transport.sent.count == 2)
        let first = try #require(fake.transport.sent.first)
        #expect(isClose(first.timeoutInterval, 10))
        #expect(fake.clock.waited == [.milliseconds(500)])
        #expect(fake.clock.elapsed == .seconds(10) + .milliseconds(500))
    }

    @Test("A transport that hangs every time ends in timeout after more than one try")
    func everyAttemptHangs() async throws {
        let fake = harness(Array(repeating: .failure(.timedOut), count: 4))
        do {
            _ = try await fake.model.decide(
                DecisionRequest(state: ticket, questionnaire: triage(), timeout: .seconds(60))
            )
            Issue.record("The call should give up.")
        } catch let error as DecisionError {
            guard case .timeout = error else {
                Issue.record("Expected a timeout, got \(error).")
                return
            }
        }
        #expect(fake.transport.sent.count == 4)
        #expect(fake.transport.sent.allSatisfy { isClose($0.timeoutInterval, 10) })
        // Four attempts of ten seconds and three backoffs.
        #expect(fake.clock.elapsed == .seconds(43) + .milliseconds(500))
    }

    @Test("The deadline cuts the last attempt shorter than the attempt timeout")
    func deadlineBoundsTheAttemptTimeout() async throws {
        let fake = harness(Array(repeating: .failure(.timedOut), count: 4))
        do {
            _ = try await fake.model.decide(
                DecisionRequest(state: ticket, questionnaire: triage(), timeout: .seconds(25))
            )
            Issue.record("The call should give up.")
        } catch let error as DecisionError {
            guard case .timeout = error else {
                Issue.record("Expected a timeout, got \(error).")
                return
            }
        }
        // Ten, a half-second wait, ten, a one-second wait, and what is left.
        #expect(fake.transport.sent.count == 3)
        let last = try #require(fake.transport.sent.last)
        #expect(isClose(last.timeoutInterval, 3.5))
        #expect(fake.clock.elapsed == .seconds(25))
    }

    @Test("The attempt timeout applies without a deadline")
    func attemptTimeoutWithoutDeadline() async throws {
        let fake = harness([.ok(sampleResponse)])
        _ = try await fake.model.decide(DecisionRequest(state: ticket, questionnaire: triage()))
        let sent = try #require(fake.transport.sent.first)
        #expect(isClose(sent.timeoutInterval, 10))
    }

    @Test("Without an attempt timeout, one hung attempt spends the whole deadline")
    func noAttemptTimeout() async throws {
        let fake = harness(
            Array(repeating: .failure(.timedOut), count: 4),
            retry: RetryPolicy(attemptTimeout: nil)
        )
        do {
            _ = try await fake.model.decide(
                DecisionRequest(state: ticket, questionnaire: triage(), timeout: .seconds(60))
            )
            Issue.record("The call should give up.")
        } catch let error as DecisionError {
            guard case .timeout = error else {
                Issue.record("Expected a timeout, got \(error).")
                return
            }
        }
        #expect(fake.transport.sent.count == 1)
        let first = try #require(fake.transport.sent.first)
        #expect(isClose(first.timeoutInterval, 60))
        #expect(fake.clock.elapsed == .seconds(60))
    }

    @Test("Without an attempt timeout or a deadline, the transport's default stands")
    func noAttemptTimeoutAndNoDeadline() async throws {
        let fake = harness([.ok(sampleResponse)], retry: RetryPolicy(attemptTimeout: nil))
        _ = try await fake.model.decide(DecisionRequest(state: ticket, questionnaire: triage()))
        let sent = try #require(fake.transport.sent.first)
        let untouched = URLRequest(url: Jev.productionHost)
        #expect(sent.timeoutInterval == untouched.timeoutInterval)
    }

    @Test("A cancelled call throws CancellationError, not a provider error")
    func cancellationMidPause() async throws {
        let cancelWhileWaiting: @Sendable (Duration) async -> Void = { _ in
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let fake = harness(
            [.status(429), .ok(sampleResponse)],
            sleep: cancelWhileWaiting
        )
        let call = Task {
            try await fake.model.decide(DecisionRequest(state: ticket, questionnaire: triage()))
        }
        let result = await call.result
        guard case .failure(let error) = result else {
            Issue.record("A cancelled call should not answer.")
            return
        }
        #expect(error is CancellationError)
        #expect(fake.transport.sent.count == 1)
    }

    @Test("A cancelled transport is a cancellation too")
    func cancellationFromTheTransport() async throws {
        let outcome = await run([.failure(.cancelled)])
        #expect(outcome.error is CancellationError)
        #expect(outcome.transport.sent.count == 1)
        #expect(outcome.clock.waited.isEmpty)
    }

    @Test("Jev answers one question at a time")
    func rejectsRepeatedSamples() async throws {
        let fake = harness([.ok(sampleResponse)])
        do {
            _ = try await fake.model.decide(
                DecisionRequest(state: ticket, questionnaire: triage(), samples: 3)
            )
            Issue.record("Repeated samples should not go out.")
        } catch let error as DecisionError {
            guard case .unsupported(.repeatedSamples) = error else {
                Issue.record("Expected repeated samples, got \(error).")
                return
            }
        }
        #expect(fake.transport.sent.isEmpty)
    }
}
