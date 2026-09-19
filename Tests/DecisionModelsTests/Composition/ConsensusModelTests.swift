import Synchronization
import Testing

@testable import DecisionModels

/// A fake that gives one scripted response per call, in call order.
private func scripted(_ responses: [ModelResponse]) -> FakeModel {
    let next = Mutex<Int>(0)
    return FakeModel { _ in
        let turn = next.withLock { count -> Int in
            defer { count += 1 }
            return count
        }
        return responses[min(turn, responses.count - 1)]
    }
}

/// One run that answers the `team` question.
private func run(
    _ reported: String,
    _ probabilities: [String: Double],
    quality: ProbabilityQuality = .calibrated,
    requestID: String? = nil
) -> ModelResponse {
    ModelResponse(
        answers: Answers(
            records: [
                "team": .choice(
                    reported: reported,
                    probabilities: probabilities,
                    confidence: 0.9
                )
            ],
            quality: quality
        ),
        usage: Usage(inputTokens: 3, outputTokens: 1, requests: 1),
        requestID: requestID
    )
}

/// One run with any records at all.
private func run(_ records: [String: AnswerRecord]) -> ModelResponse {
    ModelResponse(
        answers: Answers(records: records, quality: .calibrated),
        usage: Usage(inputTokens: 3, outputTokens: 1, requests: 1)
    )
}

@Suite("Consensus")
struct ConsensusModelTests {
    static let request = DecisionRequest(
        state: .text("The blender arrived broken."),
        questionnaire: Questionnaire([
            Choose("team", "Which team handles this ticket?", among: Array(Team.allCases)).spec
        ]),
        metadata: ["tenant": "acme"]
    )

    @Test("Three runs that differ average to the expected distribution")
    func averagesThreeRuns() async throws {
        let model = scripted([
            run("returns", ["returns": 1, "shipping": 0, "billing": 0], requestID: "run-1"),
            run("shipping", ["returns": 0, "shipping": 1, "billing": 0], requestID: "run-2"),
            run("returns", ["returns": 0.6, "shipping": 0.4, "billing": 0], requestID: "run-3"),
        ])
        let consensus = ConsensusModel(model, samples: 3)

        let report = try await consensus.decideWithReport(Self.request)

        #expect(model.callCount == 3)
        #expect(report.disagreements == ["team"])
        #expect(report.response.answers.quality == .sampled(count: 3))
        #expect(report.response.usage == Usage(inputTokens: 9, outputTokens: 3, requests: 3))

        let record = try #require(report.response.answers.records["team"])
        guard case .choice(let reported, let probabilities, let confidence) = record else {
            Issue.record("The merged answer is not a choice.")
            return
        }
        #expect(reported == "returns")
        #expect(confidence == nil)
        #expect(isClose(probabilities["returns"] ?? 0, 1.6 / 3, within: 1e-12))
        #expect(isClose(probabilities["shipping"] ?? 0, 1.4 / 3, within: 1e-12))
        #expect(isClose(probabilities["billing"] ?? 0, 0, within: 1e-12))
    }

    @Test("Every run asks for one draw and keeps the state and the metadata")
    func everyRunAsksOnce() async throws {
        let model = scripted([run("returns", ["returns": 1, "shipping": 0, "billing": 0])])
        let consensus = ConsensusModel(model, samples: 4)

        _ = try await consensus.decide(Self.request)

        #expect(model.callCount == 4)
        for sent in model.requests {
            #expect(sent.samples == 1)
            #expect(sent.state == Self.request.state)
            #expect(sent.metadata == ["tenant": "acme"])
            #expect(sent.questionnaire.specs.map(\.id) == ["team"])
        }
    }

    @Test("A run that names only its top option carries its full weight")
    func everyRunScalesToOne() async throws {
        let model = scripted([
            run("returns", ["returns": 0.34, "shipping": 0.33, "billing": 0.33]),
            run("shipping", ["shipping": 0.6]),
        ])

        let response = try await ConsensusModel(model, samples: 2).decide(Self.request)

        let record = try #require(response.answers.records["team"])
        guard case .choice(let reported, let probabilities, _) = record else {
            Issue.record("The merged answer is not a choice.")
            return
        }
        // The short run counts as one whole vote: (0.33 + 1) / 2.
        #expect(reported == "shipping")
        #expect(isClose(probabilities["shipping"] ?? 0, 0.665, within: 1e-12))
        #expect(isClose(probabilities["returns"] ?? 0, 0.17, within: 1e-12))
        #expect(isClose(probabilities["billing"] ?? 0, 0.165, within: 1e-12))
    }

    @Test("One draw keeps the model's own quality")
    func oneDrawAddsNothing() async throws {
        let model = scripted([
            run(
                "returns",
                ["returns": 1, "shipping": 0, "billing": 0],
                quality: .pointEstimate
            )
        ])
        let response = try await ConsensusModel(model, samples: 1).decide(Self.request)

        #expect(model.callCount == 1)
        #expect(response.answers.quality == .pointEstimate)

        // The model claims no better, so one draw claims no better either.
        let plain = FakeModel(
            answers: Answers(quality: .pointEstimate),
            capabilities: DecisionModelCapabilities(probabilityQuality: .pointEstimate)
        )
        let once = ConsensusModel(plain, samples: 1)
        #expect(once.capabilities.probabilityQuality == .pointEstimate)
        #expect(once.capabilities.supportsRepeatedSamples)
    }

