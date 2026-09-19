/// How much a distribution can be trusted.
///
/// The order runs `pointEstimate < sampled < calibrated`, and among sampled
/// values, by count. A session can demand a floor.
public enum ProbabilityQuality: Sendable, Codable, Hashable, Comparable {
    /// One-hot, from a model that returns only an argmax.
    case pointEstimate
    /// Empirical, from repeated draws.
    case sampled(count: Int)
    /// Trained and reported by the provider.
    case calibrated
}
