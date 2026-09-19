import Testing

@testable import DecisionModels

/// The session adds up what every call costs.
@Suite("Usage")
struct UsageTests {
    @Test("Usage accumulates across concurrent calls")
    func concurrentCallsAccumulate() async throws {
        let model = FakeModel(
            answers: triageAnswers,
            usage: Usage(inputTokens: 3, outputTokens: 2, requests: 1)
        )
        let session = DecisionSession(model: model)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    _ = try? await session.decide(TicketTriage.self, about: "broken")
                }
            }
        }

        #expect(session.usage == Usage(inputTokens: 60, outputTokens: 40, requests: 20))
        #expect(model.callCount == 20)
    }

    @Test("A new session has spent nothing")
    func startsAtZero() {
        let session = DecisionSession(model: FakeModel(answers: triageAnswers))
        #expect(session.usage == .zero)
    }

    @Test("Usage adds and subtracts")
    func arithmetic() {
        let first = Usage(inputTokens: 10, outputTokens: 4, requests: 1)
        let second = Usage(inputTokens: 5, outputTokens: 1, requests: 1)
        #expect(first + second == Usage(inputTokens: 15, outputTokens: 5, requests: 2))
        #expect(first - second == Usage(inputTokens: 5, outputTokens: 3, requests: 0))
        #expect(first + .zero == first)
    }

    @Test("A response rejected for quality still counts")
    func rejectedResponseCounts() async {
        let model = FakeModel(
            answers: Answers(records: triageAnswers.records, quality: .pointEstimate),
            usage: Usage(inputTokens: 7, outputTokens: 1, requests: 1)
        )
        let session = DecisionSession(
            model: model,
            options: DecisionOptions(minimumProbabilityQuality: .calibrated)
        )

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }
        guard case .insufficientProbabilityQuality = error else {
            Issue.record("Expected insufficientProbabilityQuality, got \(String(describing: error))")
            return
        }
        #expect(session.usage == Usage(inputTokens: 7, outputTokens: 1, requests: 1))
    }
}
