import Synchronization
import Testing

@testable import DecisionModels

/// A model that counts `prewarm` calls. The composition suites share it.
final class PrewarmSpy: DecisionModel {
    let identity = DecisionModelIdentity(provider: "test", name: "spy")
    let capabilities = DecisionModelCapabilities.permissive
    private let warmed = Mutex<Int>(0)

    var availability: DecisionModelAvailability {
        get async { .available }
    }

    /// How many times someone warmed this model.
    var prewarmCount: Int { warmed.withLock { $0 } }

    func prewarm() async {
        warmed.withLock { $0 += 1 }
    }

    func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        ModelResponse(answers: Answers(quality: .pointEstimate))
    }
}

/// A choice over `Team`, so that a questionnaire holds real questions.
private func teamQuestion(_ id: String) -> QuestionSpec {
    Choose(id, "Which team handles this ticket?", among: Array(Team.allCases)).spec
}

/// A choice record with a stated confidence, so that the bar is exact.
private func answer(_ reported: String, confidence: Double) -> AnswerRecord {
    .choice(
        reported: reported,
        probabilities: ["returns": 0.5, "shipping": 0.3, "billing": 0.2],
        confidence: confidence
    )
}

@Suite("Cascade")
struct CascadeModelTests {
    static let questionnaire = Questionnaire([
        teamQuestion("a"), teamQuestion("b"), teamQuestion("c"),
    ])

    static let request = DecisionRequest(
        state: .object(["message": "The blender arrived broken."]),
        questionnaire: questionnaire,
        timeout: .seconds(5),
        metadata: ["tenant": "acme"]
    )

    /// A first model that is sure about `a` and `c` and unsure about `b`.
    func unsureAboutB() -> FakeModel {
        FakeModel(
            answers: Answers(
                records: [
                    "a": answer("returns", confidence: 0.95),
                    "b": answer("shipping", confidence: 0.2),
                    "c": answer("billing", confidence: 0.8),
                ],
                quality: .calibrated
            ),
            usage: Usage(inputTokens: 10, outputTokens: 2, requests: 1),
            requestID: "first-1"
        )
    }

    @Test("Only the weak answers reach the second model")
    func onlyWeakAnswersEscalate() async throws {
        let first = unsureAboutB()
        let second = FakeModel(
            answers: Answers(
                records: ["b": answer("returns", confidence: 0.99)],
                quality: .sampled(count: 4)
            ),
            usage: Usage(inputTokens: 40, outputTokens: 4, requests: 1),
            requestID: "second-1"
        )
        let cascade = CascadeModel(first: first, then: second, escalateBelow: 0.7)

        let report = try await cascade.decideWithReport(Self.request)

        #expect(report.escalated == ["b"])
        #expect(second.callCount == 1)
        let followUp = try #require(second.requests.first)
        #expect(followUp.questionnaire.specs.map(\.id) == ["b"])
        #expect(report.response.answers.records["b"] == answer("returns", confidence: 0.99))
        #expect(report.response.answers.records["a"] == answer("returns", confidence: 0.95))
        #expect(report.response.answers.records["c"] == answer("billing", confidence: 0.8))
    }

    @Test("A second model that answers everything changes only the weak answers")
    func onlyEscalatedAnswersMerge() async throws {
        let second = FakeModel(
            answers: Answers(
                records: [
                    "a": answer("billing", confidence: 0.99),
                    "b": answer("returns", confidence: 0.99),
                    "c": answer("shipping", confidence: 0.99),
                ],
                quality: .calibrated
            )
        )
        let cascade = CascadeModel(first: unsureAboutB(), then: second, escalateBelow: 0.7)

        let report = try await cascade.decideWithReport(Self.request)

        #expect(report.escalated == ["b"])
        #expect(report.response.answers.records["a"] == answer("returns", confidence: 0.95))
        #expect(report.response.answers.records["b"] == answer("returns", confidence: 0.99))
        #expect(report.response.answers.records["c"] == answer("billing", confidence: 0.8))
    }

