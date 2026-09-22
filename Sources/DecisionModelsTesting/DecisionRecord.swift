import DecisionModels
import Foundation

/// One request and the answer it got.
///
/// Records turn live traffic into fixtures: a `RecordingModel` writes them and
/// a `ReplayModel` serves them back.
public struct DecisionRecord: Sendable, Codable, Hashable {
    /// What the session sent.
    public var request: DecisionRequest
    /// What the model gave back.
    public var response: ModelResponse
    /// Which model answered.
    public var model: DecisionModelIdentity
    /// How long the call took.
    public var duration: Duration
    /// When the call ended.
    public var recordedAt: Date

    public init(
        request: DecisionRequest,
        response: ModelResponse,
        model: DecisionModelIdentity,
        duration: Duration,
        recordedAt: Date = Date()
    ) {
        self.request = request
        self.response = response
        self.model = model
        self.duration = duration
        self.recordedAt = recordedAt
    }

    /// Two records are equal when every field is, field by field.
    ///
    /// `ModelResponse` is not `Equatable`, so the three fields it holds are
    /// compared here.
    public static func == (left: DecisionRecord, right: DecisionRecord) -> Bool {
        left.request == right.request
            && left.model == right.model
            && left.duration == right.duration
            && left.recordedAt == right.recordedAt
            && left.response.answers == right.response.answers
            && left.response.usage == right.response.usage
            && left.response.requestID == right.response.requestID
    }

    /// Hashes the request and the model only.
    ///
    /// `ModelResponse` is not `Hashable`. A coarse hash is still a correct
    /// one: equal records hash the same, and records of one model for one
    /// request are few.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(request)
        hasher.combine(model)
    }
}

/// What a cache or a replay matches on.
///
/// A request also carries a timeout and metadata. Neither changes the answer,
/// so neither belongs in the key: a retry with a new trace id must still hit.
public struct ReplayKey: Sendable, Hashable, Codable {
    /// The material the model judged, or `nil`.
    public var state: State?
    /// The questions it answered.
    public var questionnaire: Questionnaire
    /// How many draws the caller asked for.
    public var samples: Int

    public init(state: State? = nil, questionnaire: Questionnaire, samples: Int = 1) {
        self.state = state
        self.questionnaire = questionnaire
        self.samples = samples
    }

    /// Takes the three fields of a request that decide the answer.
    public init(_ request: DecisionRequest) {
        self.init(
            state: request.state,
            questionnaire: request.questionnaire,
            samples: request.samples
        )
    }
}

extension DecisionRecord {
    /// The key this record answers.
    public var key: ReplayKey { ReplayKey(request) }
}
