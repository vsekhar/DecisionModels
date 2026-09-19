import Testing

@testable import DecisionModels

/// Everything the session refuses before it sends.
@Suite("Pre-flight")
struct PreflightTests {
    /// A model that fails the test if the session ever calls it.
    private func unusedModel(
        capabilities: DecisionModelCapabilities = .permissive,
        availability: DecisionModelAvailability = .available
    ) -> FakeModel {
        FakeModel(capabilities: capabilities, availability: availability) { _ in
            Issue.record("The session sent a request it should have refused.")
            return ModelResponse(answers: Answers(quality: .pointEstimate))
        }
    }

    private func questionnaire(_ kind: QuestionSpec.Kind, id: String = "q") -> Questionnaire {
        Questionnaire([QuestionSpec(id: id, instructions: "Judge it.", kind: kind)])
    }

    private func options(_ count: Int) -> [QuestionSpec.OptionSpec] {
        (0..<count).map {
            QuestionSpec.OptionSpec(id: "o\($0)", criterion: Criterion("Option \($0)"))
        }
    }

    @Test("A question with no instructions is invalid, not a capability gap")
    func nullInstructions() async {
        let session = DecisionSession(model: unusedModel())
        let questionnaire = Questionnaire([
            QuestionSpec(id: "q", instructions: .null, kind: .verdict(ifTrue: nil, ifFalse: nil))
        ])

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(questionnaire, about: "broken")
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "q")
    }

    @Test("An unavailable model throws before the call")
    func unavailable() async {
        let model = unusedModel(availability: .unavailable(.notConfigured("no API key")))
        let session = DecisionSession(model: model)

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }
        guard case .unavailable(.notConfigured(let detail)) = error else {
            Issue.record("Expected unavailable, got \(String(describing: error))")
            return
        }
        #expect(detail == "no API key")
        #expect(model.callCount == 0)
    }

    @Test("Too many options throws before the model is called")
    func tooManyOptions() async {
        let model = unusedModel(
            capabilities: DecisionModelCapabilities(
                structuredCriteria: true,
                structuredInstructions: true,
                maximumOptionsPerChoice: 255
            )
        )
        let session = DecisionSession(model: model)

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(
                questionnaire(.choice(options: options(300))),
                about: "a request"
            )
        }
        guard case .unsupported(.tooManyOptions(let id, let count, let limit)) = error else {
            Issue.record("Expected tooManyOptions, got \(String(describing: error))")
            return
        }
        #expect(id == "q")
        #expect(count == 300)
        #expect(limit == 255)
        #expect(model.callCount == 0)
    }

    @Test("Too many levels throws")
    func tooManyLevels() async {
        let model = unusedModel(
            capabilities: DecisionModelCapabilities(
                structuredCriteria: true,
                structuredInstructions: true,
                maximumLevelsPerRating: 10
            )
        )
        let session = DecisionSession(model: model)

        let levels = (0..<12).map { Criterion("Level \($0)") }
        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(questionnaire(.rating(levels: levels)), about: "a request")
        }
        guard case .unsupported(.tooManyLevels(_, let count, let limit)) = error else {
            Issue.record("Expected tooManyLevels, got \(String(describing: error))")
            return
        }
        #expect(count == 12)
        #expect(limit == 10)
    }

    @Test("Too many questions throws")
    func tooManyQuestions() async {
        let model = unusedModel(
            capabilities: DecisionModelCapabilities(
                structuredCriteria: true,
                structuredInstructions: true,
                maximumQuestionsPerRequest: 2
            )
        )
        let session = DecisionSession(model: model)

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }
        guard case .unsupported(.tooManyQuestions(let count, let limit)) = error else {
            Issue.record("Expected tooManyQuestions, got \(String(describing: error))")
            return
        }
        #expect(count == 3)
        #expect(limit == 2)
    }

    @Test("Structured criteria throw against a model that reads only text")
    func structuredCriteria() async {
        let model = unusedModel(
            capabilities: DecisionModelCapabilities(
                structuredCriteria: false,
                structuredInstructions: true
            )
        )
        let session = DecisionSession(model: model)

        // Team.returns carries notFor and examples.
        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }
        guard case .unsupported(.structuredCriteria) = error else {
            Issue.record("Expected structuredCriteria, got \(String(describing: error))")
            return
        }
        #expect(model.callCount == 0)
    }

    @Test("Structured instructions throw against a model that reads only text")
    func structuredInstructions() async {
        let model = unusedModel(
            capabilities: DecisionModelCapabilities(
                structuredCriteria: true,
                structuredInstructions: false
            )
        )
        let session = DecisionSession(model: model)

        let spec = QuestionSpec(
            id: "totalsMatch",
            instructions: ["question": "Do the totals match?", "focus": "arithmetic only"],
            kind: .verdict(ifTrue: nil, ifFalse: nil)
        )
        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(Questionnaire([spec]), about: "an invoice")
        }
        guard case .unsupported(.structuredInstructions) = error else {
            Issue.record("Expected structuredInstructions, got \(String(describing: error))")
            return
        }
    }

    @Test("Repeated samples throw where the model draws once")
    func repeatedSamples() async {
        let model = unusedModel(
            capabilities: DecisionModelCapabilities(
                structuredCriteria: true,
                structuredInstructions: true,
                supportsRepeatedSamples: false
            )
        )
        let session = DecisionSession(model: model, options: DecisionOptions(samples: 5))

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }
        guard case .unsupported(.repeatedSamples) = error else {
            Issue.record("Expected repeatedSamples, got \(String(describing: error))")
            return
        }
    }

    @Test("A choice with no options is an invalid question")
    func zeroOptions() async {
        let session = DecisionSession(model: unusedModel())

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(questionnaire(.choice(options: [])), about: "a request")
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "q")
    }

    @Test("A scale with one level is an invalid question")
    func oneLevel() async {
        let session = DecisionSession(model: unusedModel())

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(
                questionnaire(.rating(levels: ["The only level"])),
                about: "a request"
            )
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "q")
    }

    @Test("Two options with one id are an invalid question")
    func duplicateOptionIDs() async {
        let session = DecisionSession(model: unusedModel())
        let twice = [
            QuestionSpec.OptionSpec(id: "refund", criterion: "Give money back"),
            QuestionSpec.OptionSpec(id: "refund", criterion: "Refund, version two"),
        ]

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(questionnaire(.choice(options: twice)), about: "a request")
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "q")
    }

    @Test("Two questions with one id are an invalid question")
    func duplicateQuestionIDs() async {
        let session = DecisionSession(model: unusedModel())
        let spec = QuestionSpec(
            id: "unsafe",
            instructions: "Does the request break the policy?",
            kind: .verdict(ifTrue: nil, ifFalse: nil)
        )

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(Questionnaire([spec, spec]), about: "a request")
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "unsafe")
    }

    @Test("A response below the quality floor throws")
    func insufficientQuality() async {
        let model = FakeModel(
            answers: Answers(records: triageAnswers.records, quality: .pointEstimate)
        )
        let session = DecisionSession(
            model: model,
            options: DecisionOptions(minimumProbabilityQuality: .calibrated)
        )

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }
        guard case .insufficientProbabilityQuality(let got, let required) = error else {
            Issue.record("Expected a quality floor error, got \(String(describing: error))")
            return
        }
        #expect(got == .pointEstimate)
        #expect(required == .calibrated)
        #expect(model.callCount == 1)
    }

    @Test("A response at the quality floor passes")
    func sufficientQuality() async throws {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(
            model: model,
            options: DecisionOptions(minimumProbabilityQuality: .calibrated)
        )

        let triage = try await session.decide(TicketTriage.self, about: "broken")
        #expect(triage.team == .returns)
    }
}

