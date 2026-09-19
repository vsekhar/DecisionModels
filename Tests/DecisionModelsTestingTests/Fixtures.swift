import DecisionModels
import DecisionModelsTesting

// Test targets cannot share code, so the triage example of DESIGN.md section 4
// is written out again here, by hand, exactly as the macro will emit it. A
// hand-written type cannot declare `$`-prefixed names, so the projection peers
// are `_team` and so on.

/// A hand-written options enum.
enum Team: String, ChoiceOption, CaseIterable, Codable {
    case returns, shipping, billing

    var optionID: String { rawValue }

    var criterion: Criterion {
        switch self {
        case .returns: "Exchanges and refunds"
        case .shipping: "Delivery issues"
        case .billing: "Payment problems"
        }
    }
}

/// A hand-written levels enum, low to high.
enum Severity: String, RatingLevel, CaseIterable, Codable {
    case cosmetic, degraded, blocking

    var optionID: String { rawValue }

    var criterion: Criterion {
        switch self {
        case .cosmetic: "Cosmetic; no impact to functionality"
        case .degraded: "Broken or degraded feature, but a workaround exists"
        case .blocking: "Blocking issue; no workaround exists"
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

/// The three-question decision of DESIGN.md section 4.
struct TicketTriage: Decision {
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

/// A one-question decision, for the calibration arithmetic.
struct RefundCheck: Decision {
    var _requestsRefund: Bool.Projection
    var requestsRefund: Bool { Bool.read(_requestsRefund) }

    static let questions = Questionnaire(
        Bool.questions(id: "requestsRefund", Inquiry("Does the customer ask for a refund?"))
    )

    init(answers: Answers) throws {
        _requestsRefund = try Bool.projection(in: answers, id: "requestsRefund")
    }

    var answers: Answers {
        Answers(
            records: ["requestsRefund": _requestsRefund.record],
            quality: _requestsRefund.quality
        )
    }

    init(requestsRefund: Bool) {
        _requestsRefund = Verdict(certain: requestsRefund)
    }
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

func isClose(_ value: Double, _ expected: Double, within tolerance: Double = 0.01) -> Bool {
    abs(value - expected) <= tolerance
}

/// Builds a labeled set of yes and no questions and a model that answers each
/// one with the probability the row names.
///
/// Every row gets its own state, so the script can tell the examples apart.
func verdictSet(
    _ rows: [(probability: Double, expected: Bool)]
) -> (labeled: [(state: State, expected: RefundCheck)], model: ScriptedModel) {
    var labeled: [(state: State, expected: RefundCheck)] = []
    var script: [State: Answers] = [:]
    for (index, row) in rows.enumerated() {
        let state = State.text("case-\(index)")
        labeled.append((state: state, expected: RefundCheck(requestsRefund: row.expected)))
        script[state] = Answers(
            records: ["requestsRefund": .verdict(probability: row.probability)],
            quality: .calibrated
        )
    }
    let answered = script
    let model = ScriptedModel { request in
        guard let answers = answered[request.state] else {
            throw DecisionError.malformedResponse("The script has no answer for this state.")
        }
        return answers
    }
    return (labeled, model)
}
