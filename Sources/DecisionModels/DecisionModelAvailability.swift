/// Whether a model can answer now.
///
/// DESIGN.md section 10. `DecisionError` names the reason, so the type lives
/// here until the model protocol lands.
public enum DecisionModelAvailability: Sendable {
    case available
    case unavailable(Reason)

    public enum Reason: Sendable {
        /// Missing API key, missing entitlement.
        case notConfigured(String)
        case offline
        case deviceNotEligible
        /// Downloading, warming.
        case modelNotReady
        case other(String)
    }
}
