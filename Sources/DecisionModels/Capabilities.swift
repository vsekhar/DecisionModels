/// What a model can do.
///
/// The session checks a request against these limits and throws before it
/// sends, so a model never fails late on something the caller could see early.
public struct DecisionModelCapabilities: Sendable {
    /// The best probabilities the model can deliver.
    public var probabilityQuality: ProbabilityQuality
    /// Whether the model reads criteria as JSON. A model that does not gets a
    /// rendered string, so structured fields must not reach it.
    public var structuredCriteria: Bool
    /// Whether the model reads instructions as JSON.
    public var structuredInstructions: Bool
    /// How many options one choice can hold.
    public var maximumOptionsPerChoice: Int
    /// How many levels one rating can hold.
    public var maximumLevelsPerRating: Int
    /// How many questions one request can hold. `nil` means no limit.
    public var maximumQuestionsPerRequest: Int?
    /// How much state fits in the context. `nil` means the model does not say.
    public var contextTokens: Int?
    /// Whether the model can draw the same question more than once.
    public var supportsRepeatedSamples: Bool

    public init(
        probabilityQuality: ProbabilityQuality = .pointEstimate,
        structuredCriteria: Bool = false,
        structuredInstructions: Bool = false,
        maximumOptionsPerChoice: Int = 255,
        maximumLevelsPerRating: Int = 10,
        maximumQuestionsPerRequest: Int? = nil,
        contextTokens: Int? = nil,
        supportsRepeatedSamples: Bool = false
    ) {
        self.probabilityQuality = probabilityQuality
        self.structuredCriteria = structuredCriteria
        self.structuredInstructions = structuredInstructions
        self.maximumOptionsPerChoice = maximumOptionsPerChoice
        self.maximumLevelsPerRating = maximumLevelsPerRating
        self.maximumQuestionsPerRequest = maximumQuestionsPerRequest
        self.contextTokens = contextTokens
        self.supportsRepeatedSamples = supportsRepeatedSamples
    }
}