    @Test("The follow-up keeps the state, the samples, the timeout, and the metadata")
    func followUpKeepsTheRequest() async throws {
        let second = FakeModel(
            answers: Answers(records: ["b": answer("returns", confidence: 0.99)], quality: .calibrated)
        )
        let cascade = CascadeModel(first: unsureAboutB(), then: second, escalateBelow: 0.7)

        _ = try await cascade.decide(Self.request)

        let followUp = try #require(second.requests.first)
        #expect(followUp.state == Self.request.state)
        #expect(followUp.samples == Self.request.samples)
        #expect(followUp.timeout == .seconds(5))
        #expect(followUp.metadata == ["tenant": "acme"])
    }

    @Test("The merged response sums usage, takes the lower quality, and the second id")
    func mergedResponse() async throws {
        let second = FakeModel(
            answers: Answers(
                records: ["b": answer("returns", confidence: 0.99)],
                quality: .sampled(count: 4)
            ),
            usage: Usage(inputTokens: 40, outputTokens: 4, requests: 1),
            requestID: "second-1"
        )
        let cascade = CascadeModel(first: unsureAboutB(), then: second, escalateBelow: 0.7)

        let response = try await cascade.decide(Self.request)

        #expect(response.usage == Usage(inputTokens: 50, outputTokens: 6, requests: 2))
        #expect(response.answers.quality == .sampled(count: 4))
        #expect(response.requestID == "second-1")
    }

    @Test("A response without a second id keeps the first one")
    func requestIDFallsBack() async throws {
        let second = FakeModel(
            answers: Answers(records: ["b": answer("returns", confidence: 0.99)], quality: .calibrated),
            requestID: nil
        )
        let cascade = CascadeModel(first: unsureAboutB(), then: second, escalateBelow: 0.7)

        #expect(try await cascade.decide(Self.request).requestID == "first-1")
    }

    @Test("Strong answers never reach the second model")
    func confidentAnswersStand() async throws {
        let second = FakeModel(answers: Answers(quality: .pointEstimate))
        let cascade = CascadeModel(first: unsureAboutB(), then: second, escalateBelow: 0.1)

        let report = try await cascade.decideWithReport(Self.request)

        #expect(report.escalated.isEmpty)
        #expect(second.callCount == 0)
        #expect(report.response.requestID == "first-1")
        #expect(report.response.usage == Usage(inputTokens: 10, outputTokens: 2, requests: 1))
        #expect(report.response.answers.quality == .calibrated)
    }

    @Test("The escalated list follows the order of the questions")
    func escalatedKeepsOrder() async throws {
        let first = FakeModel(
            answers: Answers(
                records: [
                    "a": answer("returns", confidence: 0.1),
                    "b": answer("shipping", confidence: 0.9),
                    "c": answer("billing", confidence: 0.2),
                ],
                quality: .calibrated
            )
        )
        let second = FakeModel(
            answers: Answers(
                records: [
                    "a": answer("billing", confidence: 0.99),
                    "c": answer("returns", confidence: 0.99),
                ],
                quality: .calibrated
            )
        )
        let cascade = CascadeModel(first: first, then: second, escalateBelow: 0.7)

        let report = try await cascade.decideWithReport(Self.request)

        #expect(report.escalated == ["a", "c"])
        #expect(second.requests.first?.questionnaire.specs.map(\.id) == ["a", "c"])
    }

    @Test("A question the first model skipped escalates")
    func missingAnswerEscalates() async throws {
        let first = FakeModel(
            answers: Answers(
                records: [
                    "a": answer("returns", confidence: 0.95),
                    "c": answer("billing", confidence: 0.95),
                ],
                quality: .calibrated
            )
        )
        let second = FakeModel(
            answers: Answers(records: ["b": answer("returns", confidence: 0.9)], quality: .calibrated)
        )
        let cascade = CascadeModel(first: first, then: second, escalateBelow: 0.7)

        let report = try await cascade.decideWithReport(Self.request)

        #expect(report.escalated == ["b"])
        #expect(report.response.answers.records.keys.sorted() == ["a", "b", "c"])
    }

    @Test("The identity names both models and the bar")
    func identity() {
        let empty = ModelResponse(answers: Answers(quality: .pointEstimate))
        let cascade = CascadeModel(
            first: FakeModel(
                identity: DecisionModelIdentity(provider: "apple", name: "on-device")
            ) { _ in empty },
            then: FakeModel(
                identity: DecisionModelIdentity(provider: "typesafe", name: "jev-latest")
            ) { _ in empty },
            escalateBelow: 0.7
        )

        #expect(cascade.identity.provider == "cascade")
        #expect(cascade.identity.name == "apple/on-device→typesafe/jev-latest@0.7")
    }

