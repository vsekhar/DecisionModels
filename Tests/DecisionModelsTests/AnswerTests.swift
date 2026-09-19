import Testing

@testable import DecisionModels

@Suite("Typed answers")
struct AnswerTests {
    func team(confidence: Double) -> Choice<Team> {
        Choice(
            distribution: Distribution(
                probabilities: [.returns: 1, .shipping: 0, .billing: 0],
                quality: .calibrated
            ),
            reported: .returns,
            reportedConfidence: confidence
        )
    }

    @Test("The bands break where the thresholds say")
    func bandBoundaries() {
        #expect(team(confidence: 0.0).band(escalateBelow: 0.5, confirmBelow: 0.9) == .escalate)
        #expect(team(confidence: 0.49).band(escalateBelow: 0.5, confirmBelow: 0.9) == .escalate)
        #expect(team(confidence: 0.5).band(escalateBelow: 0.5, confirmBelow: 0.9) == .confirm)
        #expect(team(confidence: 0.89).band(escalateBelow: 0.5, confirmBelow: 0.9) == .confirm)
        #expect(team(confidence: 0.9).band(escalateBelow: 0.5, confirmBelow: 0.9) == .act)
        #expect(team(confidence: 1).band(escalateBelow: 0.5, confirmBelow: 0.9) == .act)
        #expect(Verdict(probability: 1).band(escalateBelow: 0.5, confirmBelow: 0.9) == .act)
        #expect(Verdict(probability: 0.5).band(escalateBelow: 0.5, confirmBelow: 0.9) == .escalate)
    }

    @Test("A value comes back only above the bar")
    func valueAboveTheBar() {
        #expect(team(confidence: 0.7).value(ifAtLeast: 0.7) == .returns)
        #expect(team(confidence: 0.69).value(ifAtLeast: 0.7) == nil)

        let rating = Rating(
            distribution: Distribution(
                probabilities: [Severity.cosmetic: 0, .degraded: 0.7, .blocking: 0.3],
                quality: .calibrated
            ),
            score: 1.3,
            reportedConfidence: 0.8
        )
        #expect(rating.value(ifAtLeast: 0.8) == .degraded)
        #expect(rating.value(ifAtLeast: 0.81) == nil)
    }

    @Test("A choice prefers the option the model named")
    func choicePrefersTheReportedOption() {
        let distribution = Distribution(
            probabilities: [Team.returns: 0.4, .shipping: 0.45, .billing: 0.15],
            quality: .calibrated
        )
        let named = Choice(distribution: distribution, reported: .returns)
        #expect(named.value == .returns)
        #expect(named.distribution.mostLikely == .shipping)

        let silent = Choice(distribution: distribution)
        #expect(silent.value == .shipping)
        #expect(silent.reported == nil)
    }

    @Test("A choice reads one option at a time")
    func choiceSubscript() {
        let choice = Choice(certain: Team.billing)
        #expect(choice[.billing] == 1)
        #expect(choice[.returns] == 0)
        #expect(choice.value == .billing)
        #expect(choice.quality == .pointEstimate)
    }

    @Test("A rating keeps the score and the most likely level apart")
    func ratingScoreAndValue() {
        let rating = Rating(
            distribution: Distribution(
                probabilities: [Severity.cosmetic: 0.45, .degraded: 0.1, .blocking: 0.45],
                quality: .calibrated
            )
        )
        #expect(rating.value == .cosmetic)  // a tie goes to the lower level
        #expect(isClose(rating.score, 1.0))
        #expect(isClose(rating.normalized, 0.5))
        #expect(rating.legend.count == 3)
        #expect(rating.legend[.cosmetic] == Severity.cosmetic.criterion)
    }

    @Test("A sure answer is sure")
    func certainAnswers() {
        #expect(Rating(certain: Severity.blocking).score == 2)
        #expect(Rating(certain: Severity.blocking).normalized == 1)
        #expect(Rating(certain: Severity.blocking).confidence == 1)
        #expect(Choice(certain: Team.returns).confidence == 1)
        #expect(Verdict(certain: false).value == false)
        #expect(Verdict(certain: false).probability == 0)
    }

    @Test("Every answer gives back its record")
    func answersGiveBackTheirRecords() {
        let choice = Choice(
            distribution: Distribution(
                probabilities: [Team.returns: 0.9, .shipping: 0.1],
                quality: .calibrated
            ),
            reported: .returns,
            reportedConfidence: 0.88
        )
        #expect(choice.record == .choice(
            reported: "returns",
            probabilities: ["returns": 0.9, "shipping": 0.1],
            confidence: 0.88
        ))

        let rating = Rating(
            distribution: Distribution(
                probabilities: [Severity.cosmetic: 0, .degraded: 0.7, .blocking: 0.3],
                quality: .calibrated
            ),
            score: 1.3
        )
        #expect(rating.record == .rating(
            score: 1.3,
            probabilities: [0: 0, 1: 0.7, 2: 0.3],
            confidence: nil
        ))

        #expect(Verdict(probability: 0.87).record == .verdict(probability: 0.87))
    }
}
