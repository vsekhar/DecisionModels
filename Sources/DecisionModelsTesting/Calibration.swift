import DecisionModels

/// The scoring rules an evaluation reports.
///
/// Every function here is pure. A test can check the arithmetic on its own,
/// with no model and no labeled set.
public enum Calibration {
    /// Scales probabilities so that they sum to one.
    ///
    /// A map that is empty, or that sums to zero or less, comes back
    /// unchanged.
    public static func normalized<Outcome: Hashable>(
        _ probabilities: [Outcome: Double]
    ) -> [Outcome: Double] {
        let total = probabilities.values.reduce(0, +)
        guard total > 0, abs(total - 1) > 1e-9 else { return probabilities }
        return probabilities.mapValues { $0 / total }
    }

    /// The Brier score of one prediction: the sum over outcomes of `(p - y)²`.
    ///
    /// `y` is one for the outcome that happened and zero for every other one.
    /// An outcome the prediction leaves out counts as zero. A yes and no
    /// question has two outcomes, so it scores `2 * (p - y)²`.
    ///
    /// Zero is perfect. A prediction that puts all its weight on one wrong
    /// outcome scores two, which is the worst score a map that sums to one
    /// can reach. A map that names neither the label nor anything else, and
    /// so sums to zero, is not scaled and can score more.
    public static func brierScore<Outcome: Hashable>(
        predicted: [Outcome: Double],
        expected: Outcome
    ) -> Double {
        let scaled = normalized(predicted)
        var total = 0.0
        for (outcome, probability) in scaled {
            let label = outcome == expected ? 1.0 : 0.0
            total += (probability - label) * (probability - label)
        }
        if scaled[expected] == nil { total += 1 }
        return total
    }

    /// The most likely outcome, or `nil` when there is none.
    ///
    /// A tie goes to the smaller outcome, so the answer does not depend on
    /// the order a dictionary happens to have.
    public static func mostLikely<Outcome: Hashable & Comparable>(
        _ probabilities: [Outcome: Double]
    ) -> Outcome? {
        probabilities.max { left, right in
            left.value == right.value ? left.key > right.key : left.value < right.value
        }?.key
    }

    /// The probability of the most likely outcome, after scaling. Zero when
    /// there are no outcomes.
    public static func topProbability<Outcome: Hashable>(
        _ probabilities: [Outcome: Double]
    ) -> Double {
        normalized(probabilities).values.max() ?? 0
    }

    /// The expected calibration error over equal-width bins.
    ///
    /// Each sample falls in the bin its confidence names. Every bin compares
    /// how often it was right with how sure it was, and the error is the
    /// average of those gaps, weighted by how many samples each bin holds. A
    /// model that is right nine times out of ten when it says 0.9 scores
    /// zero. Empty input scores zero.
    ///
    /// With the default of ten bins, bin `k` covers `k / 10` up to but not
    /// including `(k + 1) / 10`, and the last bin closes at 1.0, so a
    /// confidence of exactly 0.9 counts with the 0.9s and 1.0 does not fall
    /// off the end. A confidence outside `0...1` is clamped into it.
    public static func expectedCalibrationError(
        _ samples: [(confidence: Double, correct: Bool)],
        bins: Int = 10
    ) -> Double {
        guard !samples.isEmpty, bins > 0 else { return 0 }
        var counts = [Int](repeating: 0, count: bins)
        var confidenceSums = [Double](repeating: 0, count: bins)
        var correctCounts = [Double](repeating: 0, count: bins)
        for sample in samples {
            let confidence = min(max(sample.confidence, 0), 1)
            let bin = min(bins - 1, Int(confidence * Double(bins)))
            counts[bin] += 1
            confidenceSums[bin] += confidence
            correctCounts[bin] += sample.correct ? 1 : 0
        }
        var error = 0.0
        for bin in 0..<bins where counts[bin] > 0 {
            let size = Double(counts[bin])
            let accuracy = correctCounts[bin] / size
            let confidence = confidenceSums[bin] / size
            error += size / Double(samples.count) * abs(accuracy - confidence)
        }
        return error
    }

    /// Sorts confidences into the three bands of DESIGN.md section 6.
    ///
    /// Below `low` a person has to look. Below `high` the code asks. Above,
    /// it acts. The rule matches `Answer.band(escalateBelow:confirmBelow:)`.
    public static func bands(
        _ confidences: some Sequence<Double>,
        escalateBelow low: Double,
        confirmBelow high: Double
    ) -> (act: Int, confirm: Int, escalate: Int) {
        var counts = (act: 0, confirm: 0, escalate: 0)
        for confidence in confidences {
            if confidence < low {
                counts.escalate += 1
            } else if confidence < high {
                counts.confirm += 1
            } else {
                counts.act += 1
            }
        }
        return counts
    }
}
