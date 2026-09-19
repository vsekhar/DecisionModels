import DecisionModels
import Foundation

/// A model that answers from records instead of from a provider.
///
/// It matches on the state, the questionnaire, and the sample count. Metadata
/// and the timeout do not count, so a replay of a recorded run survives a new
/// trace id. A request with no record throws, because a silent default would
/// hide the gap in the fixtures.
public struct ReplayModel: DecisionModel {
    public let identity: DecisionModelIdentity
    public let capabilities: DecisionModelCapabilities
    private let responses: [ReplayKey: ModelResponse]

    /// Builds a replay from records.
    ///
    /// `identity` and `capabilities` come from the records when the caller
    /// passes neither: the identity of the first record, and the capabilities
    /// that `capabilities(for:)` derives. When two records share a key, the
    /// first one wins.
    public init(
        records: [DecisionRecord],
        identity: DecisionModelIdentity? = nil,
        capabilities: DecisionModelCapabilities? = nil
    ) {
        self.identity =
            identity
            ?? records.first?.model
            ?? DecisionModelIdentity(provider: "test", name: "replay")
        self.capabilities = capabilities ?? ReplayModel.capabilities(for: records)
        self.responses = Dictionary(
            records.map { ($0.key, $0.response) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Builds a replay from a file a `Recorder` wrote.
    public init(
        contentsOf url: URL,
        identity: DecisionModelIdentity? = nil,
        capabilities: DecisionModelCapabilities? = nil
    ) throws {
        self.init(
            records: try Recorder.read(from: url),
            identity: identity,
            capabilities: capabilities
        )
    }

    /// What a set of records can answer.
    ///
    /// A replay hands back what it holds, so every structural limit is open.
    /// Only the probability quality carries information: it is the worst
    /// quality among the recorded answers, so a session floor that the
    /// recording cannot meet still throws. A replay of a Jev recording
    /// reports `.calibrated`. Empty records report a point estimate.
    public static func capabilities(for records: [DecisionRecord]) -> DecisionModelCapabilities {
        DecisionModelCapabilities(
            probabilityQuality: records.map(\.response.answers.quality).min() ?? .pointEstimate,
            structuredCriteria: true,
            structuredInstructions: true,
            maximumOptionsPerChoice: .max,
            maximumLevelsPerRating: .max,
            maximumQuestionsPerRequest: nil,
            contextTokens: nil,
            supportsRepeatedSamples: true
        )
    }

    /// A replay is always ready.
    public var availability: DecisionModelAvailability {
        get async { .available }
    }

    /// How many distinct requests the replay can answer.
    public var count: Int { responses.count }

    /// Whether the replay holds an answer for a request.
    public func holds(_ request: DecisionRequest) -> Bool {
        responses[ReplayKey(request)] != nil
    }

    /// Hands back the recorded response, unchanged.
    public func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        guard let response = responses[ReplayKey(request)] else {
            throw DecisionError.malformedResponse("No recording for this request")
        }
        return response
    }
}
