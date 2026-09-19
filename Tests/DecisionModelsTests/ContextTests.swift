import Testing

@testable import DecisionModels

/// How standing context reaches the model.
@Suite("Context")
struct ContextTests {
    private let question = Verify("unsafe", "Does the request break the policy?")

    private func session(
        context: [String: any StateRepresentable]
    ) -> (DecisionSession, FakeModel) {
        let model = FakeModel(
            answers: Answers(records: ["unsafe": .verdict(probability: 0.1)], quality: .calibrated)
        )
        return (DecisionSession(model: model, context: context), model)
    }

    private func state(of model: FakeModel) throws -> State {
        try #require(model.requests.first).state
    }

    @Test("An object state gains the context fields")
    func objectStateGainsContext() async throws {
        let (session, model) = session(context: ["policy": "Refunds within 30 days", "region": 7])

        _ = try await session.decide(
            Questionnaire { question },
            about: ["message": "I want my money back"] as State
        )

        #expect(
            try state(of: model)
                == .object([
                    "message": .text("I want my money back"),
                    "policy": .text("Refunds within 30 days"),
                    "region": .number(7),
                ])
        )
    }

    @Test("The state wins when both hold the same field")
    func stateWinsOnClash() async throws {
        let (session, model) = session(context: ["policy": "the standing policy"])

        _ = try await session.decide(
            Questionnaire { question },
            about: ["policy": "the policy of this call"] as State
        )

        #expect(try state(of: model) == .object(["policy": .text("the policy of this call")]))
    }

    @Test("A text state is wrapped in an object")
    func textStateIsWrapped() async throws {
        let (session, model) = session(context: ["policy": "Refunds within 30 days"])

        _ = try await session.decide(Questionnaire { question }, about: "I want my money back")

        #expect(
            try state(of: model)
                == .object([
                    "state": .text("I want my money back"),
                    "policy": .text("Refunds within 30 days"),
                ])
        )
    }

    @Test("An array state is wrapped the same way")
    func arrayStateIsWrapped() async throws {
        let (session, model) = session(context: ["policy": "Refunds within 30 days"])

        _ = try await session.decide(
            Questionnaire { question },
            about: ["first", "second"] as State
        )

        #expect(
            try state(of: model)
                == .object([
                    "state": .array([.text("first"), .text("second")]),
                    "policy": .text("Refunds within 30 days"),
                ])
        )
    }

    @Test("An empty context passes the state through")
    func emptyContextPassesThrough() async throws {
        let (session, model) = session(context: [:])

        _ = try await session.decide(Questionnaire { question }, about: "I want my money back")

        #expect(try state(of: model) == .text("I want my money back"))
    }
}
