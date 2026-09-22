#if canImport(FoundationModels)
import DecisionModels
import FoundationModels

/// A decision model over Apple's on-device model.
///
/// One request becomes one `DynamicGenerationSchema` object with a property
/// per question, so a whole questionnaire comes back in one generation. The
/// state, the instructions, and the criteria go into the prompt as text.
///
/// With one sample the model runs greedy and the answers carry one-hot
/// probabilities. With `k` samples it runs `k` generations at temperature
/// one, each on its own session, and the answers carry the empirical share
/// of every option, marked `.sampled(count: k)`.
///
/// DESIGN.md 10.1 also promises an initializer over any Apple
/// `LanguageModel`. That protocol arrives with iOS 27 and macOS 27; the
/// Xcode 26.6 SDK has no part of it, so this type takes
/// `SystemLanguageModel` only.
@available(macOS 26, iOS 26, *)
public struct GuidedGenerationModel: DecisionModel {
    private let model: SystemLanguageModel
    private let extraInstructions: String?

    /// Wraps a system model.
    ///
    /// `instructions` are standing rules that follow the task in every
    /// session, such as the voice or the domain to judge by.
    public init(_ model: SystemLanguageModel, instructions: String? = nil) {
        self.model = model
        self.extraInstructions = instructions
    }

    public var identity: DecisionModelIdentity {
        DecisionModelIdentity(provider: "apple", name: "system-language-model")
    }

    public var capabilities: DecisionModelCapabilities {
        DecisionModelCapabilities(
            // Repeated draws are the best this model can do. Nothing here is
            // calibrated.
            probabilityQuality: .sampled(count: .max),
            // Structured criteria and instructions render into the prompt as
            // text, so the adapter takes them; the caller never has to know.
            structuredCriteria: true,
            structuredInstructions: true,
            maximumOptionsPerChoice: 64,
            maximumLevelsPerRating: 10,
            maximumQuestionsPerRequest: nil,
            contextTokens: contextTokens,
            supportsRepeatedSamples: true
        )
    }

    /// How many tokens the device holds.
    ///
    /// `contextSize` is back-deployed and answers 4096 before 26.4, so the
    /// fallback says the same thing the shim would.
    var contextTokens: Int {
        if #available(macOS 26.4, iOS 26.4, *) {
            return model.contextSize
        }
        return 4096
    }

    public var availability: DecisionModelAvailability {
        get async { Self.availability(of: model.availability) }
    }

    /// Maps what the system model reports.
    static func availability(
        of reported: SystemLanguageModel.Availability
    ) -> DecisionModelAvailability {
        switch reported {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.notConfigured("Apple Intelligence"))
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.other("The system model is unavailable: \(reason)."))
            }
        }
    }

    public func prewarm() async {
        LanguageModelSession(
            model: model,
            instructions: DecisionPromptBuilder.instructions(adding: extraInstructions)
        ).prewarm()
    }

    // MARK: Deciding

    public func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        // The caller's timeout bounds the whole call, not each draw, so the
        // deadline is fixed here and every step spends from the same budget.
        let clock = ContinuousClock()
        let deadline = request.timeout.map { clock.now + $0 }

        let built = try SchemaBuilder.build(request.questionnaire)
        let instructions = DecisionPromptBuilder.instructions(adding: extraInstructions)
        let prompt = DecisionPromptBuilder.prompt(
            state: request.state,
            questionnaire: request.questionnaire,
            fieldNames: built.fieldNames
        )
        let limit = contextTokens

        // The schema rides in the prompt, so its tokens are input tokens too.
        // Counting can fail, and a failure here is the caller's answer, not
        // something to swallow.
        let estimate: Int?
        do {
            let counter: DecisionPromptBuilder.TokenCounter?
            var schemaTokens = 0
            if #available(macOS 26.4, iOS 26.4, *) {
                let model = self.model
                counter = { text in try await model.tokenCount(for: text) }
                schemaTokens = try await model.tokenCount(for: built.schema)
            } else {
                counter = nil
            }
            estimate = try await DecisionPromptBuilder.estimate(
                instructions: instructions,
                prompt: prompt,
                schemaTokens: schemaTokens,
                questions: request.questionnaire.specs.count,
                limit: limit,
                counter: counter
            )
        } catch {
            throw ErrorMapping.decisionError(from: error, contextTokens: limit)
        }

        let samples = max(1, request.samples)
        let options = Self.generationOptions(samples: samples)
        var draws: [[String: QuestionOutcome]] = []
        draws.reserveCapacity(samples)
        // One session takes one request at a time, so the draws run one after
        // another. A fresh session per draw keeps the context the same for
        // each of them.
        for _ in 0..<samples {
            let content = try await generate(
                instructions: instructions,
                prompt: prompt,
                schema: built.schema,
                options: options,
                timeout: try Self.remaining(until: deadline, on: clock)
            )
            draws.append(
                try ResponseMapping.outcomes(
                    from: content,
                    questionnaire: request.questionnaire,
                    fieldNames: built.fieldNames
                )
            )
        }

        return ModelResponse(
            answers: try ResponseMapping.answers(
                from: draws,
                questionnaire: request.questionnaire
            ),
            usage: Usage(
                inputTokens: (estimate ?? 0) * samples,
                outputTokens: 0,
                requests: samples
            )
        )
    }

    /// Greedy for one draw, warm for more.
    ///
    /// `SamplingMode` carries no temperature of its own, so temperature sits
    /// beside it on the options.
    ///
    /// The draws take no seed. `random(top:seed:)` takes a `UInt64`, but the
    /// device rejects most of that range: on macOS 26.6 a seed of
    /// `UInt32.max`, `UInt32.max + 1`, or `Int64.max` fails the request with
    /// an empty `GenerationError`, while small seeds work. Left to itself the
    /// framework picks a seed per call, and the draws do come out different.
    static func generationOptions(samples: Int) -> GenerationOptions {
        guard samples > 1 else {
            return GenerationOptions(samplingMode: .greedy)
        }
        return GenerationOptions(samplingMode: .random(top: 50), temperature: 1.0)
    }

    /// What is left of the caller's deadline.
    ///
    /// Answers `nil` when the caller set no timeout, and throws when the
    /// budget is already gone, so a later draw never starts a call it cannot
    /// finish.
    static func remaining(
        until deadline: ContinuousClock.Instant?,
        on clock: ContinuousClock
    ) throws -> Duration? {
        guard let deadline else { return nil }
        let left = deadline - clock.now
        guard left > .zero else { throw DecisionError.timeout }
        return left
    }

    /// Runs one generation, within what is left of the caller's deadline.
    private func generate(
        instructions: String,
        prompt: String,
        schema: GenerationSchema,
        options: GenerationOptions,
        timeout: Duration?
    ) async throws -> GeneratedContent {
        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            guard let timeout else {
                return try await session.respond(
                    to: prompt, schema: schema, options: options
                ).content
            }
            return try await withThrowingTaskGroup(of: GeneratedContent.self) { group in
                group.addTask {
                    try await session.respond(
                        to: prompt, schema: schema, options: options
                    ).content
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw DecisionError.timeout
                }
                guard let first = try await group.next() else { throw DecisionError.timeout }
                group.cancelAll()
                return first
            }
        } catch {
            throw ErrorMapping.decisionError(from: error, contextTokens: contextTokens)
        }
    }
}
#endif
