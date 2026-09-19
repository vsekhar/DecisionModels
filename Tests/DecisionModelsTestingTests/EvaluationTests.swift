import DecisionModels
import DecisionModelsTesting
import Testing

@Suite("Evaluation")
struct EvaluationTests {
    /// Four labeled tickets. Every state is different, so a script can tell
    /// them apart.
    static let labeled: [(state: State, expected: TicketTriage)] = [
        (
            state: "The blender arrived broken.",
            expected: TicketTriage(team: .returns, severity: .blocking, requestsRefund: true)
        ),
        (
            state: "The parcel never came.",
            expected: TicketTriage(team: .shipping, severity: .degraded, requestsRefund: false)
        ),
        (
            state: "You charged me twice.",
            expected: TicketTriage(team: .billing, severity: .blocking, requestsRefund: true)
        ),
        (
            state: "The lid is scratched.",
            expected: TicketTriage(team: .returns, severity: .cosmetic, requestsRefund: false)
        ),
    ]

    /// A model that answers every ticket with the label, apart from the
    /// records `wrong` replaces.
    static func model(wrong: [State: AnswerRecord] = [:]) -> ScriptedModel {
        var script: [State: Answers] = [:]
        for example in labeled {
            var answers = example.expected.answers
            if let record = wrong[example.state] {
                answers.records["team"] = record
            }
            script[example.state] = answers
        }
        let answered = script
        return ScriptedModel { request in
            guard let answers = answered[request.state] else {
                throw DecisionError.malformedResponse("The script has no answer for this state.")
            }
            return answers
        }
    }

    @Test("A model that answers the labels scores perfectly")
    func perfectModel() async throws {
        let model = EvaluationTests.model()
        let report = try await Evaluation(models: [model])
            .run(TicketTriage.self, on: EvaluationTests.labeled)

        #expect(report.models == [model.identity])
        let scores = try #require(report[model.identity])
        #expect(scores.questions == ["team", "severity", "requestsRefund"])

        for id in scores.questions {
            let question = try #require(scores.question(id))
            #expect(question.id == id)
            #expect(question.count == 4)
            #expect(isClose(question.accuracy, 1))
            #expect(isClose(question.brierScore, 0))
            #expect(isClose(question.expectedCalibrationError, 0))
        }
        #expect(model.callCount == 4)
    }

    @Test("One wrong choice out of four gives accuracy 0.75 and a known Brier score")
    func oneWrongChoice() async throws {
        // The fourth ticket is a `returns` ticket. The model names `shipping`
        // and spreads its probabilities 0.3 / 0.6 / 0.1.
        let model = EvaluationTests.model(wrong: [
            "The lid is scratched.": .choice(
                reported: "shipping",
                probabilities: ["returns": 0.3, "shipping": 0.6, "billing": 0.1],
                confidence: nil
            )
        ])
        let report = try await Evaluation(models: [model])
            .run(TicketTriage.self, on: EvaluationTests.labeled)
        let team = try #require(report[model.identity]?.question("team"))

        // Three of four name the labeled team.
        #expect(team.count == 4)
        #expect(isClose(team.accuracy, 0.75))

        // Brier, by hand. The three right answers are one-hot on the label,
        // so each scores 0. The wrong one scores
        //   (0.3 - 1)^2 + (0.6 - 0)^2 + (0.1 - 0)^2
        // = 0.49 + 0.36 + 0.01 = 0.86.
        // The mean over four examples is 0.86 / 4 = 0.215.
        #expect(isClose(team.brierScore, 0.215, within: 1e-9))

        // The other two questions still match their labels.
        for id in ["severity", "requestsRefund"] {
            let question = try #require(report[model.identity]?.question(id))
            #expect(isClose(question.accuracy, 1))
            #expect(isClose(question.brierScore, 0))
        }
    }

