import Testing

@testable import DecisionModels

// A nested decision, written by hand. As in `TicketTriage`, `_severity` stands
// where the macro writes `$severity`.
struct BugReport: Decision {
    var _severity: Severity.Projection
    var severity: Severity { Severity.read(_severity) }

    var _reproducible: Bool.Projection
    var reproducible: Bool { Bool.read(_reproducible) }

    static let questions = Questionnaire(
        Severity.questions(id: "severity", Inquiry("How severe is the issue?"))
            + Bool.questions(
                id: "reproducible",
                Inquiry("Can the issue be reproduced from the description?")
            )
    )

    init(answers: Answers) throws {
        _severity = try Severity.projection(in: answers, id: "severity")
        _reproducible = try Bool.projection(in: answers, id: "reproducible")
    }

    var answers: Answers {
        Answers(merging: [
            Severity.answers(from: _severity, id: "severity"),
            Bool.answers(from: _reproducible, id: "reproducible"),
        ])
    }

    init(severity: Severity, reproducible: Bool) {
        _severity = Severity.certain(severity)
        _reproducible = Bool.certain(reproducible)
    }
}

// One decision holding an optional and another decision. The optional keeps the
// same projection as its wrapped type and reads through the threshold.
struct Intake: Decision {
    var _team: Team.Projection
    var team: Team? { Team?.read(_team, minimumConfidence: 0.7) }

    var _bug: BugReport.Projection
    var bug: BugReport { BugReport.read(_bug) }

    static let questions = Questionnaire(
        Team?.questions(id: "team", Inquiry("Which team handles this ticket?"))
            + BugReport.questions(id: "bug", Inquiry())
    )

    init(answers: Answers) throws {
        _team = try Team?.projection(in: answers, id: "team")
        _bug = try BugReport.projection(in: answers, id: "bug")
    }

    var answers: Answers {
        Answers(merging: [
            Team?.answers(from: _team, id: "team"),
            BugReport.answers(from: _bug, id: "bug"),
        ])
    }

    init(team: Team?, bug: BugReport) {
        _team = Team?.certain(team)
        _bug = BugReport.certain(bug)
    }
}

@Suite("Askable")
struct AskableTests {
    private func choice(of team: Team, confidence: Double) -> Choice<Team> {
        Choice(
            distribution: Distribution(
                probabilities: [.returns: 0.6, .shipping: 0.3, .billing: 0.1],
                quality: .calibrated
            ),
            reported: team,
            reportedConfidence: confidence
        )
    }

    @Test("The declared type picks the question kind")
    func typePicksTheKind() {
        guard case .choice(let options) = Team.questions(id: "team", Inquiry("Which team?"))[0].kind
        else {
            Issue.record("An options enum must ask a choice.")
            return
        }
        #expect(options.map(\.id) == ["returns", "shipping", "billing"])

        guard
            case .rating(let levels) = Severity.questions(id: "severity", Inquiry("How bad?"))[0]
                .kind
        else {
            Issue.record("A levels enum must ask a rating.")
            return
        }
        #expect(levels.count == 3)

        let verdict = Bool.questions(
            id: "refund",
            Inquiry("Does the customer ask for a refund?", ifTrue: "wants money back")
        )[0]
        guard case .verdict(let ifTrue, let ifFalse) = verdict.kind else {
            Issue.record("Bool must ask a verdict.")
            return
        }
        #expect(ifTrue?.summary == "wants money back")
        #expect(ifFalse == nil)
    }

    @Test("An optional asks the same question as its wrapped type")
    func optionalAsksTheSameQuestion() {
        let plain = Team.questions(id: "team", Inquiry("Which team?"))
        let optional = Team?.questions(id: "team", Inquiry("Which team?"))
        #expect(plain == optional)
    }

    @Test("An optional gates on the threshold")
    func optionalGating() {
        let atBar = Team?.read(choice(of: .returns, confidence: 0.7), minimumConfidence: 0.7)
        let above = Team?.read(choice(of: .returns, confidence: 0.9), minimumConfidence: 0.7)
        #expect(atBar == .returns)
        #expect(above == .returns)
        #expect(Team?.read(choice(of: .returns, confidence: 0.69), minimumConfidence: 0.7) == nil)
        #expect(Bool?.read(Verdict(probability: 0.87), minimumConfidence: 0.7) == true)
        #expect(Bool?.read(Verdict(probability: 0.6), minimumConfidence: 0.7) == nil)
    }

    @Test("The one-argument read always gives a value")
    func optionalReadWrapsSome() {
        #expect(Team?.read(choice(of: .billing, confidence: 0.1)) == .billing)
    }

    @Test("A nested decision takes a dotted prefix")
    func nestedQuestionsArePrefixed() {
        #expect(Intake.questions.specs.map(\.id) == ["team", "bug.severity", "bug.reproducible"])
    }

    @Test("A nested decision reads from scoped answers")
    func nestedDecisionReadsScopedAnswers() throws {
        let answers = Answers(
            records: [
                "team": .choice(
                    reported: "returns",
                    probabilities: ["returns": 0.95, "shipping": 0.03, "billing": 0.02],
                    confidence: 0.95
                ),
                "bug.severity": .rating(
                    score: 2, probabilities: [0: 0, 1: 0, 2: 1], confidence: nil
                ),
                "bug.reproducible": .verdict(probability: 0.2),
            ],
            quality: .calibrated
        )

        let intake = try Intake(answers: answers)

        #expect(intake.team == .returns)
        #expect(intake.bug.severity == .blocking)
        #expect(intake.bug.reproducible == false)
        #expect(intake._bug._severity.quality == .calibrated)
    }

