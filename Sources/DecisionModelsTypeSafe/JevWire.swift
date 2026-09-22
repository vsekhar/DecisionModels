import DecisionModels
import Foundation

// The shapes that go on the wire, field for field. Nothing here knows about
// `Questionnaire` or `Answers`; `JevMapping` joins the two levels.

// MARK: The request

/// The body of `POST /v1/systemone`.
struct JevRequest: Encodable, Sendable {
    /// The material to judge: a text, an object, or an array. Absent when the
    /// request has none; the encoder then omits the field.
    var state: State?
    /// An alias such as `jev-latest`, or a pinned version.
    var model: String
    /// The questions, by id.
    var questions: [String: Question]

    enum CodingKeys: String, CodingKey {
        case state
        case model
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

    /// The three answer spaces the service knows.
    enum Kind: String, Codable, Sendable {
        case choice
        case score
        case noul
    }
}

// MARK: The response

/// The body of a successful `POST /v1/systemone`.
struct JevResponse: Decodable {
    /// The pinned version that answered, such as `jev-1.13.0`.
    var model: String?
    var answers: [String: JevAnswer]
    var usage: JevUsage?

    enum CodingKeys: String, CodingKey {
        case model
        case answers
        case usage
    }
}

/// What the request cost.
struct JevUsage: Decodable {
    var inputTokens: Int
    var outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

/// One answer. The `type` field picks the shape.
enum JevAnswer: Decodable {
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
        case JevRequest.Kind.choice.rawValue: self = .choice(try Choice(from: decoder))
        case JevRequest.Kind.score.rawValue: self = .score(try Score(from: decoder))
        case JevRequest.Kind.noul.rawValue: self = .noul(try Noul(from: decoder))
        default:
            throw DecisionError.malformedResponse(
                "The answer type \(type) is not one this provider knows."
            )
        }
    }
}

// MARK: The model list

/// The body of `GET /v1/models`. The service may send the list bare or under
/// a field, so both shapes decode.
struct JevModelList: Decodable {
    var models: [JevModel]

    private enum CodingKeys: String, CodingKey {
        case models
        case data
    }

    init(from decoder: any Decoder) throws {
        if let bare = try? [JevModel](from: decoder) {
            self.models = bare
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let listed = try container.decodeIfPresent([JevModel].self, forKey: .models) {
            self.models = listed
        } else {
            self.models = try container.decode([JevModel].self, forKey: .data)
        }
    }
}

/// One model the account can call.
struct JevModel: Decodable {
    var name: String
    var description: String?
    var releaseDate: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case id
        case description
        case releaseDate = "release_date"
        case releaseDateCamel = "releaseDate"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try? container.decode(String.self, forKey: .name) {
            self.name = name
        } else {
            self.name = try container.decode(String.self, forKey: .id)
        }
        self.description = try? container.decode(String.self, forKey: .description)
        self.releaseDate =
            (try? container.decode(String.self, forKey: .releaseDate))
            ?? (try? container.decode(String.self, forKey: .releaseDateCamel))
    }
}