    @Test("A choice bins on the probability of the option it named")
    func choiceBinsOnTheNamedOption() async throws {
        // The fourth ticket is a `returns` ticket. The model names `returns`
        // at 0.3 while `shipping` carries 0.6. The answer is right, so the
        // 0.3 bin holds one right answer and the gap is |1 - 0.3| = 0.7.
        // Binning on the highest probability, 0.6, would score a prediction
        // the model never made.
        let model = EvaluationTests.model(wrong: [
            "The lid is scratched.": .choice(
                reported: "returns",
                probabilities: ["returns": 0.3, "shipping": 0.6, "billing": 0.1],
                confidence: nil
            )
        ])
        let report = try await Evaluation(models: [model])
            .run(TicketTriage.self, on: [EvaluationTests.labeled[3]])
        let team = try #require(report[model.identity]?.question("team"))

        #expect(team.count == 1)
        #expect(isClose(team.accuracy, 1))
        #expect(isClose(team.expectedCalibrationError, 0.7, within: 1e-9))
        // Brier does not care which option was named:
        // (0.3 - 1)^2 + (0.6 - 0)^2 + (0.1 - 0)^2 = 0.86.
        #expect(isClose(team.brierScore, 0.86, within: 1e-9))
    }

    @Test("A rating that ties for the top scores as the lower level")
    func ratingTieScoresAsTheLowerLevel() async throws {
        // The label is `degraded`. The model splits its weight evenly between
        // `degraded` and `blocking`. Both sides break the tie toward the
        // lower level, so the evaluation agrees with the `severity` a call
        // site reads. `RatingTieTests` holds the call-site half.
        let state = State.text("The lid is scratched.")
        let expected = TicketTriage(team: .returns, severity: .degraded, requestsRefund: false)
        var answers = expected.answers
        answers.records["severity"] = .rating(
            score: 1.5, probabilities: [0: 0, 1: 0.5, 2: 0.5], confidence: nil
        )
        let model = ScriptedModel(answering: answers)

        let report = try await Evaluation(models: [model])
            .run(TicketTriage.self, on: [(state: state, expected: expected)])
        let severity = try #require(report[model.identity]?.question("severity"))

        #expect(isClose(severity.accuracy, 1))
        // The bin is the probability of the level the answer names, 0.5.
        #expect(isClose(severity.expectedCalibrationError, 0.5, within: 1e-9))
    }

