import DecisionModels
import DecisionModelsTestSupport
import Foundation
import Testing

@testable import DecisionModelsTypeSafe

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The documented reply, with one answer of each kind.
let sampleResponse = """
    {
      "model": "jev-1.13.0",
      "answers": {
        "team": {
          "type": "choice",
          "choice": "returns",
          "probabilities": {"returns": 0.91, "shipping": 0.06, "billing": 0.03},
          "confidence": 0.88
        },
        "severity": {
          "type": "score",
          "score": 1.3,
          "confidence": 0.54,
          "legend": {"0": "Cosmetic", "1": "Degraded", "2": "Blocking"},
          "probabilities": {"0": 0.0, "1": 0.7, "2": 0.3}
        },
        "refund": {"type": "noul", "noul": 0.87}
      },
      "usage": {"input_tokens": 412, "output_tokens": 63}
    }
    """

@Suite("Jev wire")
struct WireTests {
    /// One question of each kind: a choice with a structured option beside a
    /// plain one, a score with a structured level and structured
    /// instructions, and a noul with both sides.
    let questionnaire = Questionnaire([
        QuestionSpec(
            id: "team",
            instructions: "Which team should handle this ticket?",
            kind: .choice(options: [
                QuestionSpec.OptionSpec(
                    id: "returns",
                    criterion: Criterion(
                        "Exchanges and refunds",
                        notFor: "Payment disputes",
                        examples: ["wrong size", "arrived damaged"]
                    )
                ),
                QuestionSpec.OptionSpec(id: "shipping", criterion: "Delivery issues"),
            ])
        ),
        QuestionSpec(
            id: "severity",
            instructions: [
                "task": "Rate how bad the problem is",
                "scale": ["lowest": "0", "highest": "2"],
            ],
            kind: .rating(levels: [
                "Cosmetic; nothing stops working",
                Criterion(
                    "A feature is broken, but a workaround exists",
                    signals: ["reports an error"]
                ),
                "Blocking; no workaround exists",
            ])
        ),
        QuestionSpec(
            id: "refund",
            instructions: "Does the customer ask for a refund?",
            kind: .verdict(
                ifTrue: "The customer asks for money back",
                ifFalse: Criterion(
                    "The customer asks for anything else",
                    examples: ["an exchange"]
                )
            )
        ),
    ])

    let expectedRequest = """
        {
          "model": "jev-latest",
          "state": "Wrong size shoes arrived, I want my money back",
          "questions": {
            "team": {
              "type": "choice",
              "instructions": "Which team should handle this ticket?",
              "criteria": {
                "returns": {
                  "what": "Exchanges and refunds",
                  "not_for": "Payment disputes",
                  "examples": ["wrong size", "arrived damaged"]
                },
                "shipping": "Delivery issues"
              }
            },
            "severity": {
              "type": "score",
              "instructions": {
                "task": "Rate how bad the problem is",
                "scale": {"lowest": "0", "highest": "2"}
              },
              "criteria": [
                "Cosmetic; nothing stops working",
                {
                  "summary": "A feature is broken, but a workaround exists",
                  "signals": ["reports an error"]
                },
                "Blocking; no workaround exists"
              ]
            },
            "refund": {
              "type": "noul",
              "instructions": "Does the customer ask for a refund?",
              "criteria": {
                "true": "The customer asks for money back",
                "false": {
                  "what": "The customer asks for anything else",
                  "examples": ["an exchange"]
                }
              }
            }
          }
        }
        """

    // MARK: Out

    @Test("The request matches the documented shape")
    func encodesTheDocumentedRequest() async throws {
        let sent = try await send(questionnaire)
        let body = try #require(sent.httpBody)
        #expect(try object(body) == object(Data(expectedRequest.utf8)))
    }

    @Test("The call goes to the systemone endpoint with the key")
    func addsTheHeaders() async throws {
        let sent = try await send(questionnaire)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("A criterion with only a summary goes as a plain string")
    func plainCriterion() {
        #expect(JevMapping.criterion("Delivery issues", summaryKey: "what") == .text("Delivery issues"))
        #expect(
            JevMapping.criterion(Criterion("Delivery issues", notFor: "Refunds"), summaryKey: "what")
                == .object(["what": "Delivery issues", "not_for": "Refunds"])
        )
    }

    @Test("A noul with no sides sends no criteria")
    func bareVerdict() {
        let spec = QuestionSpec(
            id: "refund",
            instructions: "Asks for a refund?",
            kind: .verdict(ifTrue: nil, ifFalse: nil)
        )
        let question = JevMapping.question(spec)
        #expect(question.type == .noul)
        #expect(question.criteria == nil)
        let encoded = try? JSONEncoder().encode(question)
        #expect(!String(decoding: encoded ?? Data(), as: UTF8.self).contains("criteria"))
    }

    @Test("A request with no state sends an empty string as the state")
    func noStateSendsAnEmptyString() async throws {
        let body = try await sentBody(DecisionRequest(questionnaire: capital))
        #expect(body["state"] as? String == "")
        #expect((body["questions"] as? NSDictionary)?.count == 1)
    }

    @Test("A null state sends an empty string too")
    func nullStateSendsAnEmptyString() async throws {
        let body = try await sentBody(DecisionRequest(state: .null, questionnaire: capital))
        #expect(body["state"] as? String == "")
        #expect((body["questions"] as? NSDictionary)?.count == 1)
    }

    // MARK: Back

