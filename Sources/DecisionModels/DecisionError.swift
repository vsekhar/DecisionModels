/// What can go wrong. Providers translate their own failures into these cases.
public enum DecisionError: Error, Sendable {
    case unavailable(DecisionModelAvailability.Reason)
    case unsupported(Unsupported)
    case invalidQuestion(id: String, reason: String)
    case contextSizeExceeded(limit: Int?, estimated: Int?)
    case rateLimited(retryAfter: Duration?)
    case overloaded
    case unauthorized
    case timeout
    /// The model declined to answer.
    case refused
    /// Input or output tripped a safety filter.
    case guardrailViolation
    case insufficientProbabilityQuality(got: ProbabilityQuality, required: ProbabilityQuality)
    case malformedResponse(String)
    case transport(any Error)

    /// What the model cannot do.
    public enum Unsupported: Sendable {
        case structuredCriteria
        case structuredInstructions
        case tooManyOptions(id: String, count: Int, limit: Int)
        case tooManyLevels(id: String, count: Int, limit: Int)
        case tooManyQuestions(count: Int, limit: Int)
        case repeatedSamples
    }
}
