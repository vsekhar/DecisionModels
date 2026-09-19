import Testing

@testable import DecisionModels

@Suite("Confidence math")
struct ConfidenceMathTests {
    @Test("A rating over three levels reproduces the published example")
    func ratingMatchesPublishedExample() throws {
        let probabilities = [0: 0.0, 1: 0.7, 2: 0.3]
        #expect(isClose(ConfidenceMath.expectedLevel(probabilities), 1.3))
        #expect(isClose(ConfidenceMath.ratingConfidence(probabilities, levelCount: 3), 0.54))

        let record = AnswerRecord.rating(score: 1.3, probabilities: probabilities, confidence: nil)
        #expect(isClose(record.confidence, 0.54))

        let rating: Rating<Severity> = try AnswerReader.rating(
            record,
            id: "severity",
            quality: .calibrated
        )
        #expect(isClose(rating.score, 1.3))
        #expect(isClose(rating.confidence, 0.54))
        #expect(rating.value == .degraded)
        #expect(isClose(rating.normalized, 0.65))
    }

    @Test("A record that names only the levels it saw infers the scale")
    func ratingInfersLevelCount() {
        let record = AnswerRecord.rating(
            score: 1.3,
            probabilities: [1: 0.7, 2: 0.3],
            confidence: nil
        )
        #expect(ConfidenceMath.inferredLevelCount([1: 0.7, 2: 0.3]) == 3)
        #expect(isClose(record.confidence, 0.54))
    }

    @Test("A uniform choice has no confidence", arguments: [2, 3, 5, 255])
    func uniformChoiceIsZero(count: Int) {
        let share = 1 / Double(count)
        let probabilities = Array(repeating: share, count: count)
        #expect(isClose(
            ConfidenceMath.choiceConfidence(probabilities, optionCount: count),
            0,
            within: 1e-9
        ))
    }

    @Test("A one-hot choice is fully confident")
    func oneHotChoiceIsOne() {
        #expect(isClose(
            ConfidenceMath.choiceConfidence([1, 0, 0], optionCount: 3),
            1,
            within: 1e-9
        ))
        let record = AnswerRecord.choice(
            reported: "returns",
            probabilities: ["returns": 1, "shipping": 0, "billing": 0],
            confidence: nil
        )
        #expect(isClose(record.confidence, 1, within: 1e-9))
    }

    @Test("One option or one level means full confidence")
    func singleOutcomeIsOne() {
        #expect(ConfidenceMath.choiceConfidence([1], optionCount: 1) == 1)
        #expect(ConfidenceMath.ratingConfidence([0: 1], levelCount: 1) == 1)
        #expect(Choice(certain: Team.billing).confidence == 1)
        #expect(Rating(certain: SingleLevel.only).confidence == 1)
    }

    @Test("A verdict reads its confidence off the probability")
    func verdictConfidence() {
        #expect(isClose(Verdict(probability: 0.87).confidence, 0.74))
        #expect(isClose(Verdict(probability: 0.13).confidence, 0.74))
        #expect(isClose(Verdict(probability: 0.5).confidence, 0, within: 1e-9))
        #expect(isClose(Verdict(certain: true).confidence, 1, within: 1e-9))
        #expect(isClose(AnswerRecord.verdict(probability: 0.87).confidence, 0.74))
    }

    @Test("A reported confidence wins over the formula")
    func reportedConfidenceWins() throws {
        let choiceRecord = AnswerRecord.choice(
            reported: "returns",
            probabilities: ["returns": 1, "shipping": 0, "billing": 0],
            confidence: 0.42
        )
        #expect(choiceRecord.confidence == 0.42)
        let choice = try AnswerReader.choice(
            choiceRecord,
            id: "team",
            options: Array(Team.allCases),
            quality: .calibrated
        )
        #expect(choice.confidence == 0.42)
        #expect(choice.reportedConfidence == 0.42)

        let ratingRecord = AnswerRecord.rating(
            score: 1.3,
            probabilities: [0: 0, 1: 0.7, 2: 0.3],
            confidence: 0.9
        )
        #expect(ratingRecord.confidence == 0.9)
        let rating: Rating<Severity> = try AnswerReader.rating(
            ratingRecord,
            id: "severity",
            quality: .calibrated
        )
        #expect(rating.confidence == 0.9)
        #expect(rating.reportedConfidence == 0.9)
    }

    @Test("Answers that say nothing have no confidence")
    func uncertainAnswers() {
        #expect(isClose(Choice<Team>.uncertain.confidence, 0, within: 1e-9))
        #expect(Choice<Team>.uncertain.value(ifAtLeast: 0.1) == nil)
        #expect(Rating<Severity>.uncertain.confidence == 0)
        #expect(Rating<Severity>.uncertain.value(ifAtLeast: 0.1) == nil)
        #expect(Verdict.uncertain.confidence == 0)
        #expect(isClose(Verdict.uncertain.probability, 0.5))
    }
}
