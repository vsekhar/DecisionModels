#if canImport(FoundationModels)
import DecisionModels
import FoundationModels
import Testing

@testable import DecisionModelsApple

/// What the adapter says about itself. Nothing here calls the model.
@Suite("GuidedGenerationModel")
struct GuidedGenerationModelTests {
    @Test("Availability maps one state to one state")
    func availabilityMaps() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }

        #expect(isAvailable(GuidedGenerationModel.availability(of: .available)))
        #expect(isDeviceNotEligible(
            GuidedGenerationModel.availability(of: .unavailable(.deviceNotEligible))
        ))
        #expect(isNotConfigured(
            GuidedGenerationModel.availability(of: .unavailable(.appleIntelligenceNotEnabled)),
            "Apple Intelligence"
        ))
        #expect(isModelNotReady(
            GuidedGenerationModel.availability(of: .unavailable(.modelNotReady))
        ))
    }

    @Test("The adapter names itself and its limits")
    func identityAndCapabilities() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let model = GuidedGenerationModel()

        #expect(model.identity.provider == "apple")
        #expect(model.identity.name == "system-language-model")

        let capabilities = model.capabilities
        #expect(capabilities.probabilityQuality == .sampled(count: .max))
        #expect(capabilities.structuredCriteria)
        #expect(capabilities.structuredInstructions)
        #expect(capabilities.maximumOptionsPerChoice == 64)
        #expect(capabilities.maximumLevelsPerRating == 10)
        #expect(capabilities.maximumQuestionsPerRequest == nil)
        #expect(capabilities.supportsRepeatedSamples)
        #expect((capabilities.contextTokens ?? 0) >= 4096)
    }

    @Test("One sample runs greedy, more than one runs warm")
    func samplingOptions() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }

        #expect(GuidedGenerationModel.generationOptions(samples: 1).sampling == .greedy)
        let many = GuidedGenerationModel.generationOptions(samples: 3)
        #expect(many.sampling != .greedy)
        #expect(many.temperature == 1.0)
    }

    // MARK: The deadline

    @Test("No timeout leaves every draw unbounded")
    func noTimeoutNoDeadline() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }

        #expect(try GuidedGenerationModel.remaining(
            until: nil, on: ContinuousClock()
        ) == nil)
    }

    @Test("The budget shrinks as the call spends it")
    func budgetShrinks() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)

        let first = try #require(
            try GuidedGenerationModel.remaining(until: deadline, on: clock)
        )
        let second = try #require(
            try GuidedGenerationModel.remaining(until: deadline, on: clock)
        )

        #expect(first <= .seconds(10))
        #expect(second <= first)
    }

    @Test("A spent budget throws before the draw starts")
    func spentBudgetThrows() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let clock = ContinuousClock()
        let deadline = clock.now - .seconds(1)

        do {
            _ = try GuidedGenerationModel.remaining(until: deadline, on: clock)
            Issue.record("A spent budget started another draw.")
        } catch DecisionError.timeout {
            // Expected.
        } catch {
            Issue.record("A spent budget threw \(error).")
        }
    }

    // MARK: Helpers

    private func isAvailable(_ availability: DecisionModelAvailability) -> Bool {
        if case .available = availability { return true }
        return false
    }

    private func isDeviceNotEligible(_ availability: DecisionModelAvailability) -> Bool {
        if case .unavailable(.deviceNotEligible) = availability { return true }
        return false
    }

    private func isModelNotReady(_ availability: DecisionModelAvailability) -> Bool {
        if case .unavailable(.modelNotReady) = availability { return true }
        return false
    }

    private func isNotConfigured(
        _ availability: DecisionModelAvailability,
        _ what: String
    ) -> Bool {
        if case .unavailable(.notConfigured(let named)) = availability { return named == what }
        return false
    }
}
#endif
