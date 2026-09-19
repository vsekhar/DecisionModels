import DecisionModelsTesting
import Testing

@Suite("Calibration")
struct CalibrationTests {
    @Test("A one-hot prediction on the label scores zero")
    func perfectBrier() {
        #expect(
            Calibration.brierScore(
                predicted: ["returns": 1, "shipping": 0, "billing": 0],
                expected: "returns"
            ) == 0
        )
    }

    @Test("A one-hot prediction on the wrong outcome scores two")
    func worstBrier() {
        // (1 - 0)^2 + (0 - 1)^2 = 2.
        #expect(
            isClose(
                Calibration.brierScore(
                    predicted: ["returns": 1, "shipping": 0],
                    expected: "shipping"
                ),
                2,
                within: 1e-12
            )
        )
    }

    @Test("A spread prediction scores the sum of the squared gaps")
    func spreadBrier() {
        // (0.3 - 1)^2 + (0.6 - 0)^2 + (0.1 - 0)^2 = 0.49 + 0.36 + 0.01 = 0.86.
        let score = Calibration.brierScore(
            predicted: ["returns": 0.3, "shipping": 0.6, "billing": 0.1],
            expected: "returns"
        )
        #expect(isClose(score, 0.86, within: 1e-9))
    }

    @Test("A yes and no question scores the two-outcome form")
    func verdictBrier() {
        // 2 * (0.8 - 1)^2 = 0.08.
        let score = Calibration.brierScore(predicted: [true: 0.8, false: 0.2], expected: true)
        #expect(isClose(score, 0.08, within: 1e-9))
    }

    @Test("An outcome the prediction leaves out counts as zero")
    func missingOutcome() {
        // The label carries all the weight the prediction never gave it.
        let score = Calibration.brierScore(predicted: ["shipping": 1], expected: "returns")
        #expect(isClose(score, 2, within: 1e-12))
    }

    @Test("Probabilities scale to one")
    func normalize() {
        let scaled = Calibration.normalized(["a": 1.0, "b": 3.0])
        #expect(isClose(scaled["a"] ?? 0, 0.25, within: 1e-12))
        #expect(isClose(scaled["b"] ?? 0, 0.75, within: 1e-12))
        #expect(Calibration.normalized([String: Double]()).isEmpty)
        #expect(Calibration.topProbability([String: Double]()) == 0)
    }

    @Test("A tie in the argmax goes to the smaller outcome")
    func argmaxTie() {
        #expect(Calibration.mostLikely([0: 0.5, 1: 0.5, 2: 0.0]) == 0)
        #expect(Calibration.mostLikely([0: 0.1, 1: 0.7, 2: 0.2]) == 1)
        #expect(Calibration.mostLikely([Int: Double]()) == nil)
    }

    @Test("A calibrated set scores zero")
    func calibratedIsZero() {
        var samples: [(confidence: Double, correct: Bool)] = []
        for index in 0..<10 { samples.append((confidence: 0.9, correct: index < 9)) }
        for index in 0..<10 { samples.append((confidence: 0.6, correct: index < 6)) }
        #expect(isClose(Calibration.expectedCalibrationError(samples), 0, within: 0.01))
    }

    @Test("Confidence without accuracy scores the gap")
    func overconfidentIsPositive() {
        // Ten answers at 0.9 that are right half the time: |0.5 - 0.9| = 0.4.
        var samples: [(confidence: Double, correct: Bool)] = []
        for index in 0..<10 { samples.append((confidence: 0.9, correct: index < 5)) }
        #expect(isClose(Calibration.expectedCalibrationError(samples), 0.4, within: 1e-9))

        // Add ten calibrated answers at 0.6 and the error halves:
        // (10 / 20) * 0.4 + (10 / 20) * 0 = 0.2.
        for index in 0..<10 { samples.append((confidence: 0.6, correct: index < 6)) }
        #expect(isClose(Calibration.expectedCalibrationError(samples), 0.2, within: 1e-9))
    }

    @Test("An empty set has no calibration error")
    func emptyCalibration() {
        #expect(Calibration.expectedCalibrationError([]) == 0)
    }

    @Test("Bands split at the two thresholds")
    func bands() {
        // 0.95 and 0.9 act, 0.89 and 0.5 confirm, 0.49 and 0 escalate.
        let counts = Calibration.bands(
            [0.95, 0.9, 0.89, 0.5, 0.49, 0],
            escalateBelow: 0.5,
            confirmBelow: 0.9
        )
        #expect(counts.act == 2)
        #expect(counts.confirm == 2)
        #expect(counts.escalate == 2)

        let none = Calibration.bands([Double](), escalateBelow: 0.5, confirmBelow: 0.9)
        #expect(none == (act: 0, confirm: 0, escalate: 0))
    }
}
