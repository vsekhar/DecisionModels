import DecisionModels
import DecisionModelsOpenRouter
import DecisionModelsTestSupport
import DecisionModelsTypeSafe
import Foundation
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// OpenRouter forwards the request to TypeSafe, so the state and the
/// questions the two providers send for one questionnaire must be the same
/// JSON. The two mappings are separate code on purpose. This test keeps them
/// from drifting apart.
@Suite("OpenRouterAlpha and Jev parity")
struct ParityTests {
    /// One question of each kind with every criterion structured, plus
    /// structured instructions: the shapes the documented example leaves out.
    let questionnaire = Questionnaire([
        QuestionSpec(
            id: "team",
            instructions: ["task": "Route the ticket", "tone": "terse"],
            kind: .choice(options: [
                QuestionSpec.OptionSpec(
                    id: "returns",
                    criterion: Criterion(
                        "Exchanges and refunds",
                        notFor: "Payment disputes",
                        examples: ["wrong size"]
                    )
                ),
                QuestionSpec.OptionSpec(
                    id: "billing",
                    criterion: Criterion("Payment problems", signals: ["mentions a charge"])
                ),
            ])
        ),
        QuestionSpec(
            id: "severity",
            instructions: "How bad is it?",
            kind: .rating(levels: [
                Criterion("Cosmetic", examples: ["a typo"]),
                "Degraded",
                Criterion("Blocking", notFor: "Slow but working"),
            ])
        ),
        QuestionSpec(
            id: "refund",
            instructions: "Does the customer ask for money back?",
            kind: .verdict(
                ifTrue: Criterion("Wants a refund", signals: ["money back"]), ifFalse: nil
            )
        ),
    ])

    /// A structured state, so the object path is covered too.
    let state: State = [
        "ticket": "Wrong size shoes arrived, I want my money back",
        "orders": .array(["A1", "B2"]),
    ]

    @Test("Both providers send the same state and the same questions")
    func sameStateAndQuestions() async throws {
        let jevTransport = ScriptedTransport([.status(500)])
        let openRouterTransport = ScriptedTransport([.status(500)])
        let request = DecisionRequest(state: state, questionnaire: questionnaire)
        _ = try? await Jev(
            version: "jev-latest", apiKey: "k", retry: .none, transport: jevTransport
        ).decide(request)
        _ = try? await OpenRouterAlpha(
            model: "typesafe/jev-1.13", apiKey: "k", retry: .none, transport: openRouterTransport
        ).decide(request)

        let fromJev = try object(#require(jevTransport.sent.first?.httpBody))
        let fromOpenRouter = try object(#require(openRouterTransport.sent.first?.httpBody))
        let questions = try #require(fromJev["questions"] as? NSDictionary)
        #expect(questions.count == 3)
        #expect(questions == fromOpenRouter["questions"] as? NSDictionary)
        let sentState = try #require(fromJev["state"] as? NSDictionary)
        #expect(sentState == fromOpenRouter["state"] as? NSDictionary)
        #expect(fromJev["model"] as? String == "jev-latest")
        #expect(fromOpenRouter["model"] as? String == "typesafe/jev-1.13")
    }

    /// Reads JSON as a dictionary, so key order does not matter.
    private func object(_ data: Data) throws -> NSDictionary {
        try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
    }
}
