import Foundation
import Testing

@testable import DecisionModels

@Suite("Distribution and quality")
struct DistributionTests {
    @Test("A distribution ranks its outcomes")
    func rankingAndArgmax() {
        let distribution = Distribution(
            probabilities: [Team.returns: 0.2, .shipping: 0.5, .billing: 0.3],
            quality: .calibrated
        )
        #expect(distribution.mostLikely == .shipping)
        #expect(distribution.ranked.map(\.0) == [.shipping, .billing, .returns])
        #expect(distribution.ranked.map(\.1) == [0.5, 0.3, 0.2])
    }

    @Test("Ties rank in a stable order")
    func tiesAreStable() {
        let distribution = Distribution(
            probabilities: [Team.returns: 0.5, .shipping: 0.5, .billing: 0],
            quality: .calibrated
        )
        #expect(distribution.ranked.map(\.0) == [.returns, .shipping, .billing])
        #expect(distribution.mostLikely == .returns)
    }

    @Test("Entropy comes back in nats")
    func entropyInNats() {
        let even = Distribution(
            probabilities: [Team.returns: 0.5, .shipping: 0.5],
            quality: .calibrated
        )
        #expect(isClose(even.entropy, log(2.0), within: 1e-9))

        let sure = Distribution(
            probabilities: [Team.returns: 1, .shipping: 0],
            quality: .calibrated
        )
        #expect(sure.entropy == 0)
    }

    @Test("Quality has an order")
    func qualityOrder() {
        #expect(ProbabilityQuality.pointEstimate < .sampled(count: 1))
        #expect(ProbabilityQuality.sampled(count: 1) < .sampled(count: 5))
        #expect(ProbabilityQuality.sampled(count: .max) < .calibrated)
        #expect(
            min(ProbabilityQuality.calibrated, .sampled(count: 3), .pointEstimate)
                == .pointEstimate
        )
    }
}
