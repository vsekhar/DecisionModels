import DecisionModels
import DecisionModelsTesting
import Foundation
import Testing

@Suite("Recording and replay")
struct RecordReplayTests {
    /// Runs one triage through a recording wrapper and hands back what it kept.
    private func recordOneTriage() async throws -> (
        scripted: ScriptedModel, records: [DecisionRecord], triage: TicketTriage
    ) {
        let scripted = ScriptedModel(answering: triageAnswers)
        let recorder = Recorder()
        let session = DecisionSession(
            model: RecordingModel(scripted, into: recorder),
            options: DecisionOptions(metadata: ["trace": "t-1"])
        )
        let triage: TicketTriage = try await session.decide(about: "The blender arrived broken.")
        return (scripted, await recorder.records, triage)
    }

    @Test("A recording keeps the request, the response, and the model")
    func recordingKeepsTheCall() async throws {
        let (scripted, records, triage) = try await recordOneTriage()

        #expect(triage.team == .returns)
        #expect(records.count == 1)
        let record = try #require(records.first)
        #expect(record.request.state == .text("The blender arrived broken."))
        #expect(record.request.questionnaire == TicketTriage.questions)
        #expect(record.request.samples == 1)
        #expect(record.request.metadata == ["trace": "t-1"])
        #expect(record.response.answers == triageAnswers)
        #expect(record.response.usage == .zero)
        #expect(record.model == DecisionModelIdentity(provider: "test", name: "scripted"))
        #expect(record.duration > .zero)
        #expect(scripted.callCount == 1)
    }

    @Test("A recording wrapper forwards the model it wraps")
    func recordingForwards() async throws {
        let scripted = ScriptedModel(
            answering: triageAnswers,
            identity: DecisionModelIdentity(provider: "test", name: "inner"),
            capabilities: DecisionModelCapabilities(probabilityQuality: .sampled(count: 4))
        )
        let recording = RecordingModel(scripted, into: Recorder())

        #expect(recording.identity == scripted.identity)
        #expect(recording.capabilities.probabilityQuality == .sampled(count: 4))
        if case .unavailable = await recording.availability {
            Issue.record("The wrapper reports the inner model unavailable.")
        }
    }

    @Test("A failed call is not recorded")
    func failuresAreNotRecorded() async throws {
        let recorder = Recorder()
        let failing = ScriptedModel { _ in throw DecisionError.overloaded }
        let session = DecisionSession(model: RecordingModel(failing, into: recorder))

        await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }

