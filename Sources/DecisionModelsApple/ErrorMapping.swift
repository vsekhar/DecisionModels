#if canImport(FoundationModels)
import DecisionModels
import FoundationModels

/// Turns Foundation Models failures into `DecisionError` cases, so that
/// application code never sees an Apple error type.
enum ErrorMapping {
    /// Maps one error.
    ///
    /// `contextTokens` names the limit the device reported, so a context
    /// overflow can say what it overflowed.
    @available(macOS 26, iOS 26, *)
    static func decisionError(from error: any Error, contextTokens: Int?) -> DecisionError {
        if let decisionError = error as? DecisionError { return decisionError }
        guard let generation = error as? LanguageModelSession.GenerationError else {
            return .transport(error)
        }
        switch generation {
        case .guardrailViolation:
            return .guardrailViolation
        case .refusal:
            return .refused
        case .exceededContextWindowSize:
            return .contextSizeExceeded(limit: contextTokens, estimated: nil)
        case .rateLimited:
            return .rateLimited(retryAfter: nil)
        // The words that went in, or the JSON that came back, did not work
        // out. Either way the response is not usable.
        case .unsupportedLanguageOrLocale(let context):
            return .malformedResponse(context.debugDescription)
        case .decodingFailure(let context):
            return .malformedResponse(context.debugDescription)
        // The schema this questionnaire asks for is one the device will not
        // generate against, so the fault is in the question, not the answer.
        // No one question owns it, so the id is empty.
        case .unsupportedGuide(let context):
            return .invalidQuestion(id: "", reason: context.debugDescription)
        // The model's files are not on the device yet: the same state that
        // availability reports as not ready.
        case .assetsUnavailable:
            return .unavailable(.modelNotReady)
        // The device is already busy with another request. Waiting and asking
        // again is the answer, which is what `overloaded` means.
        case .concurrentRequests:
            return .overloaded
        @unknown default:
            return .transport(error)
        }
    }
}
#endif
