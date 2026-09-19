import DecisionModels
import Synchronization
import Testing

// The section 4 example, written with the macros and nothing else.

@Options
enum Team {
    @Criterion("Exchanges and refunds") case returns
    @Criterion("Delivery issues") case shipping
    @Criterion("Payment problems") case billing
}

@Levels  // declaration order is low to high
enum Severity {
    @Criterion("Cosmetic; no impact to functionality")
    case cosmetic
    @Criterion("Broken or degraded feature, but a workaround exists")
    case degraded
    @Criterion("Blocking issue; no workaround exists")
    case blocking
}

@Decision
struct TicketTriage {
    @Ask("Which team handles this ticket?")
    var team: Team

    @Ask("How severe is the reported issue?")
    var severity: Severity

    @Ask("Does the customer ask for a refund?")
    var requestsRefund: Bool

    /// Plain Swift. The decision logic lives with the questions.
    var needsHuman: Bool {
        $team.confidence < 0.5 || (severity == .blocking && $severity.confidence < 0.8)
    }
}

@Decision
struct BugReport {
    @Ask("How severe is the issue?")
    var severity: Severity

    @Ask("Can the issue be reproduced from the description?")
    var reproducible: Bool
}

@Decision
struct Intake {
    @Ask("Which team handles this ticket?", minimumConfidence: 0.7)
    var team: Team?

    @Ask()
    var bug: BugReport
}

/// The other two `@Ask` forms: what each side of a yes or no means, and
/// structured instructions, as Jev accepts them.
@Decision
struct Invoice {
    @Ask(
        "Does the customer ask for a refund?",
        ifTrue: Criterion("The customer wants money back", examples: ["chargeback"]),
        ifFalse: "The customer wants a fix, a replacement, or information"
    )
    var requestsRefund: Bool

    @Ask(
        instructions: [
            "question": "Is the amount in `invoice.total` consistent with `invoice.lines`?",
            "focus": "arithmetic consistency only",
        ]
    )
    var totalsMatch: Bool
}

// A public answer space and a public decision, to prove the access modifiers
// travel.

@Options
public enum Desk {
    @Criterion("Money questions") case billing
    case everythingElse
}

@Decision
public struct FrontDesk {
    @Ask("Which desk takes this?")
    public var desk: Desk
}

// A decision inside a namespace. The generated members sit in the struct, so
// `Team` here is `Fixtures.Team`, not the one at file scope.
enum Fixtures {
    @Options
    enum Team {
        case hardware
        case software
    }

    @Decision
    struct Inner {
        @Ask("Which team handles this ticket?")
        var team: Team
    }
}

/// A decision with a type parameter. `questions` computes itself, because a
/// generic type takes no stored static.
@Decision
struct Tagged<Tag> {
    @Ask("Which team handles this ticket?")
    var team: Team
}

/// A description of its own does not change what goes on the wire.
@Options
enum Channel: CustomStringConvertible {
    case email
    case chat

    var description: String { "the \(optionID) channel" }
}

/// Names that need backticks, in the answer space and in the decision.
@Options
enum Fallback {
    case `default`
    case escalate
}

@Decision
struct Routing {
    @Ask("Which fallback applies?")
    var `default`: Fallback
}

/// Runs of capitals stay as they are when a case names itself.
@Options
enum Fault {
    case URLIssue
    case httpURL
}

/// A model that keeps every request it got and answers from a closure.
/// Test targets share no code, so this is a copy of the fake in
/// `DecisionModelsTests`.
final class FakeModel: DecisionModel {
    let identity = DecisionModelIdentity(provider: "test", name: "fake")
    let capabilities = DecisionModelCapabilities(
        probabilityQuality: .calibrated,
        structuredCriteria: true,
        structuredInstructions: true,
        maximumOptionsPerChoice: 255,
        maximumLevelsPerRating: 10,
        supportsRepeatedSamples: true
    )
    private let script: @Sendable (DecisionRequest) throws -> ModelResponse
    private let received = Mutex<[DecisionRequest]>([])

    init(script: @escaping @Sendable (DecisionRequest) throws -> ModelResponse) {
        self.script = script
    }

    convenience init(answers: Answers) {
        self.init { _ in ModelResponse(answers: answers, requestID: "fake-1") }
    }