    @Test("A low-confidence nested answer gates to nil")
    func nestedOptionalGatesToNil() throws {
        let answers = Answers(
            records: [
                "team": .choice(
                    reported: "returns",
                    probabilities: ["returns": 0.4, "shipping": 0.35, "billing": 0.25],
                    confidence: 0.4
                ),
                "bug.severity": .rating(
                    score: 1, probabilities: [0: 0.1, 1: 0.8, 2: 0.1], confidence: nil
                ),
                "bug.reproducible": .verdict(probability: 0.9),
            ],
            quality: .calibrated
        )

        let intake = try Intake(answers: answers)

        #expect(intake.team == nil)
        #expect(intake.bug.severity == .degraded)
    }

    @Test("answers round-trips through init(answers:)")
    func answersRoundTrip() throws {
        let triage = TicketTriage(team: .billing, severity: .blocking, requestsRefund: true)
        let again = try TicketTriage(answers: triage.answers)

        #expect(again.team == .billing)
        #expect(again.severity == .blocking)
        #expect(again.requestsRefund)
        // Reading fills in the options the model left out, so the records are
        // stable from the first pass on, not byte for byte with a certain answer.
        #expect(try TicketTriage(answers: again.answers).answers == again.answers)
    }

    @Test("A nested decision round-trips through its own answers")
    func nestedAnswersRoundTrip() throws {
        let intake = Intake(
            team: .shipping,
            bug: BugReport(severity: .degraded, reproducible: true)
        )
        let ids = intake.answers.records.keys.sorted()
        #expect(ids == ["bug.reproducible", "bug.severity", "team"])

        let again = try Intake(answers: intake.answers)
        #expect(again.team == .shipping)
        #expect(again.bug.severity == .degraded)
        #expect(again.bug.reproducible)
    }

    @Test("A missing optional stores an uncertain answer that gates to nil")
    func uncertainGatesToNil() throws {
        let intake = Intake(team: nil, bug: BugReport(severity: .cosmetic, reproducible: false))
        #expect(intake.team == nil)

        let again = try Intake(answers: intake.answers)
        #expect(again.team == nil)
    }

    @Test("A nested decision goes through the session in one request")
    func nestedDecisionThroughTheSession() async throws {
        let answers = Answers(
            records: [
                "team": .choice(
                    reported: "shipping",
                    probabilities: ["returns": 0.05, "shipping": 0.9, "billing": 0.05],
                    confidence: 0.9
                ),
                "bug.severity": .rating(
                    score: 0.2, probabilities: [0: 0.8, 1: 0.2, 2: 0], confidence: nil
                ),
                "bug.reproducible": .verdict(probability: 0.95),
            ],
            quality: .calibrated
        )
        let model = FakeModel(answers: answers)
        let session = DecisionSession(model: model)

        let intake = try await session.decide(Intake.self, about: "The parcel never arrived.")

        #expect(intake.team == .shipping)
        #expect(intake.bug.severity == .cosmetic)
        #expect(intake.bug.reproducible)
        #expect(model.callCount == 1)
        #expect(
            model.requests.first?.questionnaire.specs.map(\.id)
                == ["team", "bug.severity", "bug.reproducible"]
        )
    }
}

extension AskableTests {
    @Test("A missing nested answer names the question as the response knows it")
    func missingNestedAnswerNamesTheDottedID() {
        let answers = Answers(
            records: [
                "team": .choice(reported: "returns", probabilities: ["returns": 1], confidence: 1),
                "bug.reproducible": .verdict(probability: 0.2),
            ],
            quality: .calibrated
        )

        let error = #expect(throws: DecisionError.self) {
            try Intake(answers: answers)
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "bug.severity")
    }
}

extension AskableTests {
    @Test("A leaf contributes one record under its id")
    func leafContributesOneRecord() {
        let answers = Bool.answers(from: Verdict(probability: 0.87), id: "requestsRefund")

        #expect(answers.records.keys.sorted() == ["requestsRefund"])
        #expect(answers.records["requestsRefund"] == .verdict(probability: 0.87))
        #expect(answers.quality == .pointEstimate)
    }

    @Test("An optional contributes what its wrapped type contributes")
    func optionalContributesTheWrappedRecord() {
        let projection = choice(of: .returns, confidence: 0.9)

        #expect(
            Team?.answers(from: projection, id: "team") == Team.answers(from: projection, id: "team")
        )
    }

    @Test("A nested decision contributes prefixed answers")
    func nestedDecisionContributesPrefixedAnswers() {
        let bug = BugReport(severity: .degraded, reproducible: true)

        let answers = BugReport.answers(from: bug, id: "bug")

        #expect(answers.records.keys.sorted() == ["bug.reproducible", "bug.severity"])
        #expect(answers.quality == bug.answers.quality)
    }

    @Test("certain builds a sure answer of every kind")
    func certainBuildsSureAnswers() {
        #expect(Team.certain(.billing).value == .billing)
        #expect(isClose(Team.certain(.billing)[.billing], 1))
        #expect(Severity.certain(.blocking).value == .blocking)
        #expect(isClose(Severity.certain(.blocking).score, 2))
        #expect(Bool.certain(true).value)
        let bug = BugReport(severity: .cosmetic, reproducible: false)
        #expect(BugReport.certain(bug).severity == .cosmetic)
    }

    @Test("certain on nil says nothing")
    func certainOnNilIsUncertain() {
        #expect(isClose(Team?.certain(nil).confidence, 0))
        #expect(isClose(Severity?.certain(nil).confidence, 0))
        #expect(isClose(Bool?.certain(nil).probability, 0.5))
        #expect(Team?.certain(.shipping).value == .shipping)
    }
}
