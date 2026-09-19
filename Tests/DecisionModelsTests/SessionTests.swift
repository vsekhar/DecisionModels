import Synchronization
import Testing

@testable import DecisionModels

// The section 12 expansion, written by hand. Hand-written code cannot declare
// `$`-prefixed names, so the projection peers here are `_team` and so on; the
// `$` form is for macro expansion only. Everything else matches what the macro
// will emit, call for call.
struct TicketTriage: Decision {
    var _team: Team.Projection
    var team: Team { Team.read(_team) }

    var _severity: Severity.Projection
    var severity: Severity { Severity.read(_severity) }

    var _requestsRefund: Bool.Projection
    var requestsRefund: Bool { Bool.read(_requestsRefund) }

    /// Plain Swift, next to the questions.
    var needsHuman: Bool {
        _team.confidence < 0.5 || (severity == .blocking && _severity.confidence < 0.8)
    }

    static let questions = Questionnaire(
        Team.questions(id: "team", Inquiry("Which team handles this ticket?"))
            + Severity.questions(id: "severity", Inquiry("How severe is the reported issue?"))
            + Bool.questions(id: "requestsRefund", Inquiry("Does the customer ask for a refund?"))
    )

    init(answers: Answers) throws {
        _team = try Team.projection(in: answers, id: "team")
        _severity = try Severity.projection(in: answers, id: "severity")
        _requestsRefund = try Bool.projection(in: answers, id: "requestsRefund")
    }

    var answers: Answers {
        Answers(
            records: [
                "team": _team.record,
                "severity": _severity.record,
                "requestsRefund": _requestsRefund.record,
            ],
            quality: min(_team.quality, _severity.quality, _requestsRefund.quality)
        )
    }

    init(team: Team, severity: Severity, requestsRefund: Bool) {
        _team = Choice(certain: team)
        _severity = Rating(certain: severity)
        _requestsRefund = Verdict(certain: requestsRefund)
    }
}

/// A model that keeps every request it got and answers from a closure.
final class FakeModel: DecisionModel {
    let identity: DecisionModelIdentity
    let capabilities: DecisionModelCapabilities
    private let reported: DecisionModelAvailability
    private let script: @Sendable (DecisionRequest) throws -> ModelResponse
    private let received = Mutex<[DecisionRequest]>([])

    init(
        capabilities: DecisionModelCapabilities = .permissive,
        availability: DecisionModelAvailability = .available,
        identity: DecisionModelIdentity = DecisionModelIdentity(provider: "test", name: "fake"),
        script: @escaping @Sendable (DecisionRequest) throws -> ModelResponse
    ) {
        self.capabilities = capabilities
        self.reported = availability
        self.identity = identity
        self.script = script
    }

    convenience init(
        answers: Answers,
        usage: Usage = Usage(inputTokens: 3, outputTokens: 1, requests: 1),
        requestID: String? = "fake-1",
        capabilities: DecisionModelCapabilities = .permissive,
        availability: DecisionModelAvailability = .available
    ) {
        self.init(capabilities: capabilities, availability: availability) { _ in
            ModelResponse(answers: answers, usage: usage, requestID: requestID)
        }
    }

    var availability: DecisionModelAvailability {
        get async { reported }
    }

    func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        received.withLock { $0.append(request) }
        return try script(request)
    }

    /// Every request the session sent.
    var requests: [DecisionRequest] { received.withLock { $0 } }
    var callCount: Int { received.withLock { $0.count } }
}

extension DecisionModelCapabilities {
    /// Everything allowed, so a test only states the limit it is about.
    static let permissive = DecisionModelCapabilities(
        probabilityQuality: .calibrated,
        structuredCriteria: true,
        structuredInstructions: true,
        maximumOptionsPerChoice: 255,
        maximumLevelsPerRating: 10,
        supportsRepeatedSamples: true
    )
}

/// What a model answers for the triage example.
let triageAnswers = Answers(
    records: [
        "team": .choice(
            reported: "returns",
            probabilities: ["returns": 0.91, "shipping": 0.06, "billing": 0.03],
            confidence: 0.9
        ),
        "severity": .rating(score: 1.3, probabilities: [0: 0, 1: 0.7, 2: 0.3], confidence: nil),
        "requestsRefund": .verdict(probability: 0.87),
    ],
    quality: .calibrated
)

@Suite("Session")
struct SessionTests {
    @Test("A hand-written decision round-trips through the session")
    func roundTrip() async throws {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(model: model)

        let triage: TicketTriage = try await session.decide(about: "The blender arrived broken.")

        #expect(triage.team == .returns)
        #expect(triage.severity == .degraded)
        #expect(triage.requestsRefund)
        #expect(isClose(triage._team.confidence, 0.9))
        #expect(isClose(triage._severity.score, 1.3))
        #expect(isClose(triage._requestsRefund.probability, 0.87))
        #expect(!triage.needsHuman)
    }

