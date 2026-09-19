@testable import DecisionModels

/// A hand-written options enum. The macros will generate this shape later.
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
        case .shipping:
            "Delivery issues"
        case .billing:
            "Payment problems"
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
        case .degraded:
            Criterion(
                "Broken or degraded feature, but a workaround exists",
                signals: ["reports an error"]
            )
        case .blocking: "Blocking issue; no workaround exists"
        }
    }

    static func < (left: Severity, right: Severity) -> Bool {
        let order = Array(allCases)
        return order.firstIndex(of: left)! < order.firstIndex(of: right)!
    }
}

/// A scale with one level only, for the edge case in the confidence formulas.
enum SingleLevel: String, RatingLevel, CaseIterable, Codable {
    case only

    var optionID: String { rawValue }
    var criterion: Criterion { "The only level" }

    static func < (left: SingleLevel, right: SingleLevel) -> Bool { false }
}

/// An option that exists only at run time.
struct Skill: ChoiceOption, Hashable, Codable {
    var id: String
    var summary: String

    var optionID: String { id }
    var criterion: Criterion { Criterion(summary) }
}

let catalog = [
    Skill(id: "search", summary: "Find something"),
    Skill(id: "refund", summary: "Give money back"),
    Skill(id: "escalate", summary: "Hand to a person"),
]

/// A struct for the `Encodable` paths.
struct Customer: Codable, Equatable {
    var name: String
    var orders: Int
    var vip: Bool
}

func isClose(_ value: Double, _ expected: Double, within tolerance: Double = 0.01) -> Bool {
    abs(value - expected) <= tolerance
}

// MARK: Askable

// The concrete type carries the `typealias`, as the macros will emit it. The
// framework defaults then pick the kind: `Choice` for an options enum, `Rating`
// for a levels enum, with no ambiguity even though a levels enum is also a
// `ChoiceOption` and `CaseIterable`.

extension Team: Askable {
    typealias Projection = Choice<Team>
}

extension Severity: Askable {
    typealias Projection = Rating<Severity>
}
