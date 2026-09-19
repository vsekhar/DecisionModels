import DecisionModels
import Foundation

/// Where records collect.
///
/// A recorder is an actor, so many concurrent calls can append to one file of
/// fixtures.
public actor Recorder {
    /// Every record so far, in the order the calls finished.
    public private(set) var records: [DecisionRecord]

    public init(records: [DecisionRecord] = []) {
        self.records = records
    }

    /// Keeps one record.
    public func append(_ record: DecisionRecord) {
        records.append(record)
    }

    /// Forgets everything.
    public func removeAll() {
        records.removeAll()
    }

    /// Writes the records to a file as pretty JSON, keys in order, so that a
    /// fixture checked into a repository has a readable diff.
    public func write(to url: URL) throws {
        try Recorder.encoder.encode(records).write(to: url, options: .atomic)
    }

    /// Reads records a `write(to:)` wrote.
    public static func read(from url: URL) throws -> [DecisionRecord] {
        try JSONDecoder().decode([DecisionRecord].self, from: Data(contentsOf: url))
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

/// A model that keeps every call it forwards.
///
/// It wraps a real model, times the call, and hands the answer back unchanged.
/// A failed call is rethrown and not recorded, so a fixture file holds answers
/// only.
public struct RecordingModel: DecisionModel {
    /// The model that does the work.
    public let model: any DecisionModel
    /// Where the records go.
    public let recorder: Recorder

    public init(_ model: some DecisionModel, into recorder: Recorder) {
        self.model = model
        self.recorder = recorder
    }

    public var identity: DecisionModelIdentity { model.identity }
    public var capabilities: DecisionModelCapabilities { model.capabilities }

    public var availability: DecisionModelAvailability {
        get async { await model.availability }
    }

    public func prewarm() async {
        await model.prewarm()
    }

    public func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        let clock = ContinuousClock()
        let start = clock.now
        let response = try await model.decide(request)
        let duration = clock.now - start
        await recorder.append(
            DecisionRecord(
                request: request,
                response: response,
                model: model.identity,
                duration: duration,
                recordedAt: Date()
            )
        )
        return response
    }
}
