#if canImport(FoundationModels)
import DecisionModels
import FoundationModels
import Testing

@testable import DecisionModelsApple

@Suite("ErrorMapping")
struct ErrorMappingTests {
    @Test("Every generation failure becomes a decision error")
    func mapsEveryCase() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "why")

        expect(.guardrailViolation(context), isGuardrailViolation)
        expect(
            .refusal(LanguageModelSession.GenerationError.Refusal(transcriptEntries: []), context),
            isRefused
        )
        expect(.rateLimited(context), isRateLimited)
        expect(.unsupportedLanguageOrLocale(context), isMalformed)
        expect(.decodingFailure(context), isMalformed)
        expect(.unsupportedGuide(context), isInvalidQuestion)
        expect(.assetsUnavailable(context), isModelNotReady)
        expect(.concurrentRequests(context), isOverloaded)
    }

    @Test("A guide the device will not take blames the questionnaire")
    func unsupportedGuideIsAnInvalidQuestion() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "no anyOf")

        let mapped = ErrorMapping.decisionError(
            from: LanguageModelSession.GenerationError.unsupportedGuide(context),
            contextTokens: 4096
        )

        guard case .invalidQuestion(let id, let reason) = mapped else {
            Issue.record("An unsupported guide mapped to \(mapped).")
            return
        }
        // No one question owns a schema the device refuses.
        #expect(id == "")
        #expect(reason == "no anyOf")
    }

    private func isModelNotReady(_ error: DecisionError) -> Bool {
        if case .unavailable(.modelNotReady) = error { return true }
        return false
    }

    private func isOverloaded(_ error: DecisionError) -> Bool {
        if case .overloaded = error { return true }
        return false
    }

    private func isInvalidQuestion(_ error: DecisionError) -> Bool {
        if case .invalidQuestion = error { return true }
        return false
    }

    @Test("A context overflow carries the device's limit")
    func contextOverflowCarriesTheLimit() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "too long")

        let mapped = ErrorMapping.decisionError(
            from: LanguageModelSession.GenerationError.exceededContextWindowSize(context),
            contextTokens: 4096
        )

        guard case .contextSizeExceeded(let limit, let estimated) = mapped else {
            Issue.record("A context overflow mapped to \(mapped).")
            return
        }
        #expect(limit == 4096)
        #expect(estimated == nil)
    }

    @Test("A malformed response keeps the framework's own words")
    func malformedKeepsTheMessage() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "bad JSON")

        let mapped = ErrorMapping.decisionError(
            from: LanguageModelSession.GenerationError.decodingFailure(context),
            contextTokens: 4096
        )

        guard case .malformedResponse(let message) = mapped else {
            Issue.record("A decoding failure mapped to \(mapped).")
            return
        }
        #expect(message == "bad JSON")
    }

    @Test("A decision error passes through unchanged")
    func decisionErrorsPassThrough() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let mapped = ErrorMapping.decisionError(from: DecisionError.timeout, contextTokens: 4096)

        guard case .timeout = mapped else {
            Issue.record("A timeout mapped to \(mapped).")
            return
        }
    }

    @Test("Anything else travels as transport")
    func otherErrorsAreTransport() {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        struct Whatever: Error {}

        #expect(isTransport(ErrorMapping.decisionError(from: Whatever(), contextTokens: nil)))
    }

    // MARK: Helpers

    @available(macOS 26, iOS 26, *)
    private func expect(
        _ error: LanguageModelSession.GenerationError,
        _ matches: (DecisionError) -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let mapped = ErrorMapping.decisionError(from: error, contextTokens: 4096)
        if !matches(mapped) {
            Issue.record("\(error) mapped to \(mapped).", sourceLocation: sourceLocation)
        }
    }

    private func isGuardrailViolation(_ error: DecisionError) -> Bool {
        if case .guardrailViolation = error { return true }
        return false
    }

    private func isRefused(_ error: DecisionError) -> Bool {
        if case .refused = error { return true }
        return false
    }

    private func isRateLimited(_ error: DecisionError) -> Bool {
        if case .rateLimited(let retryAfter) = error { return retryAfter == nil }
        return false
    }

    private func isMalformed(_ error: DecisionError) -> Bool {
        if case .malformedResponse = error { return true }
        return false
    }

    private func isTransport(_ error: DecisionError) -> Bool {
        if case .transport = error { return true }
        return false
    }
}
#endif