    @Test("The documented answers decode into records")
    func decodesTheDocumentedAnswers() async throws {
        let response = try await decide(reply: .ok(sampleResponse))
        let answers = response.answers

        #expect(answers.quality == .calibrated)

        let teamRecord = try #require(answers.records["team"])
        guard case .choice(let reported, let options, let choiceConfidence) = teamRecord else {
            Issue.record("The team answer is not a choice.")
            return
        }
        #expect(reported == "returns")
        #expect(options == ["returns": 0.91, "shipping": 0.06, "billing": 0.03])
        #expect(choiceConfidence == 0.88)

        let severityRecord = try #require(answers.records["severity"])
        guard case .rating(let score, let levels, let scoreConfidence) = severityRecord else {
            Issue.record("The severity answer is not a rating.")
            return
        }
        #expect(score == 1.3)
        #expect(levels == [0: 0.0, 1: 0.7, 2: 0.3])
        #expect(scoreConfidence == 0.54)

        #expect(answers.records["refund"] == .verdict(probability: 0.87))
    }

    @Test("The usage and the request id come back")
    func keepsUsageAndRequestID() async throws {
        let response = try await decide(
            reply: .ok(sampleResponse, headers: ["x-typesafe-request-id": "req_42"])
        )
        #expect(response.usage.inputTokens == 412)
        #expect(response.usage.outputTokens == 63)
        #expect(response.usage.requests == 1)
        #expect(response.requestID == "req_42")
    }

    @Test("A reply with no request id header says so")
    func missingRequestID() async throws {
        #expect(try await decide(reply: .ok(sampleResponse)).requestID == nil)
    }

    @Test("A typed answer reads the decoded record")
    func typedAnswers() async throws {
        let answers = try await decide(reply: .ok(sampleResponse)).answers
        #expect(try answers.choice("team", as: Team.self).value == .returns)
        #expect(try isClose(answers.rating("severity", as: Severity.self).score, 1.3))
        #expect(try answers.rating("severity", as: Severity.self).value == .degraded)
        #expect(try answers.verdict("refund").isTrue(atLeast: 0.8))
    }

    @Test("An answer type the provider does not know is malformed")
    func unknownAnswerType() async throws {
        let body = """
            {"model": "jev-1.13.0", "answers": {"team": {"type": "ranking", "order": ["a"]}}}
            """
        do {
            _ = try await decide(reply: .ok(body))
            Issue.record("The reply should not decode.")
        } catch let error as DecisionError {
            guard case .malformedResponse(let reason) = error else {
                Issue.record("Expected a malformed response, got \(error).")
                return
            }
            #expect(reason.contains("ranking"))
        }
    }

    @Test("A level key that is not a whole number is malformed")
    func nonIntegerLevelKey() async throws {
        let body = """
            {
              "model": "jev-1.13.0",
              "answers": {
                "severity": {"type": "score", "score": 1, "probabilities": {"low": 1.0}}
              }
            }
            """
        do {
            _ = try await decide(reply: .ok(body))
            Issue.record("The reply should not decode.")
        } catch let error as DecisionError {
            guard case .malformedResponse(let reason) = error else {
                Issue.record("Expected a malformed response, got \(error).")
                return
            }
            #expect(reason.contains("low"))
        }
    }

    @Test("A reply that is not the documented JSON is malformed")
    func garbledReply() async throws {
        await #expect(throws: DecisionError.self) {
            try await decide(reply: .ok("not json at all"))
        }
    }

    @Test("The model list reads both shapes")
    func modelList() throws {
        let listed = try JevMapping.modelCards(
            Data(
                """
                {"models": [
                  {"name": "jev-latest", "description": "The newest release", "release_date": "2026-08-01"},
                  {"name": "jev-1.13.0"}
                ]}
                """.utf8
            )
        )
        #expect(listed.map(\.name) == ["jev-latest", "jev-1.13.0"])
        #expect(listed[0].description == "The newest release")
        #expect(listed[0].releaseDate == "2026-08-01")
        #expect(listed[1].releaseDate == nil)

        let bare = try JevMapping.modelCards(Data("""
            [{"name": "jev-preview"}]
            """.utf8))
        #expect(bare.map(\.name) == ["jev-preview"])
    }

    // MARK: Helpers

    /// A question that carries its own facts, so the request needs no state.
    private var capital: Questionnaire {
        Questionnaire { Verify("capital", "Is Atlanta the capital of Georgia?") }
    }

    /// Sends a request to a scripted transport and returns the body it sent.
    private func sentBody(_ request: DecisionRequest) async throws -> NSDictionary {
        let fake = harness([.ok(sampleResponse)])
        _ = try? await fake.model.decide(request)
        return try object(#require(fake.transport.sent.first?.httpBody))
    }

    /// Sends a questionnaire to a scripted transport and returns the request.
    private func send(_ questionnaire: Questionnaire) async throws -> URLRequest {
        let fake = harness([.ok(sampleResponse)])
        _ = try? await fake.model.decide(
            DecisionRequest(state: ticket, questionnaire: questionnaire)
        )
        return try #require(fake.transport.sent.first)
    }

    /// Answers one request with the given reply.
    private func decide(reply: Reply) async throws -> ModelResponse {
        try await harness([reply]).model.decide(
            DecisionRequest(state: ticket, questionnaire: questionnaire)
        )
    }

    /// Reads JSON as a dictionary, so key order does not matter.
    private func object(_ data: Data) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}
