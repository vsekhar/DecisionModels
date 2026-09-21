/// Asks a cheap model first and a stronger model only about the weak answers.
///
/// Every answer the first model gives below the bar goes to the second model in
/// one follow-up request that carries the same state, samples, timeout, and
/// metadata. The second model's records win. DESIGN.md section 10.2.
public struct CascadeModel: DecisionModel {
    /// The model that answers first.
    public let first: any DecisionModel
    /// The model that answers the weak questions again.
    public let second: any DecisionModel
    /// The confidence a first answer must reach to stand.
    public let threshold: Double

    public init(
        first: some DecisionModel,
        then second: some DecisionModel,
        escalateBelow threshold: Double
    ) {
        self.first = first
        self.second = second
        self.threshold = threshold
    }

    /// Names both models and the bar between them.
    ///
    /// A cache keys on the identity, so two cascades that differ only in the
    /// threshold must not look alike.
    public var identity: DecisionModelIdentity {
        DecisionModelIdentity(
            provider: "cascade",
            name: """
                \(first.identity.provider)/\(first.identity.name)\
                →\(second.identity.provider)/\(second.identity.name)@\(threshold)
                """
        )
    }

    /// What both models can do: the intersection of the two.
    public var capabilities: DecisionModelCapabilities {
        let near = first.capabilities
        let far = second.capabilities
        return DecisionModelCapabilities(
            probabilityQuality: min(near.probabilityQuality, far.probabilityQuality),
            structuredCriteria: near.structuredCriteria && far.structuredCriteria,
            structuredInstructions: near.structuredInstructions && far.structuredInstructions,
            maximumOptionsPerChoice: min(
                near.maximumOptionsPerChoice,
                far.maximumOptionsPerChoice
            ),
            maximumLevelsPerRating: min(
                near.maximumLevelsPerRating,
                far.maximumLevelsPerRating
            ),
            maximumQuestionsPerRequest: Self.tighter(
                near.maximumQuestionsPerRequest,
                far.maximumQuestionsPerRequest
            ),
            contextTokens: Self.tighter(near.contextTokens, far.contextTokens),
            supportsRepeatedSamples: near.supportsRepeatedSamples && far.supportsRepeatedSamples
        )
    }

    /// Available only when both models are. The first reason wins.
    public var availability: DecisionModelAvailability {
        get async {
            if case .unavailable(let reason) = await first.availability {
                return .unavailable(reason)
            }
            if case .unavailable(let reason) = await second.availability {
                return .unavailable(reason)
            }
            return .available
        }
    }

    public func prewarm() async {
        await first.prewarm()
        await second.prewarm()
    }

    public func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        try await decideWithReport(request).response
    }

    /// Answers the request and names the questions the second model answered again.
    ///
    /// The cascade resolves each first answer against its question (DESIGN.md
    /// section 8) before it compares it with the bar. So the bar sees an exact
    /// confidence, not one guessed from a record that lists only part of the
    /// scale. A malformed first answer throws before the cascade asks the
    /// second model. A question the first model left out also escalates, so a
    /// gap gets a second chance instead of reaching the caller. The second
    /// model's answers to the escalated questions are resolved the same way on
    /// merge, so the merged response is complete. Only the escalated answers
    /// change: a second model that answers more than it was asked cannot
    /// overwrite a confident first answer.
    public func decideWithReport(_ request: DecisionRequest) async throws -> CascadeReport {
        let near = try await first.decide(request)
        var records = near.answers.records
        var escalated: [String] = []
        for spec in request.questionnaire.specs {
            guard let record = near.answers.records[spec.id] else {
                escalated.append(spec.id)
                continue
            }
            let resolved = try AnswerReader.resolved(record, against: spec)
            records[spec.id] = resolved
            if resolved.confidence < threshold { escalated.append(spec.id) }
        }
        guard !escalated.isEmpty else {
            return CascadeReport(
                response: ModelResponse(
                    answers: Answers(records: records, quality: near.answers.quality),
                    usage: near.usage,
                    requestID: near.requestID
                ),
                escalated: []
            )
        }

        let weak = Set(escalated)
        let followUp = DecisionRequest(
            state: request.state,
            questionnaire: Questionnaire(
                request.questionnaire.specs.filter { weak.contains($0.id) }
            ),
            samples: request.samples,
            timeout: request.timeout,
            metadata: request.metadata
        )
        let far = try await second.decide(followUp)

        for spec in followUp.questionnaire.specs {
            guard let record = far.answers.records[spec.id] else { continue }
            records[spec.id] = try AnswerReader.resolved(record, against: spec)
        }
        return CascadeReport(
            response: ModelResponse(
                answers: Answers(
                    records: records,
                    quality: min(near.answers.quality, far.answers.quality)
                ),
                usage: near.usage + far.usage,
                requestID: far.requestID ?? near.requestID
            ),
            escalated: escalated
        )
    }

    /// The lower of two limits. A model that states no limit raises none.
    private static func tighter(_ near: Int?, _ far: Int?) -> Int? {
        guard let near else { return far }
        guard let far else { return near }
        return min(near, far)
    }
}

/// What a cascade answered, and which questions the second model took.
public struct CascadeReport: Sendable {
    /// The merged answers.
    public let response: ModelResponse
    /// The questions the second model answered again, in the order asked.
    public let escalated: [String]

    public init(response: ModelResponse, escalated: [String]) {
        self.response = response
        self.escalated = escalated
    }
}
