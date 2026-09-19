import Testing
@testable import DecisionModels

/// Provider input that must throw, never trap or pass.
@Suite("Malformed input")
struct MalformedInputTests {
    let answers = Answers(records: [:], quality: .calibrated)

    @Test("Duplicate option ids in a run-time list throw")
    func duplicateOptionIDs() {
        let twice = [
            Skill(id: "refund", summary: "Give money back"),
            Skill(id: "refund", summary: "Refund, version two"),
        ]
        let record = AnswerRecord.choice(
            reported: "refund", probabilities: ["refund": 1], confidence: nil
        )
        let error = #expect(throws: DecisionError.self) {
            try AnswerReader.choice(record, id: "skill", options: twice, quality: .calibrated)
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "skill")
    }

    @Test("A negative probability throws instead of producing NaN")
    func negativeProbability() {
        let record = AnswerRecord.rating(score: 1, probabilities: [0: -1, 1: 2], confidence: nil)
        let error = #expect(throws: DecisionError.self) {
            try AnswerReader.rating(record, id: "severity", quality: .calibrated) as Rating<Severity>
        }
        guard case .malformedResponse = error else {
            Issue.record("Expected malformedResponse, got \(String(describing: error))")
            return
        }
    }

    @Test("A probability that is not a number throws")
    func nanProbability() {
        let record = AnswerRecord.choice(
            reported: "returns", probabilities: ["returns": .nan, "billing": 1], confidence: nil
        )
        #expect(throws: DecisionError.self) {
            try AnswerReader.choice(
                record, id: "team", options: Array(Team.allCases), quality: .calibrated
            )
        }
    }

    @Test("Empty probabilities throw for choice and rating")
    func emptyProbabilities() {
        let choice = AnswerRecord.choice(reported: "returns", probabilities: [:], confidence: nil)
        #expect(throws: DecisionError.self) {
            try AnswerReader.choice(
                choice, id: "team", options: Array(Team.allCases), quality: .calibrated
            )
        }
        let rating = AnswerRecord.rating(score: 0, probabilities: [:], confidence: nil)
        #expect(throws: DecisionError.self) {
            try AnswerReader.rating(rating, id: "severity", quality: .calibrated) as Rating<Severity>
        }
    }

    @Test("Probabilities that sum to zero throw")
    func zeroSum() {
        let record = AnswerRecord.choice(
            reported: "returns", probabilities: ["returns": 0, "billing": 0], confidence: nil
        )
        #expect(throws: DecisionError.self) {
            try AnswerReader.choice(
                record, id: "team", options: Array(Team.allCases), quality: .calibrated
            )
        }
    }

    @Test("A reported confidence outside 0...1 throws")
    func reportedConfidenceOutOfRange() {
        let record = AnswerRecord.choice(
            reported: "returns", probabilities: ["returns": 1], confidence: 7.5
        )
        #expect(throws: DecisionError.self) {
            try AnswerReader.choice(
                record, id: "team", options: Array(Team.allCases), quality: .calibrated
            )
        }
    }

    @Test("A verdict probability outside 0...1 throws")
    func verdictOutOfRange() {
        #expect(throws: DecisionError.self) {
            try AnswerReader.verdict(.verdict(probability: 1.5), id: "refund", quality: .calibrated)
        }
        #expect(throws: DecisionError.self) {
            try AnswerReader.verdict(.verdict(probability: .nan), id: "refund", quality: .calibrated)
        }
    }

    @Test("A record with no probabilities has confidence zero, not one")
    func emptyRecordConfidence() {
        let choice = AnswerRecord.choice(reported: "x", probabilities: [:], confidence: nil)
        #expect(choice.confidence == 0)
        let rating = AnswerRecord.rating(score: 0, probabilities: [:], confidence: nil)
        #expect(rating.confidence == 0)
    }

    @Test("A record with a negative probability never bands as act")
    func negativeRecordBands() {
        let record = AnswerRecord.rating(score: 1, probabilities: [0: -1, 1: 2], confidence: nil)
        #expect(record.confidence.isFinite)
        #expect(record.confidence >= 0 && record.confidence <= 1)
    }

    @Test("A rating score outside the scale throws")
    func scoreOutOfRange() {
        for score in [100.0, -7.0, .nan] {
            let record = AnswerRecord.rating(score: score, probabilities: [1: 1], confidence: nil)
            #expect(throws: DecisionError.self) {
                try AnswerReader.rating(record, id: "severity", quality: .calibrated) as Rating<Severity>
            }
        }
        // The ends of the scale are fine.
        let ends = [0.0, 2.0].map {
            AnswerRecord.rating(score: $0, probabilities: [1: 1], confidence: nil)
        }
        for record in ends {
            #expect(throws: Never.self) {
                try AnswerReader.rating(record, id: "severity", quality: .calibrated) as Rating<Severity>
            }
        }
    }
}
