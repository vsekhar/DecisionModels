import DecisionModels
import DecisionModelsTestSupport
import Foundation
import Testing

@testable import DecisionModelsTypeSafe

/// These tests pass an empty environment, so what the shell holds makes no
/// difference to them.
@Suite("Jev availability")
struct AvailabilityTests {
    private func model(
        apiKey: String?,
        environment: [String: String] = [:],
        transport: ScriptedTransport
    ) -> Jev {
        Jev(version: "jev-latest", apiKey: apiKey, transport: transport, environment: environment)
    }

    @Test("No key, no model")
    func withoutAKey() async throws {
        let transport = ScriptedTransport([])
        let jev = model(apiKey: nil, transport: transport)
        guard case .unavailable(let reason) = await jev.availability else {
            Issue.record("A model with no key is not available.")
            return
        }
        guard case .notConfigured(let variable) = reason else {
            Issue.record("Expected a missing setting, got \(reason).")
            return
        }
        #expect(variable == "TYPESAFE_API_KEY")
        #expect(transport.sent.isEmpty)
    }

    @Test("A blank key counts as no key")
    func blankKey() async throws {
        let jev = model(apiKey: "   ", transport: ScriptedTransport([]))
        guard case .unavailable = await jev.availability else {
            Issue.record("A blank key is no key.")
            return
        }
    }

    @Test("The environment holds the key when the caller does not")
    func keyFromTheEnvironment() async throws {
        let jev = model(
            apiKey: nil,
            environment: ["TYPESAFE_API_KEY": "from-the-shell"],
            transport: ScriptedTransport([.ok(sampleResponse)])
        )
        guard case .available = await jev.availability else {
            Issue.record("A key in the environment makes the model available.")
            return
        }
    }

    @Test("A session with no key throws before it sends")
    func sessionThrowsUnavailable() async throws {
        let transport = ScriptedTransport([.ok(sampleResponse)])
        let session = DecisionSession(model: model(apiKey: nil, transport: transport))
        do {
            _ = try await session.decide(triage(), about: ticket)
            Issue.record("A model with no key should not answer.")
        } catch let error as DecisionError {
            guard case .unavailable(.notConfigured(let variable)) = error else {
                Issue.record("Expected an unavailable model, got \(error).")
                return
            }
            #expect(variable == "TYPESAFE_API_KEY")
        }
        #expect(transport.sent.isEmpty)
        #expect(session.usage == .zero)
    }

    @Test("A model with no key refuses a direct call too")
    func decideThrowsUnavailable() async throws {
        let transport = ScriptedTransport([.ok(sampleResponse)])
        let jev = model(apiKey: nil, transport: transport)
        do {
            _ = try await jev.decide(DecisionRequest(state: ticket, questionnaire: triage()))
            Issue.record("A model with no key should not answer.")
        } catch let error as DecisionError {
            guard case .unavailable = error else {
                Issue.record("Expected an unavailable model, got \(error).")
                return
            }
        }
        #expect(transport.sent.isEmpty)
    }

    @Test("A model with no key lists no models")
    func modelsThrowsUnavailable() async throws {
        let jev = model(apiKey: nil, transport: ScriptedTransport([]))
        await #expect(throws: DecisionError.self) {
            _ = try await jev.models()
        }
    }

    @Test("The identity and the capabilities say what Jev is")
    func identityAndCapabilities() {
        let jev = Jev(version: "jev-latest", apiKey: "k")
        #expect(jev.identity.provider == "typesafe")
        #expect(jev.identity.name == "jev-latest")
        #expect(Jev(version: "jev-preview", apiKey: "k").identity.name == "jev-preview")
        #expect(Jev(version: "jev-1.13.0", apiKey: "k").identity.name == "jev-1.13.0")

        let capabilities = jev.capabilities
        #expect(capabilities.probabilityQuality == .calibrated)
        #expect(capabilities.structuredCriteria)
        #expect(capabilities.structuredInstructions)
        #expect(capabilities.maximumOptionsPerChoice == 255)
        #expect(capabilities.maximumLevelsPerRating == 10)
        #expect(capabilities.maximumQuestionsPerRequest == nil)
        #expect(capabilities.contextTokens == 64_000)
        #expect(!capabilities.supportsRepeatedSamples)
    }

    @Test("A session rejects repeated samples before it sends")
    func sessionRejectsRepeatedSamples() async throws {
        let transport = ScriptedTransport([.ok(sampleResponse)])
        let session = DecisionSession(
            model: model(apiKey: "test-key", transport: transport),
            options: DecisionOptions(samples: 3)
        )
        do {
            _ = try await session.decide(triage(), about: ticket)
            Issue.record("Jev does not repeat a question.")
        } catch let error as DecisionError {
            guard case .unsupported(.repeatedSamples) = error else {
                Issue.record("Expected repeated samples, got \(error).")
                return
            }
        }
        #expect(transport.sent.isEmpty)
    }

    @Test("A session with a key answers through the transport")
    func sessionAnswers() async throws {
        let transport = ScriptedTransport([.ok(sampleResponse)])
        let session = DecisionSession(model: model(apiKey: "test-key", transport: transport))
        let answers = try await session.decide(triage(), about: ticket)
        #expect(answers.quality == .calibrated)
        #expect(try answers.choice("team", as: Team.self).value == .returns)
        #expect(transport.sent.count == 1)
        #expect(session.usage.inputTokens == 412)
        #expect(session.usage.requests == 1)
    }
}