    var availability: DecisionModelAvailability { get async { .available } }

    func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        received.withLock { $0.append(request) }
        return try script(request)
    }

    /// Every request the session sent.
    var requests: [DecisionRequest] { received.withLock { $0 } }
}

/// What the fake answers for the triage example.
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

func isClose(_ value: Double, _ expected: Double, within tolerance: Double = 0.01) -> Bool {
    abs(value - expected) <= tolerance
}

@Suite("The macros end to end")
struct EndToEndTests {
    @Test("The section 4 example runs against a model")
    func sectionFourRuns() async throws {
        let model = FakeModel(answers: triageAnswers)
        let session = DecisionSession(model: model)

        let triage: TicketTriage = try await session.decide(about: "The blender arrived broken.")

        #expect(triage.team == .returns)
        #expect(triage.severity == .degraded)
        #expect(triage.requestsRefund)
        #expect(isClose(triage.$team.probabilities[.returns] ?? 0, 0.91))
        #expect(isClose(triage.$team.probabilities[.shipping] ?? 0, 0.06))
        #expect(isClose(triage.$severity.score, 1.3))
        #expect(isClose(triage.$requestsRefund.probability, 0.87))
        #expect(!triage.needsHuman)
    }

    @Test("A thin answer asks for a person")
    func lowConfidenceNeedsHuman() throws {
        let answers = Answers(
            records: [
                "team": .choice(
                    reported: "returns",
                    probabilities: ["returns": 0.4, "shipping": 0.35, "billing": 0.25],
                    confidence: 0.4
                ),
                "severity": .rating(score: 1, probabilities: [0: 0, 1: 1, 2: 0], confidence: nil),
                "requestsRefund": .verdict(probability: 0.2),
            ],
            quality: .calibrated
        )

        let triage = try TicketTriage(answers: answers)

        #expect(triage.needsHuman)
        #expect(!triage.requestsRefund)
    }

    @Test("The questions carry the criteria and the order of the cases")
    func questionsCarryCriteria() {
        let specs = TicketTriage.questions.specs

        #expect(specs.map(\.id) == ["team", "severity", "requestsRefund"])
        guard case .choice(let options) = specs[0].kind else {
            Issue.record("The first question is not a choice.")
            return
        }
        #expect(options.map(\.id) == ["returns", "shipping", "billing"])
        #expect(options[0].criterion == Criterion("Exchanges and refunds"))
        guard case .rating(let levels) = specs[1].kind else {
            Issue.record("The second question is not a rating.")
            return
        }
        #expect(levels.first?.summary == "Cosmetic; no impact to functionality")
        guard case .verdict = specs[2].kind else {
            Issue.record("The third question is not a verdict.")
            return
        }
        #expect(specs[2].instructions == .text("Does the customer ask for a refund?"))
    }

    @Test("A yes or no question carries what each side means")
    func branchesReachTheSpec() {
        guard case .verdict(let ifTrue, let ifFalse) = Invoice.questions.specs[0].kind else {
            Issue.record("The first question is not a verdict.")
            return
        }
        #expect(ifTrue?.summary == "The customer wants money back")
        #expect(ifTrue?.examples == ["chargeback"])
        #expect(ifFalse == Criterion("The customer wants a fix, a replacement, or information"))
    }