    @Test("Two bars over one cache do not share answers")
    func thresholdSeparatesCacheEntries() async throws {
        let first = unsureAboutB()
        let second = FakeModel(
            answers: Answers(records: ["b": answer("returns", confidence: 0.99)], quality: .calibrated)
        )
        let cache = InMemoryDecisionCache()
        let strict = CachedModel(
            CascadeModel(first: first, then: second, escalateBelow: 0.9),
            storage: cache
        )
        let loose = CachedModel(
            CascadeModel(first: first, then: second, escalateBelow: 0.1),
            storage: cache
        )

        _ = try await strict.decide(Self.request)
        _ = try await loose.decide(Self.request)
        _ = try await strict.decide(Self.request)

        #expect(first.callCount == 2)
        #expect(await cache.count == 2)
    }

    @Test("The capabilities are the intersection")
    func capabilitiesIntersect() {
        let near = DecisionModelCapabilities(
            probabilityQuality: .calibrated,
            structuredCriteria: true,
            structuredInstructions: false,
            maximumOptionsPerChoice: 255,
            maximumLevelsPerRating: 10,
            maximumQuestionsPerRequest: nil,
            contextTokens: 64_000,
            supportsRepeatedSamples: true
        )
        let far = DecisionModelCapabilities(
            probabilityQuality: .sampled(count: 4),
            structuredCriteria: true,
            structuredInstructions: true,
            maximumOptionsPerChoice: 20,
            maximumLevelsPerRating: 5,
            maximumQuestionsPerRequest: 8,
            contextTokens: nil,
            supportsRepeatedSamples: false
        )
        let cascade = CascadeModel(
            first: FakeModel(answers: Answers(quality: .calibrated), capabilities: near),
            then: FakeModel(answers: Answers(quality: .calibrated), capabilities: far),
            escalateBelow: 0.7
        )

        let merged = cascade.capabilities
        #expect(merged.probabilityQuality == .sampled(count: 4))
        #expect(merged.structuredCriteria)
        #expect(!merged.structuredInstructions)
        #expect(merged.maximumOptionsPerChoice == 20)
        #expect(merged.maximumLevelsPerRating == 5)
        #expect(merged.maximumQuestionsPerRequest == 8)
        #expect(merged.contextTokens == 64_000)
        #expect(!merged.supportsRepeatedSamples)
    }

    @Test("One unavailable model makes the cascade unavailable")
    func availability() async {
        let ready = FakeModel(answers: Answers(quality: .pointEstimate))
        let offline = FakeModel(
            answers: Answers(quality: .pointEstimate),
            availability: .unavailable(.offline)
        )
        let waiting = FakeModel(
            answers: Answers(quality: .pointEstimate),
            availability: .unavailable(.modelNotReady)
        )

        guard case .available = await CascadeModel(
            first: ready, then: ready, escalateBelow: 0.7
        ).availability else {
            Issue.record("Two ready models make a ready cascade.")
            return
        }
        guard case .unavailable(.offline) = await CascadeModel(
            first: offline, then: waiting, escalateBelow: 0.7
        ).availability else {
            Issue.record("The first reason wins.")
            return
        }
        guard case .unavailable(.modelNotReady) = await CascadeModel(
            first: ready, then: waiting, escalateBelow: 0.7
        ).availability else {
            Issue.record("The second model's reason reaches the caller.")
            return
        }
    }

    @Test("prewarm reaches both models")
    func prewarmForwards() async {
        let near = PrewarmSpy()
        let far = PrewarmSpy()

        await CascadeModel(first: near, then: far, escalateBelow: 0.7).prewarm()

        #expect(near.prewarmCount == 1)
        #expect(far.prewarmCount == 1)
    }
}

