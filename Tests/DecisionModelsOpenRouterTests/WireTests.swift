import DecisionModels
import DecisionModelsTestSupport
import Foundation
import Testing

@testable import DecisionModelsOpenRouter

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@Suite("OpenRouterAlpha wire")
struct WireTests {
    // MARK: Out

    @Test("The request matches the documented example")
    func encodesTheDocumentedRequest() async throws {
        let sent = try await send()
        let body = try #require(sent.httpBody)
        #expect(try object(body) == object(Data(documentedRequest.utf8)))
    }

    @Test("The call goes to the alpha decisions endpoint with the key")
    func addsTheHeaders() async throws {
        let sent = try await send()
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.absoluteString == "https://openrouter.ai/api/alpha/decisions")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("A plain criterion goes as a string and a structured one as an object")
    func criteria() {
        #expect(
            OpenRouterMapping.criterion("Delivery issues", summaryKey: "what")
                == .text("Delivery issues")
        )
        #expect(
            OpenRouterMapping.criterion(
                Criterion(
                    "Exchanges and refunds", notFor: "Payment disputes", examples: ["wrong size"]
                ),
                summaryKey: "what"
            )
                == .object([
                    "what": "Exchanges and refunds",
                    "not_for": "Payment disputes",
                    "examples": .array(["wrong size"]),
                ])
        )
        #expect(
            OpenRouterMapping.criterion(
                Criterion("Degraded", signals: ["reports an error"]), summaryKey: "summary"
            )
                == .object(["summary": "Degraded", "signals": .array(["reports an error"])])
        )
    }

    @Test("A noul with no sides sends no criteria")
    func bareVerdict() {
        let spec = QuestionSpec(
            id: "is_bug", instructions: "A defect?", kind: .verdict(ifTrue: nil, ifFalse: nil)
        )
        let question = OpenRouterMapping.question(spec)
        #expect(question.type == .noul)
        #expect(question.criteria == nil)
    }

    // MARK: Back

    @Test("The documented answers decode into records")
    func decodesTheDocumentedAnswers() async throws {
        let response = try await decide(reply: .ok(documentedResponse))
        let answers = response.answers

        #expect(answers.quality == .calibrated)
        #expect(answers.records["is_bug"] == .verdict(probability: 0.96))

        let teamRecord = try #require(answers.records["team"])
        guard case .choice(let reported, let options, let confidence) = teamRecord else {
            Issue.record("The team answer is not a choice.")
            return
        }
        #expect(reported == "payments")
        #expect(options == ["account": 0, "frontend": 0.16, "payments": 0.84])
        #expect(confidence == 0.75)

        let urgencyRecord = try #require(answers.records["urgency"])
        guard case .rating(let score, let levels, let scoreConfidence) = urgencyRecord else {
            Issue.record("The urgency answer is not a rating.")
            return
        }
        #expect(score == 1.99)
        #expect(levels == [0: 0, 1: 0.01, 2: 0.99])
        #expect(scoreConfidence == 0.99)
    }

    @Test("The wire type keeps the id, the model, the provider, and the legend")
    func decodesTheWholeReply() throws {
        let body = try OpenRouterMapping.decode(
            OpenRouterResponse.self, from: Data(documentedResponse.utf8)
        )
        #expect(body.id == "gen-dec-1789738314-X5e5eKGQdvR9rblyX250")
        #expect(body.model == "typesafe/jev-1.13-20260917")
        #expect(body.provider == "TypeSafe")
        guard case .score(let urgency)? = body.answers["urgency"] else {
            Issue.record("The urgency answer is not a score.")
            return
        }
        #expect(urgency.legend?.count == 3)
        #expect(urgency.legend?["2"] == "Blocking revenue right now")
    }

    @Test("The usage and the request id come from the body")
    func keepsUsageAndRequestID() async throws {
        let response = try await decide(reply: .ok(documentedResponse))
        #expect(response.usage.inputTokens == 476)
        #expect(response.usage.outputTokens == 70)
        #expect(response.usage.requests == 1)
        #expect(response.requestID == "gen-dec-1789738314-X5e5eKGQdvR9rblyX250")
    }

    @Test("A reply with no id and no usage still answers")
    func missingRequestID() async throws {
        let body = #"{"answers": {"is_bug": {"type": "noul", "noul": 0.5}}}"#
        let response = try await decide(reply: .ok(body))
        #expect(response.requestID == nil)
        #expect(response.usage == Usage(inputTokens: 0, outputTokens: 0, requests: 1))
    }

    @Test("An empty id counts as no id")
    func emptyRequestID() async throws {
        let body = #"{"id": "", "answers": {"is_bug": {"type": "noul", "noul": 0.5}}}"#
        #expect(try await decide(reply: .ok(body)).requestID == nil)
    }

    @Test("An answer type the provider does not know is malformed")
    func unknownAnswerType() async {
        let body = #"{"id": "x", "answers": {"team": {"type": "ranking", "order": ["a"]}}}"#
        await expectMalformed(body, mentions: "ranking")
    }

    @Test("An answer with no probabilities is malformed")
    func missingProbabilities() async {
        let body = #"{"id": "x", "answers": {"team": {"type": "choice", "choice": "payments"}}}"#
        await expectMalformed(body, mentions: "probabilities")
    }

    @Test("A level key that is not a whole number is malformed")
    func nonIntegerLevelKey() async {
        let body = """
            {"answers": {"urgency": {"type": "score", "score": 1, "probabilities": {"low": 1.0}}}}
            """
        await expectMalformed(body, mentions: "low")
    }

    @Test("A reply that is not JSON is malformed")
    func garbledReply() async {
        await expectMalformed("not json at all", mentions: nil)
    }

    @Test("A 503 then a 200 sends twice")
    func retriesThroughTheClient() async throws {
        let fake = harness([.status(503), .ok(documentedResponse)])
        let response = try await fake.model.decide(
            DecisionRequest(state: ticket, questionnaire: triage())
        )
        #expect(response.requestID != nil)
        #expect(fake.transport.sent.count == 2)
        #expect(fake.clock.waited == [.milliseconds(500)])
    }

    @Test("Repeated samples are refused before anything is sent")
    func rejectsRepeatedSamples() async throws {
        let fake = harness([.ok(documentedResponse)])
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

    // MARK: Helpers

    /// Sends the fixture questionnaire to a scripted transport and returns
    /// the request.
    private func send() async throws -> URLRequest {
        let fake = harness([.ok(documentedResponse)])
        _ = try? await fake.model.decide(DecisionRequest(state: ticket, questionnaire: triage()))
        return try #require(fake.transport.sent.first)
    }

    /// Answers one request with the given reply.
    private func decide(reply: Reply) async throws -> ModelResponse {
        try await harness([reply]).model.decide(
            DecisionRequest(state: ticket, questionnaire: triage())
        )
    }

    /// Expects the reply to come back as a malformed response whose reason
    /// names `mentions`.
    private func expectMalformed(
        _ body: String,
        mentions: String?,
        _ location: SourceLocation = #_sourceLocation
    ) async {
        do {
            _ = try await decide(reply: .ok(body))
            Issue.record("The reply should not decode.", sourceLocation: location)
        } catch let error as DecisionError {
            guard case .malformedResponse(let reason) = error else {
                Issue.record(
                    "Expected a malformed response, got \(error).", sourceLocation: location
                )
                return
            }
            if let mentions {
                #expect(reason.contains(mentions), sourceLocation: location)
            }
        } catch {
            Issue.record("Expected a DecisionError, got \(error).", sourceLocation: location)
        }
    }

    /// Reads JSON as a dictionary, so key order does not matter.
    private func object(_ data: Data) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}
