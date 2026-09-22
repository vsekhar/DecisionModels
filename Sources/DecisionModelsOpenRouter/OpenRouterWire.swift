import DecisionModels
import Foundation

// The shapes that go on the wire, field for field. Nothing here knows about
// `Questionnaire` or `Answers`; `OpenRouterMapping` joins the two levels.
//
// The endpoint is alpha. These shapes follow OpenRouter's docs as read on
// 2026-09-20, and they move when the endpoint does.

// MARK: The request

/// The body of `POST /api/alpha/decisions`.
///
/// OpenRouter also takes `provider`, `session_id`, `user`, and `trace`. The
/// provider sends none of them.
struct OpenRouterRequest: Encodable, Sendable {
    /// The model, in OpenRouter's `vendor/model` form.
    var model: String
    /// The material to judge: a text, an object, or an array. The service
    /// requires one and rejects a bare `null`, so a request with no state, or
    /// with a `.null` state, sends an empty string. The model then answers
    /// from the questions alone.
    var state: State
    /// The questions, by id.
    var questions: [String: Question]

    /// Builds a body. A `nil` state and a `.null` state both become an empty
    /// string; every other state goes as it is.
    init(model: String, state: State?, questions: [String: Question]) {
        self.model = model
        if let state, state != .null {
            self.state = state
        } else {
            self.state = .text("")
        }
        self.questions = questions
    }

    enum CodingKeys: String, CodingKey {
        case model
        case state
        case questions
    }

    /// One question: its answer space, what to judge, and what the answers
    /// mean.
    struct Question: Encodable, Sendable, Equatable {
        var type: Kind
        var instructions: State
        /// A map of option ids for a choice, an ordered array for a score,
        /// the two sides for a noul. Absent when the question needs none.
        var criteria: State?

        enum CodingKeys: String, CodingKey {
            case type
            case instructions
            case criteria
        }
    }

    /// The three answer spaces the endpoint knows.
    enum Kind: String, Codable, Sendable {
        case choice
        case score
        case noul
    }
}

// MARK: The response

/// The body of a successful `POST /api/alpha/decisions`.
struct OpenRouterResponse: Decodable {
    /// OpenRouter's id for the request.
    var id: String?
    /// The pinned model that answered, such as `typesafe/jev-1.13-20260917`.
    var model: String?
    /// Who answered, such as `TypeSafe`.
    var provider: String?
    var answers: [String: OpenRouterAnswer]
    var usage: OpenRouterUsage?

    enum CodingKeys: String, CodingKey {
        case id
        case model
        case provider
        case answers
        case usage
    }
}

/// What the request cost. OpenRouter also reports `cost` in dollars; the
/// provider does not read it.
struct OpenRouterUsage: Decodable {
    var inputTokens: Int
    var outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

/// One answer. The `type` field picks the shape.
///
/// OpenRouter's docs mark `probabilities` optional. The provider requires
/// it: it reports calibrated probabilities, and an answer with no
/// distribution cannot be read as one, so such a reply is malformed.
enum OpenRouterAnswer: Decodable {
    case choice(Choice)
    case score(Score)
    case noul(Noul)

    /// The named option, with the probability of every option.
    struct Choice: Decodable {
        var choice: String
        var probabilities: [String: Double]
        var confidence: Double?

        enum CodingKeys: String, CodingKey {
            case choice
            case probabilities
            case confidence
        }
    }

    /// The expected level, with the probability of every level. The keys of
    /// `probabilities` and `legend` are level indices written as strings.
    struct Score: Decodable {
        var score: Double
        var probabilities: [String: Double]
        var confidence: Double?
        var legend: [String: State]?

        enum CodingKeys: String, CodingKey {
            case score
            case probabilities
            case confidence
            case legend
        }
    }

    /// P(yes).
    struct Noul: Decodable {
        var noul: Double

        enum CodingKeys: String, CodingKey {
            case noul
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case OpenRouterRequest.Kind.choice.rawValue: self = .choice(try Choice(from: decoder))
        case OpenRouterRequest.Kind.score.rawValue: self = .score(try Score(from: decoder))
        case OpenRouterRequest.Kind.noul.rawValue: self = .noul(try Noul(from: decoder))
        default:
            throw DecisionError.malformedResponse(
                "The answer type \(type) is not one this provider knows."
            )
        }
    }
}
