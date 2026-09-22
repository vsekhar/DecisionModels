#if canImport(FoundationModels)
import DecisionModels
import FoundationModels
import Testing

@testable import DecisionModelsApple

/// Live calls to the on-device model.
///
/// These tests **fail** when the system model is not available. A skip would
/// hide the one thing the suite is here to prove. One session takes one
/// request at a time, so the suite runs serially.
@Suite("GuidedGenerationModel live", .serialized)
struct GuidedGenerationLiveTests {
    /// Records a failure and answers false when the model cannot run.
    @available(macOS 26, iOS 26, *)
    private func modelIsReady(
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> Bool {
        let availability = SystemLanguageModel.default.availability
        if case .available = availability { return true }
        Issue.record(
            """
            The system language model is not available (\(availability)). \
            These tests need a Mac with Apple Intelligence turned on and the \
            model downloaded.
            """,
            sourceLocation: sourceLocation
        )
        return false
    }

    @Test("One sample answers the questionnaire with one-hot probabilities")
    func oneSample() async throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        guard modelIsReady() else { return }
        let session = DecisionSession(model: GuidedGenerationModel(.default))

        let answers = try await session.decide(
            supportQuestionnaire,
            about: "Wrong size shoes arrived, I want my money back"
        )

        #expect(answers.quality == .pointEstimate)

        guard case .choice(let team, let teams, _)? = answers.records["team"] else {
            Issue.record("The team answer is not a choice: \(String(describing: answers.records["team"])).")
            return
        }
        #expect(team == "returns")
        #expect(teams.count == 3)
        #expect(isClose(teams[team] ?? 0, 1))
        #expect(isClose(teams.values.reduce(0, +), 1))
        for (id, probability) in teams where id != team {
            #expect(probability == 0)
        }

        guard case .rating(let score, let levels, _)? = answers.records["severity"] else {
            Issue.record("The severity answer is not a rating.")
            return
        }
        #expect(levels.count == 3)
        #expect((0...2).contains(score))
        #expect(isClose(levels.values.reduce(0, +), 1))
        #expect(levels.values.allSatisfy { $0 == 0 || $0 == 1 })

        guard case .verdict(let refund)? = answers.records["refund"] else {
            Issue.record("The refund answer is not a verdict.")
            return
        }
        #expect(refund == 1)

        #expect(session.usage.inputTokens > 0)
        #expect(session.usage.requests == 1)

        print("LIVE one sample: team=\(team) severity=\(score) refund=\(refund) "
            + "usage=\(session.usage)")
    }

    /// The control is unrelated on purpose: asked two capitals questions in
    /// one request, this model answers both false.
    @Test("The model answers questions that carry their own facts")
    func noState() async throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        guard modelIsReady() else { return }
        let session = DecisionSession(model: GuidedGenerationModel(.default))

        let questionnaire = Questionnaire {
            Verify("capital", "Is Paris the capital of France?")
            Verify("control", "Is the Moon made of cheese?")
        }

        let answers = try await session.decide(questionnaire)

        guard case .verdict(let capital)? = answers.records["capital"],
              case .verdict(let control)? = answers.records["control"]
        else {
            Issue.record("The answers are not verdicts.")
            return
        }
        // One sample is one-hot: the model either says it or it does not.
        #expect(capital == 1)
        #expect(control == 0)

        print("LIVE no state: capital=\(capital) control=\(control)")

        guard #available(macOS 26.4, iOS 26.4, *) else { return }
        // The same three texts the adapter sends with no state, counted here
        // on their own. They pin the stateless instructions to the wire.
        let model = SystemLanguageModel.default
        let built = try SchemaBuilder.build(questionnaire)
        let instructions = DecisionPromptBuilder.instructions(hasState: false)
        let prompt = DecisionPromptBuilder.prompt(
            state: nil,
            questionnaire: questionnaire,
            fieldNames: built.fieldNames
        )
        let expected = try await model.tokenCount(for: instructions)
            + model.tokenCount(for: prompt)
            + model.tokenCount(for: built.schema)