extension PreflightTests {
    private var textOnly: DecisionModelCapabilities {
        var capabilities = DecisionModelCapabilities.permissive
        capabilities.structuredCriteria = false
        return capabilities
    }

    @Test("Structured verdict criteria trip a text-only model")
    func structuredVerdictCriteria() async {
        let session = DecisionSession(model: unusedModel(capabilities: textOnly))
        let structured = Criterion("Wants money back", examples: ["refund me"])
        let questionnaire = self.questionnaire(.verdict(ifTrue: structured, ifFalse: nil))

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(questionnaire, about: "broken")
        }
        guard case .unsupported(.structuredCriteria) = error else {
            Issue.record("Expected structuredCriteria, got \(String(describing: error))")
            return
        }
    }

    @Test("Structured rating levels trip a text-only model")
    func structuredRatingLevels() async {
        let session = DecisionSession(model: unusedModel(capabilities: textOnly))
        let levels: [Criterion] = ["Low", Criterion("High", signals: ["shouting"])]

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(questionnaire(.rating(levels: levels)), about: "broken")
        }
        guard case .unsupported(.structuredCriteria) = error else {
            Issue.record("Expected structuredCriteria, got \(String(describing: error))")
            return
        }
    }

    @Test("An empty questionnaire is invalid")
    func emptyQuestionnaire() async {
        let session = DecisionSession(model: unusedModel())

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(Questionnaire(), about: "broken")
        }
        guard case .invalidQuestion = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
    }

    @Test("Sanity checks come before the model's limits")
    func sanityBeforeFit() async {
        var capabilities = DecisionModelCapabilities.permissive
        capabilities.maximumQuestionsPerRequest = 1
        let session = DecisionSession(model: unusedModel(capabilities: capabilities))
        // Two questions with one id: too many for the model, and a caller bug.
        let twice = Questionnaire(
            questionnaire(.verdict(ifTrue: nil, ifFalse: nil), id: "q").specs
                + questionnaire(.verdict(ifTrue: nil, ifFalse: nil), id: "q").specs
        )

        let error = await #expect(throws: DecisionError.self) {
            _ = try await session.decide(twice, about: "broken")
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion first, got \(String(describing: error))")
            return
        }
        #expect(id == "q")
    }

    @Test("Zero samples is a programmer error")
    func zeroSamplesTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = DecisionOptions(samples: 0)
        }
    }
}