    @Test("The model receives the questions and the state")
    func requestCarriesQuestionsAndState() async throws {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(model: model)

        _ = try await session.decide(TicketTriage.self, about: "The blender arrived broken.")

        let request = try #require(model.requests.first)
        #expect(request.state == .text("The blender arrived broken."))
        #expect(request.samples == 1)
        #expect(request.questionnaire.specs.map(\.id) == ["team", "severity", "requestsRefund"])
        guard case .choice(let options) = request.questionnaire.specs[0].kind else {
            Issue.record("The first question is not a choice.")
            return
        }
        #expect(options.map(\.id) == ["returns", "shipping", "billing"])
        guard case .rating(let levels) = request.questionnaire.specs[1].kind else {
            Issue.record("The second question is not a rating.")
            return
        }
        #expect(levels.count == 3)
        guard case .verdict = request.questionnaire.specs[2].kind else {
            Issue.record("The third question is not a verdict.")
            return
        }
    }

    @Test("The state builder assembles the state")
    func stateBuilder() async throws {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(model: model)
        let order: Int? = 12

        let triage = try await session.decide(TicketTriage.self) {
            Field("message", "The blender arrived broken.")
            if let order { Field("order", order) }
        }

        #expect(triage.team == .returns)
        #expect(
            model.requests.first?.state
                == .object([
                    "message": .text("The blender arrived broken."),
                    "order": .number(12),
                ])
        )
    }

    @Test("respond carries the model, the request id, and the duration")
    func respondCarriesMetadata() async throws {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(model: model)

        let response: DecisionResponse<TicketTriage> = try await session.respond(about: "broken")

        #expect(response.model == DecisionModelIdentity(provider: "test", name: "fake"))
        #expect(response.requestID == "fake-1")
        #expect(response.duration > .zero)
        #expect(response.usage == Usage(inputTokens: 3, outputTokens: 1, requests: 1))
        #expect(response.answers.records.keys.sorted() == ["requestsRefund", "severity", "team"])
        #expect(response.decision.team == .returns)
    }

    @Test("Run-time questions go through the same pipeline")
    func runTimeQuestions() async throws {
        let skill = Choose("skill", "Which skill fits the request?", among: catalog)
        let answers = Answers(
            records: [
                "skill": .choice(
                    reported: "refund",
                    probabilities: ["search": 0.1, "refund": 0.8, "escalate": 0.1],
                    confidence: nil
                )
            ],
            quality: .calibrated
        )
        let model = FakeModel(answers: answers)
        let session = DecisionSession(model: model)

        let got = try await session.decide(Questionnaire { skill }, about: "Give me my money back")

        #expect(try got[skill].value == catalog[1])
        #expect(model.requests.first?.questionnaire.specs.map(\.id) == ["skill"])
    }

    @Test("Per-call options override the session's")
    func perCallOptionsWin() async throws {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(
            model: model,
            options: DecisionOptions(timeout: .seconds(1), samples: 1)
        )

        _ = try await session.decide(
            TicketTriage.self,
            about: "broken",
            options: DecisionOptions(timeout: .seconds(30), samples: 3)
        )

        #expect(model.requests.first?.samples == 3)
        #expect(model.requests.first?.timeout == .seconds(30))
    }

    @Test("prewarm forwards to the model")
    func prewarmForwards() async {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(model: model)
        await session.prewarm()
        #expect(session.model.identity == model.identity)
    }
}

extension SessionTests {
    @Test("Per-call options replace the session's entirely")
    func perCallOptionsReplace() async throws {
        let model = FakeModel(
            answers: Answers(records: triageAnswers.records, quality: .pointEstimate)
        )
        let session = DecisionSession(
            model: model,
            options: DecisionOptions(minimumProbabilityQuality: .calibrated)
        )

        // The session's floor rejects a point estimate.
        await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }

        // A fresh per-call value carries no floor, so the call passes.
        _ = try await session.decide(
            TicketTriage.self, about: "broken", options: DecisionOptions(timeout: .seconds(5))
        )

        // Copying the session's options keeps the floor.
        var copied = session.options
        copied.timeout = .seconds(5)
        await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken", options: copied)
        }
    }

    @Test("Metadata travels with the request")
    func metadataReachesTheRequest() async throws {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(model: model)

        _ = try await session.decide(
            TicketTriage.self, about: "broken",
            options: DecisionOptions(metadata: ["trace": "t-1"])
        )

        #expect(model.requests.first?.metadata == ["trace": "t-1"])
    }
}