        #expect(session.usage.inputTokens == expected)
        print("LIVE no state usage: inputTokens=\(session.usage.inputTokens) "
            + "expected=\(expected)")
    }

    /// Pins a limit of the on-device model. Paris is the capital of France
    /// and Berlin is the capital of Germany, so both answers should be true;
    /// asked in one request under the ids `capital` and `control`, the model
    /// says false to both. Other id pairs, such as `q1` and `q2`, answer both
    /// right, so the cause is the field names, not the questions. A future OS
    /// model that answers this pair right turns the test red on purpose: read
    /// the numbers, then update the test and DESIGN.md 10.1.
    @Test("Two yes-or-no questions on one topic come back with one answer")
    func twoVerdictsOnOneTopic() async throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        guard modelIsReady() else { return }
        let session = DecisionSession(model: GuidedGenerationModel(.default))

        let questionnaire = Questionnaire {
            Verify("capital", "Is Paris the capital of France?")
            Verify("control", "Is Berlin the capital of Germany?")
        }

        let answers = try await session.decide(questionnaire)

        guard case .verdict(let capital)? = answers.records["capital"],
              case .verdict(let control)? = answers.records["control"]
        else {
            Issue.record("The answers are not verdicts.")
            return
        }
        #expect(capital == 0)
        #expect(control == 0)

        print("LIVE one topic: capital=\(capital) control=\(control)")
    }

    @Test("Three samples give an empirical distribution")
    func threeSamples() async throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        guard modelIsReady() else { return }
        let session = DecisionSession(
            model: GuidedGenerationModel(.default),
            options: DecisionOptions(samples: 3)
        )

        let answers = try await session.decide(
            supportQuestionnaire,
            about: "Wrong size shoes arrived, I want my money back"
        )

        #expect(answers.quality == .sampled(count: 3))
        #expect(session.usage.requests == 3)

        guard case .choice(_, let teams, _)? = answers.records["team"],
              case .rating(_, let levels, _)? = answers.records["severity"],
              case .verdict(let refund)? = answers.records["refund"]
        else {
            Issue.record("The response is not shaped like the questionnaire.")
            return
        }
        #expect(isClose(teams.values.reduce(0, +), 1))
        #expect(isClose(levels.values.reduce(0, +), 1))
        #expect((0...1).contains(refund))

        print("LIVE three samples: teams=\(teams) levels=\(levels) refund=\(refund) "
            + "usage=\(session.usage)")
    }

    @Test("A hand-written decision reads back as plain Swift values")
    func handWrittenDecision() async throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        guard modelIsReady() else { return }
        let session = DecisionSession(model: GuidedGenerationModel(.default))

        let triage: TicketTriage = try await session.decide(
            about: """
            My order arrived with the wrong size shoes. I cannot wear them at \
            all. Please refund my money.
            """
        )

        // The team and the refund are in the words of the message. The
        // severity is a judgement call, so the test does not hold the model
        // to one level: a change of wording would break it for reasons that
        // have nothing to do with the adapter.
        #expect(triage.team == .returns)
        #expect(triage.requestsRefund)

        print("LIVE decision: team=\(triage.team) severity=\(triage.severity) "
            + "requestsRefund=\(triage.requestsRefund) "
            + "teamConfidence=\(triage._team.confidence)")
    }

    @Test("A timeout bounds the whole call, not each draw")
    func timeoutBoundsTheWholeCall() async throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        guard modelIsReady() else { return }
        // One draw fits this budget. Three do not, so a per-draw timeout
        // would let all three run and come back at three times the deadline.
        let budget = Duration.milliseconds(800)
        let session = DecisionSession(
            model: GuidedGenerationModel(.default),
            options: DecisionOptions(timeout: budget, samples: 3)
        )

        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await session.decide(
                supportQuestionnaire,
                about: "Wrong size shoes arrived, I want my money back"
            )
            Issue.record("Three draws finished inside a budget that holds one.")
        } catch DecisionError.timeout {
            // Expected: the budget ran out part way through the draws.
        }
        let elapsed = clock.now - start

        #expect(elapsed < budget + .milliseconds(500))
        print("LIVE deadline: budget=\(budget) elapsed=\(elapsed)")
    }

    @Test("Usage counts the instructions, the prompt, and the schema")
    func usageAddsUp() async throws {
        guard #available(macOS 26.4, iOS 26.4, *) else { return needsMacOS264() }
        guard modelIsReady() else { return }
        let model = SystemLanguageModel.default
        let session = DecisionSession(model: GuidedGenerationModel(model))
        let state = "Wrong size shoes arrived, I want my money back"

        _ = try await session.decide(supportQuestionnaire, about: state)

        // The same three texts the adapter sends, counted here on their own.
        let built = try SchemaBuilder.build(supportQuestionnaire)
        let instructions = DecisionPromptBuilder.instructions()
        let prompt = DecisionPromptBuilder.prompt(
            state: .text(state),
            questionnaire: supportQuestionnaire,
            fieldNames: built.fieldNames
        )
        let expected = try await model.tokenCount(for: instructions)
            + model.tokenCount(for: prompt)
            + model.tokenCount(for: built.schema)

        #expect(session.usage.inputTokens == expected)
        #expect(session.usage.outputTokens == 0)
        #expect(session.usage.requests == 1)
        print("LIVE usage: inputTokens=\(session.usage.inputTokens) expected=\(expected)")
    }
}

