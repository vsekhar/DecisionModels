import DecisionModels
import DecisionModelsTestSupport
import Foundation
import Testing

@testable import DecisionModelsOpenRouter

/// Tests that call OpenRouter. They cost money, so the suite sends one
/// request and no more.
///
/// Run them with the key in the environment:
///
/// ```sh
/// set -a; . ./.env; set +a; swift test --filter OpenRouterLive
/// ```
///
/// Without the key these tests fail. They never skip, because a green run
/// that talked to nothing says nothing.
@Suite("OpenRouterLive", .serialized)
struct OpenRouterLiveTests {
    /// The key, or a recorded failure that names what is missing.
    private func liveKey(_ location: SourceLocation = #_sourceLocation) -> String? {
        let key = ProcessInfo.processInfo.environment[OpenRouterAlpha.apiKeyVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else {
            Issue.record(
                """
                \(OpenRouterAlpha.apiKeyVariable) is not set, so the live tests cannot reach \
                OpenRouter. Run: set -a; . ./.env; set +a; swift test --filter OpenRouterLive
                """,
                sourceLocation: location
            )
            return nil
        }
        return key
    }

    @Test("OpenRouter triages the documented ticket")
    func triagesTheDocumentedTicket() async throws {
        guard let key = liveKey() else { return }

        let model = OpenRouterAlpha(model: "typesafe/jev-1.13", apiKey: key)
        let response = try await model.decide(
            DecisionRequest(state: ticket, questionnaire: triage(), timeout: .seconds(60))
        )
        let answers = response.answers

        // The response as a whole.
        #expect(answers.quality == .calibrated)
        #expect(response.usage.inputTokens > 0)
        #expect(response.requestID != nil)

        // The choice.
        let teamRecord = try #require(answers.records["team"])
        guard case .choice(let reported, let options, let confidence) = teamRecord else {
            Issue.record("The team answer is not a choice.")
            return
        }
        #expect(reported == "payments")
        #expect(options.count == 3)
        #expect(isClose(options.values.reduce(0, +), 1))
        if let confidence {
            #expect((0...1).contains(confidence))
        }

        // The score.
        let urgencyRecord = try #require(answers.records["urgency"])
        guard case .rating(let score, let levels, _) = urgencyRecord else {
            Issue.record("The urgency answer is not a rating.")
            return
        }
        #expect(levels.count == 3)
        #expect(isClose(levels.values.reduce(0, +), 1))
        #expect((0...2).contains(score))

        // The verdict.
        let bugRecord = try #require(answers.records["is_bug"])
        guard case .verdict(let probability) = bugRecord else {
            Issue.record("The is_bug answer is not a verdict.")
            return
        }
        #expect(probability > 0.5)
    }
}