extension CascadeModelTests {
    @Test("A first answer that leaves out an option gates on the whole scale")
    func firstAnswerIsResolvedBeforeTheBar() async throws {
        // 0.7/0.3 over three options is 0.44 by the section 6.1 formula. The
        // bare record reads the scale as two options and gives 0.12.
        let thin = AnswerRecord.choice(
            reported: "returns", probabilities: ["returns": 0.7, "shipping": 0.3], confidence: nil
        )
        let first = FakeModel(
            answers: Answers(
                records: [
                    "a": thin,
                    "b": answer("shipping", confidence: 0.9),
                    "c": answer("billing", confidence: 0.9),
                ],
                quality: .calibrated
            )
        )
        let second = FakeModel(answers: Answers(quality: .pointEstimate))
        let cascade = CascadeModel(first: first, then: second, escalateBelow: 0.3)

        let report = try await cascade.decideWithReport(Self.request)

        #expect(isClose(thin.confidence, 0.12))
        #expect(report.escalated.isEmpty)
        #expect(second.callCount == 0)
        #expect(
            report.response.answers.records["a"] == .choice(
                reported: "returns",
                probabilities: ["returns": 0.7, "shipping": 0.3, "billing": 0],
                confidence: nil
            )
        )
    }

    @Test("A malformed first answer throws before the second model is asked")
    func malformedFirstAnswerThrows() async {
        let first = FakeModel(
            answers: Answers(
                records: [
                    "a": .choice(reported: "legal", probabilities: ["legal": 1], confidence: nil),
                    // Weak, so an escalation is pending when the bad answer throws.
                    "b": answer("shipping", confidence: 0.1),
                    "c": answer("billing", confidence: 0.9),
                ],
                quality: .calibrated
            )
        )
        let second = FakeModel(answers: Answers(quality: .pointEstimate))
        let cascade = CascadeModel(first: first, then: second, escalateBelow: 0.7)

        let error = await #expect(throws: DecisionError.self) {
            _ = try await cascade.decide(Self.request)
        }

        guard case .malformedResponse(let reason) = error else {
            Issue.record("Expected malformedResponse, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("Question a has no option named legal"))
        #expect(second.callCount == 0)
    }

    @Test("The second model's answers are resolved too")
    func secondAnswersAreResolved() async throws {
        let second = FakeModel(
            answers: Answers(
                records: [
                    "b": .choice(reported: "returns", probabilities: ["returns": 1], confidence: nil)
                ],
                quality: .calibrated
            )
        )
        let cascade = CascadeModel(first: unsureAboutB(), then: second, escalateBelow: 0.7)

        let response = try await cascade.decide(Self.request)

        #expect(
            response.answers.records["b"] == .choice(
                reported: "returns",
                probabilities: ["returns": 1, "shipping": 0, "billing": 0],
                confidence: nil
            )
        )
    }
}

extension CascadeModelTests {
    static let severityRequest = DecisionRequest(
        state: .text("The blender arrived broken."),
        questionnaire: Questionnaire { Rate<Severity>("severity", "How severe is the issue?") }
    )

    @Test("A first rating that leaves out the top level gates on the whole scale")
    func firstRatingIsResolvedBeforeTheBar() async throws {
        // 0.7/0.3 over three levels is 0.54 by the section 6.1 formula. The
        // bare record reads the scale as two levels and gives 0.08.
        let thin = AnswerRecord.rating(
            score: 0.3, probabilities: [0: 0.7, 1: 0.3], confidence: nil
        )
        let first = FakeModel(answers: Answers(records: ["severity": thin], quality: .calibrated))
        let second = FakeModel(answers: Answers(quality: .pointEstimate))
        let cascade = CascadeModel(first: first, then: second, escalateBelow: 0.5)

        let report = try await cascade.decideWithReport(Self.severityRequest)

        #expect(isClose(thin.confidence, 0.08))
        #expect(report.escalated.isEmpty)
        #expect(second.callCount == 0)
        #expect(
            report.response.answers.records["severity"]
                == .rating(score: 0.3, probabilities: [0: 0.7, 1: 0.3, 2: 0], confidence: nil)
        )
    }

    @Test("A malformed second answer throws too")
    func malformedSecondAnswerThrows() async {
        let second = FakeModel(
            answers: Answers(
                records: ["b": .choice(reported: "legal", probabilities: ["legal": 1], confidence: nil)],
                quality: .calibrated
            )
        )
        let cascade = CascadeModel(first: unsureAboutB(), then: second, escalateBelow: 0.7)

        let error = await #expect(throws: DecisionError.self) {
            _ = try await cascade.decide(Self.request)
        }

        guard case .malformedResponse(let reason) = error else {
            Issue.record("Expected malformedResponse, got \(String(describing: error))")
            return
        }
        #expect(reason.contains("Question b has no option named legal"))
    }
}
