import Testing

@testable import DecisionModels

// The command shape of DESIGN.md section 16, written by hand. Hand-written
// code cannot declare `$`-prefixed names, so the projection peers here are
// `_kind` and so on; the `$` form is for macro expansion only. Everything else
// matches what the macro emits, call for call.
//
// The suite exists for one question: a session that takes both a `Decision`
// and an `Askable` whose projection is a decision must still resolve every
// call. So it repeats the section 8 calls with a decision beside a command.

/// A decision, in the shape of the one in `SessionTests`.
struct DeskTriage: Decision {
    var _team: Team.Projection
    var team: Team { Team.read(_team) }

    var _severity: Severity.Projection
    var severity: Severity { Severity.read(_severity) }

    var _requestsRefund: Bool.Projection
    var requestsRefund: Bool { Bool.read(_requestsRefund) }

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
        Answers(merging: [
            Team.answers(from: _team, id: "team"),
            Severity.answers(from: _severity, id: "severity"),
            Bool.answers(from: _requestsRefund, id: "requestsRefund"),
        ])
    }

    init(team: Team, severity: Severity, requestsRefund: Bool) {
        _team = Team.certain(team)
        _severity = Severity.certain(severity)
        _requestsRefund = Bool.certain(requestsRefund)
    }
}

/// The arguments of one command case.
struct HandOffArguments: Decision {
    var _team: Team.Projection
    var team: Team { Team.read(_team) }

    static let questions = Questionnaire(
        Team.questions(id: "team", Inquiry("Which team takes it?"))
    )

    init(answers: Answers) throws {
        _team = try Team.projection(in: answers, id: "team")
    }

    var answers: Answers {
        Answers(merging: [Team.answers(from: _team, id: "team")])
    }

    init(team: Team) {
        _team = Team.certain(team)
    }
}

/// A command: one choice over the cases, and the arguments of each.
enum HandCommand: Sendable {
    case handOff(HandOffArguments)
    case close

    enum Kind: ChoiceOption, CaseIterable, Askable, Codable {
        case handOff, close

        typealias Projection = Choice<Kind>

        var optionID: String {
            switch self {
            case .handOff: "handOff"
            case .close: "close"
            }
        }

        var criterion: Criterion {
            switch self {
            case .handOff: "Give the ticket to a team"
            case .close: "Close the ticket"
            }
        }
    }

    struct Answered: Decision {
        var _kind: Choice<Kind>
        var kind: Kind { Kind.read(_kind) }
        let command: HandCommand

        static var questions: Questionnaire {
            Questionnaire(
                Kind.questions(id: "kind", Inquiry("What does the ticket need?"))
                    + HandOffArguments.questions(id: "handOff", Inquiry())
            )
        }

        init(answers: Answers) throws {
            _kind = try Kind.projection(in: answers, id: "kind")
            switch _kind.value {
            case .handOff:
                command = .handOff(try HandOffArguments.projection(in: answers, id: "handOff"))
            case .close:
                command = .close
            }
        }

        var answers: Answers {
            var parts = [Kind.answers(from: _kind, id: "kind")]
            switch command {
            case .handOff(let arguments):
                parts.append(HandOffArguments.answers(from: arguments, id: "handOff"))
            case .close:
                break
            }
            return Answers(merging: parts)
        }

        init(_ command: HandCommand) {
            self.command = command
            switch command {
            case .handOff: _kind = Kind.certain(.handOff)
            case .close: _kind = Kind.certain(.close)
            }
        }
    }
}

extension HandCommand: Askable {
    typealias Projection = Answered

    static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec] {
        Answered.questions(id: id, inquiry)
    }

    static func projection(in answers: Answers, id: String) throws -> Answered {
        try Answered.projection(in: answers, id: id)
    }

    static func read(_ projection: Answered) -> HandCommand {
        projection.command
    }

    static func answers(from projection: Answered, id: String) -> Answers {
        Answered.answers(from: projection, id: id)
    }

    static func certain(_ value: HandCommand) -> Answered {
        Answered(value)
    }
}