    @Test("A call that asks for more draws sets the count")
    func callSetsTheCount() async throws {
        let model = scripted([
            run("returns", ["returns": 1, "shipping": 0, "billing": 0]),
            run("shipping", ["returns": 0, "shipping": 1, "billing": 0]),
            run("returns", ["returns": 0.6, "shipping": 0.4, "billing": 0]),
        ])
        let request = DecisionRequest(
            state: Self.request.state,
            questionnaire: Self.request.questionnaire,
            samples: 3
        )

        let response = try await ConsensusModel(model, samples: 1).decide(request)

        #expect(model.callCount == 3)
        for sent in model.requests { #expect(sent.samples == 1) }
        #expect(response.answers.quality == .sampled(count: 3))
    }

    @Test("A tie goes to the smallest option id")
    func tieBreak() async throws {
        let model = scripted([
            run("shipping", ["returns": 0, "shipping": 1, "billing": 0]),
            run("billing", ["returns": 0, "shipping": 0, "billing": 1]),
        ])

        let response = try await ConsensusModel(model, samples: 2).decide(Self.request)

        let record = try #require(response.answers.records["team"])
        guard case .choice(let reported, let probabilities, _) = record else {
            Issue.record("The merged answer is not a choice.")
            return
        }
        #expect(reported == "billing")
        #expect(isClose(probabilities["billing"] ?? 0, 0.5, within: 1e-12))
        #expect(isClose(probabilities["shipping"] ?? 0, 0.5, within: 1e-12))
    }

    @Test("Ratings average index by index and verdicts average the probability")
    func averagesRatingsAndVerdicts() async throws {
        let questionnaire = Questionnaire([
            Rate<Severity>("severity", "How severe is the issue?").spec,
            Verify("refund", "Does the customer ask for a refund?").spec,
        ])
        let model = scripted([
            run([
                "severity": .rating(score: 1, probabilities: [0: 0.2, 1: 0.8], confidence: 0.7),
                "refund": .verdict(probability: 0.8),
            ]),
            run([
                "severity": .rating(score: 2, probabilities: [1: 0.3, 2: 0.7], confidence: 0.6),
                "refund": .verdict(probability: 0.4),
            ]),
        ])
        let request = DecisionRequest(state: .text("broken"), questionnaire: questionnaire)

        let report = try await ConsensusModel(model, samples: 2).decideWithReport(request)

        #expect(report.disagreements == ["severity", "refund"])
        let severity = try #require(report.response.answers.records["severity"])
        guard case .rating(let score, let probabilities, let confidence) = severity else {
            Issue.record("The merged answer is not a rating.")
            return
        }
        #expect(isClose(score, 1.5, within: 1e-12))
        #expect(confidence == nil)
        #expect(isClose(probabilities[0] ?? 0, 0.1, within: 1e-12))
        #expect(isClose(probabilities[1] ?? 0, 0.55, within: 1e-12))
        #expect(isClose(probabilities[2] ?? 0, 0.35, within: 1e-12))

        let refund = try #require(report.response.answers.records["refund"])
        guard case .verdict(let probability) = refund else {
            Issue.record("The merged answer is not a verdict.")
            return
        }
        #expect(isClose(probability, 0.6, within: 1e-12))
    }

    @Test("Calibrated runs that agree stay calibrated")
    func agreementKeepsCalibration() async throws {
        let model = scripted([
            run("returns", ["returns": 0.9, "shipping": 0.1, "billing": 0]),
            run("returns", ["returns": 0.7, "shipping": 0.3, "billing": 0]),
        ])

        let report = try await ConsensusModel(model, samples: 2).decideWithReport(Self.request)

        #expect(report.disagreements.isEmpty)
        #expect(report.response.answers.quality == .calibrated)
        let record = try #require(report.response.answers.records["team"])
        guard case .choice(let reported, let probabilities, _) = record else {
            Issue.record("The merged answer is not a choice.")
            return
        }
        #expect(reported == "returns")
        #expect(isClose(probabilities["returns"] ?? 0, 0.8, within: 1e-12))
    }

    @Test("Runs that only sample stay sampled")
    func sampledRunsStaySampled() async throws {
        let model = scripted([
            run("returns", ["returns": 1, "shipping": 0, "billing": 0], quality: .pointEstimate),
            run("returns", ["returns": 1, "shipping": 0, "billing": 0], quality: .pointEstimate),
        ])

        let response = try await ConsensusModel(model, samples: 2).decide(Self.request)

        #expect(response.answers.quality == .sampled(count: 2))
    }

    @Test("The capabilities gain repetition and sampled quality")
    func capabilities() {
        let plain = FakeModel(
            answers: Answers(quality: .pointEstimate),
            capabilities: DecisionModelCapabilities(
                probabilityQuality: .pointEstimate,
                maximumOptionsPerChoice: 30,
                supportsRepeatedSamples: false
            )
        )
        let merged = ConsensusModel(plain, samples: 3).capabilities
        #expect(merged.probabilityQuality == .sampled(count: 3))
        #expect(merged.supportsRepeatedSamples)
        #expect(merged.maximumOptionsPerChoice == 30)

        let calibrated = FakeModel(answers: Answers(quality: .calibrated))
        #expect(
            ConsensusModel(calibrated, samples: 3).capabilities.probabilityQuality == .calibrated
        )
    }

    @Test("The identity names the model and the count")
    func identity() {
        let model = FakeModel(answers: Answers(quality: .calibrated))
        let consensus = ConsensusModel(model, samples: 5)

        #expect(consensus.identity.provider == "consensus")
        #expect(consensus.identity.name == "fake×5")
    }

    @Test("prewarm and availability reach the model")
    func forwards() async {
        let spy = PrewarmSpy()
        let consensus = ConsensusModel(spy, samples: 2)

        await consensus.prewarm()

        #expect(spy.prewarmCount == 1)
        guard case .available = await consensus.availability else {
            Issue.record("The model is available, so the consensus is.")
            return
        }
    }
}