// MARK: Fixtures

/// The run-time questionnaire most tests here ask.
///
/// Every criterion here is a plain summary to keep the prompt short; the
/// adapter also takes structured criteria and renders them as text.
let supportQuestionnaire = Questionnaire([
    QuestionSpec(
        id: "team",
        instructions: "Which team should handle this customer message?",
        kind: .choice(options: [
            QuestionSpec.OptionSpec(
                id: "returns",
                criterion: "Returns, exchanges, and refunds of goods already delivered"
            ),
            QuestionSpec.OptionSpec(
                id: "shipping",
                criterion: "Delivery, tracking, and parcels that never arrived"
            ),
            QuestionSpec.OptionSpec(
                id: "billing",
                criterion: "Payments, invoices, and card charges"
            ),
        ])
    ),
    QuestionSpec(
        id: "severity",
        instructions: "How much does this problem hurt the customer?",
        kind: .rating(levels: [
            "Small; the customer can still use what they bought",
            "The customer is held up, but has a way around it",
            "The customer is fully blocked and can do nothing",
        ])
    ),
    QuestionSpec(
        id: "refund",
        instructions: "Does the customer ask for money back?",
        kind: .verdict(
            ifTrue: "The message asks for a refund or money back",
            ifFalse: "The message asks for anything else"
        )
    ),
])

/// The section 12 expansion, written by hand. A test target cannot share
/// code with another test target, so the shape is copied from
/// `DecisionModelsTests/SessionTests.swift`, with plain criteria.
enum Team: String, ChoiceOption, CaseIterable, Codable {
    case returns, shipping, billing

    var optionID: String { rawValue }

    var criterion: Criterion {
        switch self {
        case .returns: "Returns, exchanges, and refunds of goods already delivered"
        case .shipping: "Delivery, tracking, and parcels that never arrived"
        case .billing: "Payments, invoices, and card charges"
        }
    }
}

enum Severity: String, RatingLevel, CaseIterable, Codable {
    case cosmetic, degraded, blocking

    var optionID: String { rawValue }

    var criterion: Criterion {
        switch self {
        case .cosmetic: "Small; the customer can still use what they bought"
        case .degraded: "The customer is held up, but has a way around it"
        case .blocking: "The customer is fully blocked and can do nothing"
        }
    }

    static func < (left: Severity, right: Severity) -> Bool {
        let order = Array(allCases)
        return order.firstIndex(of: left)! < order.firstIndex(of: right)!
    }
}

extension Team: Askable {
    typealias Projection = Choice<Team>
}

extension Severity: Askable {
    typealias Projection = Rating<Severity>
}

struct TicketTriage: Decision {
    var _team: Team.Projection
    var team: Team { Team.read(_team) }

    var _severity: Severity.Projection
    var severity: Severity { Severity.read(_severity) }

    var _requestsRefund: Bool.Projection
    var requestsRefund: Bool { Bool.read(_requestsRefund) }

    static let questions = Questionnaire(
        Team.questions(id: "team", Inquiry("Which team should handle this ticket?"))
            + Severity.questions(
                id: "severity",
                Inquiry("How much does this problem hurt the customer?")
            )
            + Bool.questions(
                id: "requestsRefund",
                Inquiry(
                    "Does the customer ask for money back?",
                    ifTrue: "The message asks for a refund or money back",
                    ifFalse: "The message asks for anything else"
                )
            )
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
}
#endif
