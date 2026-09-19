import Testing

@testable import DecisionModels

@Suite("Composite scores")
struct CompositeScoreTests {
    /// A rating on the three-level `Severity` scale. Its `normalized` value
    /// is `score / 2`.
    func severity(score: Double, confidence: Double) -> Rating<Severity> {
        Rating(
            distribution: Distribution(
                probabilities: [Severity.cosmetic: 0, .degraded: 1, .blocking: 0],
                quality: .calibrated
            ),
            score: score,
            reportedConfidence: confidence
        )
    }

    /// Normalized 0.75, confidence 0.9.
    var regression: Rating<Severity> { severity(score: 1.5, confidence: 0.9) }

    /// Normalized 0.25, confidence 0.6.
    var reach: Rating<Severity> { severity(score: 0.5, confidence: 0.6) }

    @Test("Two ratings sum to the hand-computed value")
    func handComputedValue() {
        #expect(isClose(regression.normalized, 0.75, within: 1e-12))
        #expect(isClose(reach.normalized, 0.25, within: 1e-12))

        let score = CompositeScore {
            Weighted(0.4, "regression", regression)
            Weighted(0.6, "reach", reach)
        }

        // 0.4 * 0.75 + 0.6 * 0.25 = 0.3 + 0.15 = 0.45
        #expect(isClose(score.value, 0.4 * 0.75 + 0.6 * 0.25, within: 1e-12))
        #expect(isClose(score.value, 0.45, within: 1e-12))
    }

    @Test("Weights scale to sum to one")
    func weightsScaleToOne() {
        let score = CompositeScore {
            Weighted(2, "regression", regression)
            Weighted(3, "reach", reach)
        }

        // 2 and 3 scale to 0.4 and 0.6, so the value does not move.
        #expect(isClose(score.value, 0.45, within: 1e-12))
        #expect(score.terms[0].weight == 2)
        #expect(score.terms[1].weight == 3)
        #expect(isClose(score.terms[0].normalizedWeight, 0.4, within: 1e-12))
        #expect(isClose(score.terms[1].normalizedWeight, 0.6, within: 1e-12))
    }

    @Test("The weakest term sets the confidence")
    func minimumConfidence() {
        let score = CompositeScore {
            Weighted(0.4, "regression", regression)
            Weighted(0.6, "reach", reach)
        }
        #expect(regression.confidence == 0.9)
        #expect(reach.confidence == 0.6)
        #expect(score.minimumConfidence == 0.6)

        // No terms, no confidence.
        #expect(CompositeScore([]).minimumConfidence == 0)
        #expect(CompositeScore([]).value == 0)
    }

    @Test("Every term reports what it added")
    func termsReportContributions() {
        let score = CompositeScore {
            Weighted(0.4, "regression", regression)
            Weighted(0.6, "reach", reach)
        }

        #expect(score.terms.count == 2)
        #expect(score.terms[0].name == "regression")
        #expect(isClose(score.terms[0].normalized, 0.75, within: 1e-12))
        #expect(isClose(score.terms[0].contribution, 0.3, within: 1e-12))
        #expect(score.terms[1].name == "reach")
        #expect(isClose(score.terms[1].normalized, 0.25, within: 1e-12))
        #expect(isClose(score.terms[1].contribution, 0.15, within: 1e-12))

        let sum = score.terms.reduce(0) { $0 + $1.contribution }
        #expect(sum == score.value)
    }

    @Test("A verdict term uses its probability")
    func verdictTerm() {
        let breach = Verdict(probability: 0.8)
        let score = CompositeScore {
            Weighted(1, "regression", regression)
            Weighted(1, "breach", breach)
        }

        // (0.75 + 0.8) / 2 = 0.775
        #expect(isClose(score.value, 0.5 * 0.75 + 0.5 * 0.8, within: 1e-12))
        #expect(isClose(score.value, 0.775, within: 1e-12))
        #expect(isClose(score.terms[1].normalized, 0.8, within: 1e-12))
        // Verdict confidence is abs(2p - 1) = 0.6, the lowest here.
        #expect(isClose(score.minimumConfidence, 0.6, within: 1e-12))
    }

