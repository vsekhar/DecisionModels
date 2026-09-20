import DecisionModels
import DecisionModelsTestSupport
import Foundation
import Testing

@testable import DecisionModelsTypeSafe

/// Tests that call the real service. They cost money, so the suite sends two
/// requests and no more.
///
/// Run them with the key in the environment:
///
/// ```sh
/// set -a; . ./.env; set +a; swift test --filter JevLive
/// ```
///
/// Without the key these tests fail. They never skip, because a green run
/// that talked to nothing says nothing.
@Suite("JevLive", .serialized)
struct JevLiveTests {
    /// The key, or a recorded failure that names what is missing.
    private func liveKey(_ location: SourceLocation = #_sourceLocation) -> String? {
        let key = ProcessInfo.processInfo.environment[Jev.apiKeyVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty else {
            Issue.record(
                """
                \(Jev.apiKeyVariable) is not set, so the live tests cannot reach the service. \
                Run: set -a; . ./.env; set +a; swift test --filter JevLive
                """,
                sourceLocation: location
            )
            return nil
        }
        return key
    }

    @Test("Jev triages a support ticket")
    func triagesATicket() async throws {
        guard let key = liveKey() else { return }

        let team = Choose<Team>("team", "Which team should handle this ticket?")
        let severity = Rate<Severity>("severity", "How severe is the problem for the customer?")
        let refund = Verify("refund", "Does the customer ask for a refund?")
        let questionnaire = Questionnaire {
            team
            severity
            refund
        }

        let model = Jev(version: "jev-latest", apiKey: key)
        let response = try await model.decide(
            DecisionRequest(state: ticket, questionnaire: questionnaire, timeout: .seconds(60))
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
        #expect(reported == "returns")
        #expect(isClose(options.values.reduce(0, +), 1))
        if let confidence {
            #expect((0...1).contains(confidence))
        }
        #expect(try answers[team].value == .returns)

        // The score.
        let severityRecord = try #require(answers.records["severity"])
        guard case .rating(let score, let levels, let scoreConfidence) = severityRecord else {
            Issue.record("The severity answer is not a rating.")
            return
        }
        #expect(levels.count == Severity.allCases.count)
        #expect(isClose(levels.values.reduce(0, +), 1))
        #expect((0...Double(Severity.allCases.count - 1)).contains(score))
        if let scoreConfidence {
            #expect((0...1).contains(scoreConfidence))
        }
        #expect(try answers[severity].legend.count == 3)

        // The verdict.
        let refundRecord = try #require(answers.records["refund"])
        guard case .verdict(let probability) = refundRecord else {
            Issue.record("The refund answer is not a verdict.")
            return
        }
        #expect(probability > 0.5)
        #expect(try answers[refund].value)
    }

    @Test("The account can call a Jev model")
    func listsModels() async throws {
        guard let key = liveKey() else { return }

        let listed = try await Jev(version: "jev-latest", apiKey: key).models()
        #expect(!listed.isEmpty)
        #expect(listed.contains { $0.name.hasPrefix("jev") })
    }
}
