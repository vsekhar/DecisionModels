import DecisionModels
import DecisionModelsTestSupport
import Foundation
import Testing

@testable import DecisionModelsOpenRouter

/// Every documented status, mapped after the retries the policy allows.
@Suite("OpenRouterAlpha errors")
struct ErrorTests {
    /// Sends one request against a script and gives back the error, when
    /// there is one, with what the model did. One try by default, so a test
    /// of the mapping needs one scripted reply.
    private func run(
        _ replies: [Reply],
        retry: RetryPolicy = .none
    ) async -> (error: DecisionError?, transport: ScriptedTransport, clock: FakeClock) {
        let fake = harness(replies, retry: retry)
        do {
            _ = try await fake.model.decide(
                DecisionRequest(state: ticket, questionnaire: triage())
            )
            Issue.record("The call should fail.")
            return (nil, fake.transport, fake.clock)
        } catch let error as DecisionError {
            return (error, fake.transport, fake.clock)
        } catch {
            Issue.record("Expected a DecisionError, got \(error).")
            return (nil, fake.transport, fake.clock)
        }
    }

    @Test("400 is an invalid question that carries OpenRouter's message, sent once")
    func badRequest() async {
        let outcome = await run(
            [
                .status(
                    400,
                    body: #"{"error": {"code": 400, "message": "criteria is empty"}}"#
                )
            ],
            retry: .default
        )
        guard case .invalidQuestion(let id, let reason)? = outcome.error else {
            Issue.record("Expected an invalid question, got \(String(describing: outcome.error)).")
            return
        }
        #expect(id.isEmpty)
        #expect(reason == "criteria is empty")
        #expect(outcome.transport.sent.count == 1)
        #expect(outcome.clock.waited.isEmpty)
    }

    @Test("400 with no message still names the refusal")
    func badRequestWithoutMessage() async {
        let outcome = await run([.status(400, body: "")])
        guard case .invalidQuestion(_, let reason)? = outcome.error else {
            Issue.record("Expected an invalid question, got \(String(describing: outcome.error)).")
            return
        }
        #expect(reason == "OpenRouter refused the request.")
    }

    @Test("401 and 403 are unauthorized and not worth sending again", arguments: [401, 403])
    func unauthorized(status: Int) async {
        let body = #"{"error": {"code": 401, "message": "No auth credentials found"}}"#
        let outcome = await run([.status(status, body: body)], retry: .default)
        guard case .unauthorized? = outcome.error else {
            Issue.record("Expected unauthorized, got \(String(describing: outcome.error)).")
            return
        }
        #expect(outcome.transport.sent.count == 1)
        #expect(outcome.clock.waited.isEmpty)
    }

    @Test("402 is unavailable, with the message as the reason, sent once")
    func insufficientCredits() async {
        let outcome = await run(
            [.status(402, body: #"{"error": {"code": 402, "message": "Insufficient credits"}}"#)],
            retry: .default
        )
        guard case .unavailable(.other(let reason))? = outcome.error else {
            Issue.record("Expected an unavailable model, got \(String(describing: outcome.error)).")
            return
        }
        #expect(reason == "Insufficient credits")
        #expect(outcome.transport.sent.count == 1)
    }

    @Test("413 is a context overflow with no numbers, sent once")
    func payloadTooLarge() async {
        let outcome = await run([.status(413)], retry: .default)
        guard case .contextSizeExceeded(let limit, let estimated)? = outcome.error else {
            Issue.record("Expected a context overflow, got \(String(describing: outcome.error)).")
            return
        }
        #expect(limit == nil)
        #expect(estimated == nil)
        #expect(outcome.transport.sent.count == 1)
    }

    @Test("429 is sent again, then rate limited with the Retry-After it asked for")
    func rateLimited() async {
        let outcome = await run(
            Array(repeating: .status(429, headers: ["Retry-After": "7"]), count: 4),
            retry: .default
        )
        guard case .rateLimited(let after)? = outcome.error else {
            Issue.record("Expected a rate limit, got \(String(describing: outcome.error)).")
            return
        }
        #expect(after == .seconds(7))
        #expect(outcome.transport.sent.count == 4)
        #expect(outcome.clock.waited == [.seconds(7), .seconds(7), .seconds(7)])
    }

    @Test("503 is sent again, then overloaded")
    func overloaded() async {
        let outcome = await run(Array(repeating: .status(503), count: 4), retry: .default)
        guard case .overloaded? = outcome.error else {
            Issue.record("Expected an overload, got \(String(describing: outcome.error)).")
            return
        }
        #expect(outcome.transport.sent.count == 4)
        #expect(outcome.clock.waited.count == 3)
    }

    @Test("524 is sent again, then a timeout")
    func gatewayTimeout() async {
        let outcome = await run(Array(repeating: .status(524), count: 4), retry: .default)
        guard case .timeout? = outcome.error else {
            Issue.record("Expected a timeout, got \(String(describing: outcome.error)).")
            return
        }
        #expect(outcome.transport.sent.count == 4)
    }

    @Test("502 and 529 are sent again, then travel as server errors", arguments: [502, 529])
    func upstreamErrors(status: Int) async throws {
        let body = #"{"error": {"code": \#(status), "message": "Provider returned error"}}"#
        let outcome = await run(
            Array(repeating: .status(status, body: body), count: 4), retry: .default
        )
        let server = try #require(serverError(outcome.error))
        #expect(server.status == status)
        #expect(server.message == "Provider returned error")
        #expect(server.code == String(status))
        #expect(outcome.transport.sent.count == 4)
    }

    @Test("404 and 500 are not sent again and travel as server errors", arguments: [404, 500])
    func otherStatuses(status: Int) async throws {
        let body = #"{"error": {"code": "not_found", "message": "No such model"}}"#
        let outcome = await run([.status(status, body: body)], retry: .default)
        let server = try #require(serverError(outcome.error))
        #expect(server.status == status)
        #expect(server.message == "No such model")
        #expect(server.code == "not_found")
        #expect(outcome.transport.sent.count == 1)
        #expect(outcome.clock.waited.isEmpty)
    }

    @Test("The message falls back to the common fields and then to the body")
    func messageFallbacks() {
        func message(_ body: String) -> String? { OpenRouterError.message(in: Data(body.utf8)) }
        #expect(message(#"{"error": {"message": "nested"}, "message": "top"}"#) == "nested")
        #expect(message(#"{"message": "top level"}"#) == "top level")
        #expect(message(#"{"detail": "a detail"}"#) == "a detail")
        #expect(message(#"{"error": "a string"}"#) == "a string")
        #expect(message(#"{"error": {"detail": "nested detail"}}"#) == "nested detail")
        #expect(message("gateway is down") == "gateway is down")
        #expect(message("") == nil)
        #expect(OpenRouterError.code(in: Data(#"{"error": {"message": "no code"}}"#.utf8)) == nil)
    }

    @Test("The server error describes itself")
    func serverErrorDescription() {
        let full = OpenRouterServerError(
            status: 502, message: "Provider returned error", code: "502"
        )
        #expect(full.description == "OpenRouter answered 502 (502): Provider returned error")
        #expect(OpenRouterServerError(status: 500).description == "OpenRouter answered 500")
    }

    private func serverError(_ error: DecisionError?) -> OpenRouterServerError? {
        guard case .transport(let underlying)? = error else { return nil }
        return underlying as? OpenRouterServerError
    }
}