        #expect(await recorder.records.isEmpty)
        #expect(failing.callCount == 1)
    }

    @Test("A replay serves the recorded response back")
    func replayServesTheRecording() async throws {
        let (scripted, records, _) = try await recordOneTriage()
        let replay = ReplayModel(records: records)
        let record = try #require(records.first)

        #expect(replay.identity == DecisionModelIdentity(provider: "test", name: "scripted"))
        #expect(replay.capabilities.probabilityQuality == .calibrated)
        #expect(replay.count == 1)

        let response = try await replay.decide(record.request)
        #expect(response.answers == record.response.answers)
        #expect(response.usage == record.response.usage)
        #expect(response.requestID == record.response.requestID)

        // The whole decision comes back out of the fixture, with no model.
        let triage: TicketTriage = try await DecisionSession(model: replay)
            .decide(about: "The blender arrived broken.")
        #expect(triage.team == .returns)
        #expect(triage.severity == .degraded)
        #expect(triage.requestsRefund)
        // Nothing reached the model that made the recording.
        #expect(scripted.callCount == 1)
    }

    @Test("Metadata and the timeout do not change the match")
    func metadataDoesNotKey() async throws {
        let (_, records, _) = try await recordOneTriage()
        let replay = ReplayModel(records: records)
        let recorded = try #require(records.first).request

        let again = DecisionRequest(
            state: recorded.state,
            questionnaire: recorded.questionnaire,
            samples: recorded.samples,
            timeout: .seconds(30),
            metadata: ["trace": "t-2", "run": "nightly"]
        )

        #expect(replay.holds(again))
        #expect(try await replay.decide(again).answers == triageAnswers)
        #expect(ReplayKey(again) == ReplayKey(recorded))
    }

    @Test("A different state or sample count misses")
    func missesThrow() async throws {
        let (_, records, _) = try await recordOneTriage()
        let replay = ReplayModel(records: records)
        let recorded = try #require(records.first).request

        let otherState = DecisionRequest(
            state: "The blender works fine.",
            questionnaire: recorded.questionnaire,
            samples: recorded.samples
        )
        let otherSamples = DecisionRequest(
            state: recorded.state,
            questionnaire: recorded.questionnaire,
            samples: 3
        )

        #expect(!replay.holds(otherState))
        #expect(!replay.holds(otherSamples))

        for miss in [otherState, otherSamples] {
            await #expect(throws: DecisionError.self) { _ = try await replay.decide(miss) }
            do {
                _ = try await replay.decide(miss)
                Issue.record("The replay answered a request it never saw.")
            } catch DecisionError.malformedResponse(let reason) {
                #expect(reason == "No recording for this request")
            }
        }
    }

    @Test("An empty replay reports a point estimate and a test identity")
    func emptyReplay() async throws {
        let replay = ReplayModel(records: [])
        #expect(replay.identity == DecisionModelIdentity(provider: "test", name: "replay"))
        #expect(replay.capabilities.probabilityQuality == .pointEstimate)
        #expect(replay.count == 0)
    }

    @Test("Records round-trip through a file")
    func recordsRoundTripThroughJSON() async throws {
        let (_, recorded, _) = try await recordOneTriage()
        let recorder = Recorder(
            records: recorded + [
                DecisionRecord(
                    request: DecisionRequest(
                        state: .object(["message": .text("no power"), "orders": .number(3)]),
                        questionnaire: TicketTriage.questions,
                        samples: 2,
                        timeout: .seconds(5),
                        metadata: ["trace": "t-2"]
                    ),
                    response: ModelResponse(
                        answers: triageAnswers,
                        usage: Usage(inputTokens: 40, outputTokens: 7, requests: 1),
                        requestID: "req-7"
                    ),
                    model: DecisionModelIdentity(provider: "typesafe", name: "jev-1.13.0"),
                    duration: .milliseconds(1250),
                    recordedAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
                )
            ]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("records.json")

        try await recorder.write(to: url)
        let read = try Recorder.read(from: url)

        #expect(read == (await recorder.records))
        #expect(read.count == 2)
        #expect(read[1].duration == .milliseconds(1250))
        #expect(read[1].response.requestID == "req-7")
        #expect(read[1].response.usage == Usage(inputTokens: 40, outputTokens: 7, requests: 1))

        // The file is JSON a person can read, and a replay can open it.
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\n"))
        let replay = try ReplayModel(contentsOf: url)
        #expect(replay.count == 2)
    }

    @Test("A call count counts, and every copy shares it")
    func callCountCounts() async throws {
        let scripted = ScriptedModel(answering: triageAnswers)
        #expect(scripted.callCount == 0)

        let session = DecisionSession(model: scripted)
        for _ in 0..<3 {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }
        #expect(scripted.callCount == 3)

        // A copy inside a wrapper counts into the same box.
        let copy = scripted
        _ = try await DecisionSession(model: RecordingModel(copy, into: Recorder()))
            .decide(TicketTriage.self, about: "broken")
        #expect(scripted.callCount == 4)
        #expect(copy.callCount == 4)
    }

    @Test("An unavailable model is never called")
    func unavailableModelIsNotCalled() async throws {
        let scripted = ScriptedModel(
            answering: triageAnswers,
            availability: .unavailable(.offline)
        )
        let session = DecisionSession(model: scripted)

        await #expect(throws: DecisionError.self) {
            _ = try await session.decide(TicketTriage.self, about: "broken")
        }
        #expect(scripted.callCount == 0)
    }
}