    /// Drops the second term when the caller asks for one measure only.
    func score(withReach: Bool) -> CompositeScore {
        CompositeScore {
            Weighted(0.4, "regression", regression)
            if withReach {
                Weighted(0.6, "reach", reach)
            }
        }
    }

    @Test("The builder takes a conditional term")
    func conditionalTerm() {
        #expect(score(withReach: true).terms.count == 2)
        #expect(isClose(score(withReach: true).value, 0.45, within: 1e-12))

        // The one term left takes the whole weight.
        let alone = score(withReach: false)
        #expect(alone.terms.count == 1)
        #expect(alone.terms[0].normalizedWeight == 1)
        #expect(isClose(alone.value, 0.75, within: 1e-12))
    }

    @Test("Weights that are all zero score zero")
    func zeroWeights() {
        let score = CompositeScore {
            Weighted(0, "regression", regression)
            Weighted(0, "reach", reach)
        }

        #expect(score.value == 0)
        #expect(score.terms.count == 2)
        #expect(score.terms[0].normalizedWeight == 0)
        #expect(score.terms[1].normalizedWeight == 0)
        #expect(score.terms[0].contribution == 0)
        #expect(score.minimumConfidence == 0.6)
    }

    @Test("A score outside the scale clamps into 0...1")
    func outOfRangeScoreClamps() {
        // The reader rejects these; a hand-built rating can still carry one.
        let high = severity(score: 100, confidence: 0.9)
        let low = severity(score: -7, confidence: 0.9)
        #expect(high.normalized == 50)

        let top = CompositeScore { Weighted(1, "high", high) }
        #expect(top.terms[0].normalized == 1)
        #expect(top.value == 1)

        let bottom = CompositeScore { Weighted(1, "low", low) }
        #expect(bottom.terms[0].normalized == 0)
        #expect(bottom.value == 0)
    }

    @Test("A score that is not a number becomes zero")
    func nanScoreBecomesZero() {
        let broken = severity(score: .nan, confidence: .nan)
        let score = CompositeScore { Weighted(1, "broken", broken) }
        #expect(score.terms[0].normalized == 0)
        #expect(score.terms[0].confidence == 0)
        #expect(score.value == 0)
        #expect(score.minimumConfidence == 0)
    }

    @Test("A negative weight is a programmer error")
    func negativeWeightTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = CompositeScore.Term(name: "x", weight: -1, normalized: 0.5, confidence: 0.5)
        }
    }

    @Test("A weight that is not a number is a programmer error")
    func nanWeightTraps() async {
        await #expect(processExitsWith: .failure) {
            _ = CompositeScore.Term(name: "x", weight: .nan, normalized: 0.5, confidence: 0.5)
        }
    }

    @Test("Weights that overflow give zero shares, not a trap")
    func overflowingWeights() {
        let score = CompositeScore {
            Weighted(1e308, "regression", regression)
            Weighted(1e308, "reach", reach)
        }
        #expect(score.value == 0)
        #expect(score.terms[0].normalizedWeight == 0)
    }

    @Test("The builder takes loops, else branches, and arrays")
    func builderShapes() {
        let names = ["a", "b", "c"]
        let looped = CompositeScore {
            for name in names {
                Weighted(1, name, regression)
            }
        }
        #expect(looped.terms.map(\.name) == names)
        #expect(isClose(looped.value, 0.75, within: 1e-12))

        func pick(_ first: Bool) -> CompositeScore {
            CompositeScore {
                if first {
                    Weighted(1, "regression", regression)
                } else {
                    Weighted(1, "reach", reach)
                }
            }
        }
        #expect(pick(true).terms[0].name == "regression")
        #expect(pick(false).terms[0].name == "reach")

        let literal = CompositeScore {
            [Weighted(1, "regression", regression), Weighted(1, "reach", reach)]
        }
        #expect(literal.terms.count == 2)
        #expect(isClose(literal.value, 0.5, within: 1e-12))
    }
}
