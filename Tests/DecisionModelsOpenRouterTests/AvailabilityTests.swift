import DecisionModels
import DecisionModelsTestSupport
import Foundation
import Testing

@testable import DecisionModelsOpenRouter

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// These tests pass an empty environment, so what the shell holds makes no
/// difference to them.
@Suite("OpenRouterAlpha availability")
struct AvailabilityTests {
    @Test("No key, no model")
    func withoutAKey() async throws {
        let fake = harness([.ok(documentedResponse)], apiKey: nil)
        guard case .unavailable(let reason) = await fake.model.availability else {
            Issue.record("A model with no key is not available.")
            return
        }
        guard case .notConfigured(let variable) = reason else {
            Issue.record("Expected a missing setting, got \(reason).")
            return
        }
        #expect(variable == "OPENROUTER_API_KEY")
        #expect(fake.transport.sent.isEmpty)
    }

    @Test("A blank key counts as no key")
    func blankKey() async throws {
        let fake = harness([], apiKey: "   ")
        guard case .unavailable = await fake.model.availability else {
            Issue.record("A blank key is no key.")
            return
        }
    }

    @Test("The environment holds the key when the caller does not")
    func keyFromTheEnvironment() async throws {
        let fake = harness(
            [.ok(documentedResponse)],
            apiKey: nil,
            environment: ["OPENROUTER_API_KEY": "from-the-shell"]
        )
        guard case .available = await fake.model.availability else {
            Issue.record("A key in the environment makes the model available.")
            return
        }
        _ = try await fake.model.decide(DecisionRequest(state: ticket, questionnaire: triage()))
        let sent = try #require(fake.transport.sent.first)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer from-the-shell")
    }

    @Test("A model with no key refuses a direct call before it sends")
    func decideThrowsUnavailable() async throws {
        let fake = harness([.ok(documentedResponse)], apiKey: nil)
        do {
            _ = try await fake.model.decide(DecisionRequest(state: ticket, questionnaire: triage()))
            Issue.record("A model with no key should not answer.")
        } catch let error as DecisionError {
            guard case .unavailable(.notConfigured(let variable)) = error else {
                Issue.record("Expected an unavailable model, got \(error).")
                return
            }
            #expect(variable == "OPENROUTER_API_KEY")
        }
        #expect(fake.transport.sent.isEmpty)
    }

    @Test("A session with no key throws before it sends")
    func sessionThrowsUnavailable() async throws {
        let fake = harness([.ok(documentedResponse)], apiKey: nil)
        let session = DecisionSession(model: fake.model)
        do {
            _ = try await session.decide(triage(), about: ticket)
            Issue.record("A model with no key should not answer.")
        } catch let error as DecisionError {
            guard case .unavailable(.notConfigured) = error else {
                Issue.record("Expected an unavailable model, got \(error).")
                return
            }
        }
        #expect(fake.transport.sent.isEmpty)
        #expect(session.usage == .zero)
    }

    @Test("The identity and the capabilities say what the model is")
    func identityAndCapabilities() {
        let model = OpenRouterAlpha(model: "typesafe/jev-1.13", apiKey: "k")
        #expect(model.identity.provider == "openrouter")
        #expect(model.identity.name == "typesafe/jev-1.13")
        #expect(OpenRouterAlpha(model: "vendor/other", apiKey: "k").identity.name == "vendor/other")

        let capabilities = model.capabilities
        #expect(capabilities.probabilityQuality == .calibrated)
        #expect(capabilities.structuredCriteria)
        #expect(capabilities.structuredInstructions)
        #expect(capabilities.maximumOptionsPerChoice == 255)
        #expect(capabilities.maximumLevelsPerRating == 10)
        #expect(capabilities.maximumQuestionsPerRequest == nil)
        #expect(capabilities.contextTokens == 64_000)
        #expect(!capabilities.supportsRepeatedSamples)
    }

    @Test("A session with a key answers through the transport")
    func sessionAnswers() async throws {
        let fake = harness([.ok(documentedResponse)])
        let session = DecisionSession(model: fake.model)
        let answers = try await session.decide(triage(), about: ticket)
        #expect(answers.quality == .calibrated)
        #expect(answers.records["is_bug"] == .verdict(probability: 0.96))
        #expect(fake.transport.sent.count == 1)
        #expect(session.usage.inputTokens == 476)
        #expect(session.usage.requests == 1)
    }
}