/// What a model answers for the command.
private let commandAnswers = Answers(
    records: [
        "kind": .choice(
            reported: "handOff",
            probabilities: ["handOff": 0.8, "close": 0.2],
            confidence: 0.75
        ),
        "handOff.team": .choice(
            reported: "billing",
            probabilities: ["returns": 0.1, "shipping": 0.1, "billing": 0.8],
            confidence: nil
        ),
    ],
    quality: .calibrated
)

@Suite("A session that takes decisions and commands")
struct CommandSessionTests {
    @Test("A named decision still resolves to the decision call")
    func decisionByName() async throws {
        let session = DecisionSession(model: FakeModel(answers: triageAnswers))

        let triage = try await session.decide(DeskTriage.self, about: "The blender is broken.")

        #expect(triage.team == .returns)
    }

    @Test("An inferred decision still resolves to the decision call")
    func decisionByInference() async throws {
        let session = DecisionSession(model: FakeModel(answers: triageAnswers))

        let triage: DeskTriage = try await session.decide(about: "The blender is broken.")
        let response: DecisionResponse<DeskTriage> = try await session.respond(about: "broken")
        let built = try await session.decide(DeskTriage.self) {
            Field("message", "The blender is broken.")
        }

        #expect(triage.severity == .degraded)
        #expect(response.decision.team == .returns)
        #expect(built.requestsRefund)
    }

    @Test("A named command resolves to the projection call")
    func commandByName() async throws {
        let model = FakeModel(answers: commandAnswers)
        let session = DecisionSession(model: model)

        let command = try await session.decide(HandCommand.self, about: "Who pays for this?")

        #expect(model.requests.first?.questionnaire.specs.map(\.id) == ["kind", "handOff.team"])
        guard case .handOff(let arguments) = command else {
            Issue.record("The command is not a hand-off.")
            return
        }
        #expect(arguments.team == .billing)
    }

    @Test("An inferred command resolves to the projection call")
    func commandByInference() async throws {
        let session = DecisionSession(model: FakeModel(answers: commandAnswers))

        let command: HandCommand = try await session.decide(about: "Who pays for this?")
        let built: HandCommand = try await session.decide {
            Field("message", "Who pays for this?")
        }

        #expect(isHandOff(command))
        #expect(isHandOff(built))
    }

    @Test("respond gives the command's projection and its confidence")
    func commandResponse() async throws {
        let session = DecisionSession(model: FakeModel(answers: commandAnswers))

        let response = try await session.respond(HandCommand.self, about: "Who pays for this?")

        #expect(isClose(response.decision._kind.confidence, 0.75))
        #expect(response.decision.kind == .handOff)
        #expect(response.usage == Usage(inputTokens: 3, outputTokens: 1, requests: 1))
        #expect(isHandOff(response.decision.command))
    }

    @Test("Every call form binds without ambiguity")
    func everyCallFormBinds() async throws {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(model: model)

        _ = try await session.decide(DeskTriage.self)
        let _: DeskTriage = try await session.decide()
        _ = try await session.respond(DeskTriage.self)
        _ = try await session.decide(DeskTriage.self) { Field("a", 1) }
        _ = try await session.decide(DeskTriage.self, about: "text")
        _ = try await session.decide(DeskTriage.questions)

        let commandModel = FakeModel(answers: commandAnswers)
        let commandSession = DecisionSession(model: commandModel)

        _ = try await commandSession.decide(HandCommand.self)
        _ = try await commandSession.respond(HandCommand.self)

        let states: [State?] = [
            nil, nil, nil, .object(["a": .number(1)]), .text("text"), nil,
        ]
        #expect(model.requests.map(\.state) == states)
        #expect(commandModel.requests.map(\.state) == [nil, nil])
    }

    private func isHandOff(_ command: HandCommand) -> Bool {
        if case .handOff = command { return true }
        return false
    }
}