    @Test("Structured instructions reach the spec as an object")
    func structuredInstructionsReachTheSpec() {
        #expect(
            Invoice.questions.specs[1].instructions
                == .object([
                    "question": .text(
                        "Is the amount in `invoice.total` consistent with `invoice.lines`?"
                    ),
                    "focus": .text("arithmetic consistency only"),
                ])
        )
    }

    @Test("A case without a criterion says its name in words")
    func humanizedCriterion() {
        #expect(Desk.everythingElse.criterion == Criterion("everything else"))
        #expect(Desk.billing.optionID == "billing")
        #expect(Desk.allCases.count == 2)
    }

    @Test("A levels enum compares by declaration order")
    func levelsCompare() {
        #expect(Severity.cosmetic < Severity.degraded)
        #expect(Severity.blocking > Severity.degraded)
        #expect(Array(Severity.allCases) == [.cosmetic, .degraded, .blocking])
    }

    @Test("A nested decision asks dotted questions in one request")
    func nestedQuestionsAreDotted() async throws {
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

        #expect(
            model.requests.first?.questionnaire.specs.map(\.id)
                == ["team", "bug.severity", "bug.reproducible"]
        )
        #expect(intake.team == .shipping)
        #expect(intake.bug.severity == .cosmetic)
        #expect(intake.bug.reproducible)
        #expect(intake.$bug.$reproducible.probability == 0.95)
    }

    @Test("An optional gates on its threshold")
    func optionalGating() throws {
        let thin = Answers(
            records: [
                "team": .choice(
                    reported: "returns",
                    probabilities: ["returns": 0.4, "shipping": 0.35, "billing": 0.25],
                    confidence: 0.4
                ),
                "bug.severity": .rating(
                    score: 1, probabilities: [0: 0, 1: 1, 2: 0], confidence: nil
                ),
                "bug.reproducible": .verdict(probability: 0.1),
            ],
            quality: .calibrated
        )

        #expect(try Intake(answers: thin).team == nil)
    }

    @Test("The plain-value initializer round-trips through answers")
    func plainValuesRoundTrip() throws {
        let triage = TicketTriage(team: .billing, severity: .cosmetic, requestsRefund: false)

        #expect(triage.team == .billing)
        #expect(triage.severity == .cosmetic)
        #expect(!triage.requestsRefund)

        let again = try TicketTriage(answers: triage.answers)

        #expect(again.team == .billing)
        #expect(again.severity == .cosmetic)
        #expect(!again.requestsRefund)
        #expect(triage.answers.records.keys.sorted() == ["requestsRefund", "severity", "team"])
    }

    @Test("A nil plain value stores an uncertain answer that gates to nil")
    func nilStoresUncertain() throws {
        let intake = Intake(team: nil, bug: BugReport(severity: .cosmetic, reproducible: false))

        #expect(intake.team == nil)
        #expect(isClose(intake.$team.confidence, 0))
        #expect(intake.answers.records.keys.sorted() == ["bug.reproducible", "bug.severity", "team"])
        #expect(try Intake(answers: intake.answers).team == nil)
    }

    @Test("A public decision keeps its access")
    func publicDecisionCompiles() throws {
        let desk = FrontDesk(desk: .billing)

        #expect(desk.desk == .billing)
        #expect(FrontDesk.questions.specs.map(\.id) == ["desk"])
        #expect(try FrontDesk(answers: desk.answers).desk == .billing)
    }

    @Test("A decision in a namespace names its siblings")
    func namespacedDecision() throws {
        let specs = Fixtures.Inner.questions.specs

        #expect(specs.map(\.id) == ["team"])
        guard case .choice(let options) = specs[0].kind else {
            Issue.record("The question is not a choice.")
            return
        }
        #expect(options.map(\.id) == ["hardware", "software"])
        #expect(Fixtures.Inner(team: .software).team == .software)
    }

    @Test("A generic decision compiles and answers")
    func genericDecision() throws {
        let tagged = Tagged<Int>(team: .billing)

        #expect(tagged.team == .billing)
        #expect(Tagged<Int>.questions.specs.map(\.id) == ["team"])
        #expect(try Tagged<Int>(answers: tagged.answers).team == .billing)
    }

    @Test("A description of its own leaves the wire ids alone")
    func descriptionDoesNotRenameOptions() {
        #expect(Channel.email.optionID == "email")
        #expect(Channel.chat.optionID == "chat")
        #expect(String(describing: Channel.email) == "the email channel")
    }

    @Test("A name that needs backticks keeps them")
    func rawIdentifiers() throws {
        #expect(Fallback.default.optionID == "default")

        // The label needs no backticks at the call, though the parameter the
        // macro declares does.
        let routing = Routing(default: .escalate)

        #expect(routing.default == .escalate)
        #expect(routing.$default.value == .escalate)
        #expect(Routing.questions.specs.map(\.id) == ["default"])
        #expect(routing.answers.records.keys.sorted() == ["default"])
        #expect(try Routing(answers: routing.answers).default == .escalate)
    }

    @Test("A run of capitals stays a word")
    func acronymsSurviveHumanizing() {
        #expect(Fault.URLIssue.criterion == Criterion("URL issue"))
        #expect(Fault.httpURL.criterion == Criterion("http URL"))
    }
}
