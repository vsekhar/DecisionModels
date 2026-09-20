import DecisionModels
import DecisionModelsTestSupport

@testable import DecisionModelsTypeSafe

/// A model, its transport, and its clock, wired together.
struct Harness {
    var model: Jev
    var transport: ScriptedTransport
    var clock: FakeClock
}

/// Builds a model that talks to a script instead of the network.
func harness(
    _ replies: [Reply],
    retry: RetryPolicy = .default,
    apiKey: String? = "test-key",
    version: String = "jev-latest",
    sleep: (@Sendable (Duration) async -> Void)? = nil
) -> Harness {
    let clock = FakeClock()
    let transport = ScriptedTransport(replies, clock: clock)
    let model = Jev(
        version: version,
        apiKey: apiKey,
        retry: retry,
        transport: transport,
        environment: [:],
        sleep: sleep ?? clock.record,
        now: clock.reading
    )
    return Harness(model: model, transport: transport, clock: clock)
}

// MARK: Questions

/// The teams a ticket can go to.
enum Team: String, ChoiceOption, CaseIterable, Codable {
    case returns, shipping, billing

    var optionID: String { rawValue }

    var criterion: Criterion {
        switch self {
        case .returns:
            Criterion(
                "Exchanges and refunds",
                notFor: "Payment disputes",
                examples: ["wrong size", "arrived damaged"]
            )
        case .shipping: "Delivery issues"
        case .billing: "Payment problems"
        }
    }
}

/// How bad the problem is, low to high.
enum Severity: String, RatingLevel, CaseIterable, Codable {
    case cosmetic, degraded, blocking

    var optionID: String { rawValue }

    var criterion: Criterion {
        switch self {
        case .cosmetic: "Cosmetic; nothing stops working"
        case .degraded:
            Criterion(
                "A feature is broken, but a workaround exists",
                signals: ["reports an error"]
            )
        case .blocking: "Blocking; no workaround exists"
        }
    }

    static func < (left: Severity, right: Severity) -> Bool {
        let order = Array(allCases)
        return order.firstIndex(of: left)! < order.firstIndex(of: right)!
    }
}

/// The ticket the tests ask about.
let ticket: State = "Wrong size shoes arrived, I want my money back"

/// A questionnaire with one question of each kind.
func triage() -> Questionnaire {
    Questionnaire {
        Choose<Team>("team", "Which team should handle this ticket?")
        Rate<Severity>("severity", "How severe is the problem for the customer?")
        Verify("refund", "Does the customer ask for a refund?")
    }
}