    @Test("Two models with one identity is a programmer error")
    func duplicateIdentitiesTrap() async {
        await #expect(processExitsWith: .failure) {
            let first = ScriptedModel(answering: triageAnswers)
            let second = ScriptedModel(answering: triageAnswers)
            // Both carry the default identity, so the report would keep one.
            _ = Evaluation(models: [first, second]).models.count
        }
    }

    @Test("Two models are scored side by side")
    func twoModels() async throws {
        let good = EvaluationTests.model()
        let bad = ScriptedModel(
            answering: TicketTriage(team: .billing, severity: .cosmetic, requestsRefund: false)
                .answers,
            identity: DecisionModelIdentity(provider: "test", name: "blunt")
        )
        let report = try await Evaluation(models: [good, bad])
            .run(TicketTriage.self, on: EvaluationTests.labeled)

        #expect(report.models == [good.identity, bad.identity])
        #expect(isClose(try #require(report[good.identity]?.question("team")).accuracy, 1))
        // `billing` is the label once in four.
        #expect(isClose(try #require(report[bad.identity]?.question("team")).accuracy, 0.25))
        #expect(report[DecisionModelIdentity(provider: "test", name: "absent")] == nil)
        #expect(report[good.identity]?.question("nothing") == nil)
    }

    @Test("A calibrated set has no calibration error")
    func calibratedSetScoresZero() async throws {
        // Ten answers at probability 0.9, nine of them right; ten at 0.6, six
        // of them right. Each bin's accuracy is its own confidence, so every
        // gap is zero.
        var rows: [(probability: Double, expected: Bool)] = []
        for index in 0..<10 { rows.append((probability: 0.9, expected: index < 9)) }
        for index in 0..<10 { rows.append((probability: 0.6, expected: index < 6)) }
        let set = verdictSet(rows)

        let report = try await Evaluation(models: [set.model])
            .run(RefundCheck.self, on: set.labeled)
        let question = try #require(report[set.model.identity]?.question("requestsRefund"))

        #expect(question.count == 20)
        #expect(isClose(question.expectedCalibrationError, 0, within: 0.01))
        // Fifteen of twenty answers land on the labeled side of one half.
        #expect(isClose(question.accuracy, 0.75))
    }

    @Test("A model that is sure and wrong half the time has a known calibration error")
    func miscalibratedSetScoresPositive() async throws {
        // Ten answers at probability 0.9, five of them right; ten at 0.6, six
        // of them right.
        var rows: [(probability: Double, expected: Bool)] = []
        for index in 0..<10 { rows.append((probability: 0.9, expected: index < 5)) }
        for index in 0..<10 { rows.append((probability: 0.6, expected: index < 6)) }
        let set = verdictSet(rows)

        let report = try await Evaluation(models: [set.model])
            .run(RefundCheck.self, on: set.labeled)
        let question = try #require(report[set.model.identity]?.question("requestsRefund"))

        // Calibration error, by hand. The 0.9 answers fall in the last bin:
        // accuracy 0.5 against confidence 0.9 is a gap of 0.4 over ten of the
        // twenty answers. The 0.6 answers fall in the seventh bin with no
        // gap. So the error is (10 / 20) * 0.4 + (10 / 20) * 0 = 0.2.
        #expect(isClose(question.expectedCalibrationError, 0.2, within: 1e-9))
        #expect(isClose(question.accuracy, 0.55))

        // Brier, by hand. A right answer at 0.9 scores
        //   (0.9 - 1)^2 + (0.1 - 0)^2 = 0.02, and a wrong one
        //   (0.9 - 0)^2 + (0.1 - 1)^2 = 1.62.
        // A right answer at 0.6 scores 0.32 and a wrong one 0.72.
        // The mean is (5 * 0.02 + 5 * 1.62 + 6 * 0.32 + 4 * 0.72) / 20
        //           = (0.1 + 8.1 + 1.92 + 2.88) / 20 = 13.0 / 20 = 0.65.
        #expect(isClose(question.brierScore, 0.65, within: 1e-9))
    }

    @Test("Band counts match a hand-built set of confidences")
    func bandsCount() async throws {
        // A verdict's confidence is `abs(2p - 1)`, so these six probabilities
        // give confidences 1.0, 1.0, 0.96, 0.8, 0.6, and 0.2. Against
        // thresholds 0.5 and 0.9 that is three to act on, two to confirm, and
        // one to escalate.
        let set = verdictSet([
            (probability: 1.0, expected: true),
            (probability: 0.0, expected: false),
            (probability: 0.98, expected: true),
            (probability: 0.9, expected: true),
            (probability: 0.8, expected: true),
            (probability: 0.6, expected: true),
        ])

        let report = try await Evaluation(models: [set.model])
            .run(RefundCheck.self, on: set.labeled)
        let question = try #require(report[set.model.identity]?.question("requestsRefund"))

        #expect(question.confidences.map { ($0 * 100).rounded() } == [100, 100, 96, 80, 60, 20])
        let counts = question.bands(escalateBelow: 0.5, confirmBelow: 0.9)
        #expect(counts.act == 3)
        #expect(counts.confirm == 2)
        #expect(counts.escalate == 1)
        // Every answer lands in one band.
        #expect(counts.act + counts.confirm + counts.escalate == question.count)
        // A floor of zero acts on everything.
        #expect(question.bands(escalateBelow: 0, confirmBelow: 0).act == 6)
    }

    @Test("An empty labeled set reports nothing")
    func emptySet() async throws {
        let model = EvaluationTests.model()
        let report = try await Evaluation(models: [model]).run(TicketTriage.self, on: [])
        let team = try #require(report[model.identity]?.question("team"))

        #expect(team.count == 0)
        #expect(team.accuracy == 0)
        #expect(team.brierScore == 0)
        #expect(team.expectedCalibrationError == 0)
        #expect(model.callCount == 0)
    }

    @Test("The session options reach the model")
    func optionsReachTheModel() async throws {
        // The model answers only a request that carries both options, so the
        // run fails if either one is lost.
        let samples = ScriptedModel { request in
            guard request.samples == 3, request.metadata == ["run": "nightly"] else {
                throw DecisionError.malformedResponse("The options did not reach the model.")
            }
            return TicketTriage(team: .returns, severity: .blocking, requestsRefund: true).answers
        }
        _ = try await Evaluation(
            models: [samples],
            options: DecisionOptions(samples: 3, metadata: ["run": "nightly"])
        ).run(TicketTriage.self, on: Array(EvaluationTests.labeled.prefix(1)))

        #expect(samples.callCount == 1)
    }
}
