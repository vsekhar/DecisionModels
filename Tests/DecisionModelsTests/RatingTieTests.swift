import Testing

@testable import DecisionModels

@Suite("Rating ties")
struct RatingTieTests {
    /// A scale is ordered, so a tie for the highest probability has to
    /// resolve by position, not by the name of the level. The tie-break of
    /// `Distribution.mostLikely` compares description text, which on
    /// `Severity` puts `blocking` first and would name the top of the scale.
    @Test("A tie for the highest probability gives the lower level")
    func tieGivesTheLowerLevel() {
        let rating = Rating(
            distribution: Distribution(
                probabilities: [Severity.cosmetic: 0, .degraded: 0.5, .blocking: 0.5],
                quality: .calibrated
            )
        )

        #expect(rating.value == .degraded)
        // The text tie-break still runs where the order does not matter.
        #expect(rating.distribution.mostLikely == .blocking)
        // The score is the expected index and does not move.
        #expect(isClose(rating.score, 1.5))
    }

    @Test("A three-way tie gives the first level")
    func uncertainGivesTheFirstLevel() {
        #expect(Rating<Severity>.uncertain.value == .cosmetic)
        #expect(Severity.levels.first == .cosmetic)
    }

    @Test("A clear winner is still the winner")
    func noTie() {
        let rating = Rating(
            distribution: Distribution(
                probabilities: [Severity.cosmetic: 0.1, .degraded: 0.2, .blocking: 0.7],
                quality: .calibrated
            )
        )
        #expect(rating.value == .blocking)
    }
}
