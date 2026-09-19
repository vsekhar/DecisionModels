/// A weighted sum over several answers, with the weights visible in code.
///
/// Each term holds one `Rating` or `Verdict` as a `0...1` number and the
/// weight it carries. The weights scale to sum to one, so `0.4` and `0.6`
/// and `2` and `3` give the same `value`. `minimumConfidence` follows the
/// rule from the Jev function-calling recipe: the weakest judgment sets the
/// composite's reliability, so gate on the lowest confidence of the terms,
/// never on an average that a sure term can lift.
///
/// ```swift
/// let score = CompositeScore {
///     Weighted(0.4, "severity", severity)
///     Weighted(0.6, "reach", reach)
/// }
/// if score.minimumConfidence >= 0.7, score.value >= 0.5 { page(onCall) }
/// ```
public struct CompositeScore: Sendable {
    /// One named answer and the weight it carries.
    public struct Term: Sendable {
        /// What the term measures.
        public let name: String
        /// The weight as given, before the weights scale to sum to one.
        public let weight: Double
        /// The answer on a `0...1` scale.
        public let normalized: Double
        /// How much the answer can be trusted, `0...1`.
        public let confidence: Double
        /// The weight as a share of every weight. `CompositeScore` sets it.
        public fileprivate(set) var normalizedWeight: Double
        /// `normalizedWeight * normalized`. `CompositeScore` sets it.
        public fileprivate(set) var contribution: Double

        /// Builds a term. The weight must be finite and zero or more; any
        /// other weight is a programmer error. The answer and the confidence
        /// clamp into `0...1`: the composite is a pure value with no way to
        /// throw, so this is the last line of defense against a number that
        /// slipped past a provider's reader.
        public init(name: String, weight: Double, normalized: Double, confidence: Double) {
            precondition(
                weight >= 0 && weight.isFinite,
                "A composite weight must be finite and zero or more."
            )
            self.name = name
            self.weight = weight
            self.normalized = Term.inUnitRange(normalized)
            self.confidence = Term.inUnitRange(confidence)
            self.normalizedWeight = 0
            self.contribution = 0
        }

        /// Keeps a value inside `0...1`, as the confidence formulas do. A
        /// value that is not a number becomes 0.
        private static func inUnitRange(_ value: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(max(value, 0), 1)
        }
    }

    /// Every term, each with the share of the weight it took and what it
    /// added to the total.
    public let terms: [Term]

    /// Builds a composite from a list of terms.
    public init(_ terms: [Term]) {
        let total = terms.reduce(0) { $0 + $1.weight }
        let usable = total.isFinite && total > 0
        var weighted = terms
        for index in weighted.indices {
            let share = usable ? weighted[index].weight / total : 0
            weighted[index].normalizedWeight = share
            weighted[index].contribution = share * weighted[index].normalized
        }
        self.terms = weighted
    }

    /// Builds a composite from terms written one to a line.
    public init(@CompositeBuilder _ terms: () -> [Term]) {
        self.init(terms())
    }

    /// The weighted sum of the terms, `0...1`. It is 0 when there are no
    /// terms, when every weight is zero, or when the weights overflow to
    /// infinity.
    public var value: Double {
        terms.reduce(0) { $0 + $1.contribution }
    }

    /// The lowest confidence of the terms, or 0 when there are none.
    ///
    /// A term with weight zero still counts here. To leave a term out, drop
    /// it with an `if` in the builder; a zero weight silences its value but
    /// not its doubt.
    public var minimumConfidence: Double {
        terms.map(\.confidence).min() ?? 0
    }
}

/// Weighs a rating by its `normalized` score.
public func Weighted<Level: RatingLevel>(
    _ weight: Double,
    _ name: String,
    _ rating: Rating<Level>
) -> CompositeScore.Term {
    CompositeScore.Term(
        name: name,
        weight: weight,
        normalized: rating.normalized,
        confidence: rating.confidence
    )
}

/// Weighs a verdict by its probability.
public func Weighted(
    _ weight: Double,
    _ name: String,
    _ verdict: Verdict
) -> CompositeScore.Term {
    CompositeScore.Term(
        name: name,
        weight: weight,
        normalized: verdict.probability,
        confidence: verdict.confidence
    )
}

/// Assembles weighted terms into a composite score.
///
/// The builder supports `if`, `if let`, `for`, and `switch`.
@resultBuilder
public enum CompositeBuilder {
    public static func buildExpression(_ term: CompositeScore.Term) -> [CompositeScore.Term] {
        [term]
    }

    public static func buildExpression(_ terms: [CompositeScore.Term]) -> [CompositeScore.Term] {
        terms
    }

    public static func buildBlock(_ parts: [CompositeScore.Term]...) -> [CompositeScore.Term] {
        parts.flatMap(\.self)
    }

    public static func buildOptional(_ part: [CompositeScore.Term]?) -> [CompositeScore.Term] {
        part ?? []
    }

    public static func buildEither(first part: [CompositeScore.Term]) -> [CompositeScore.Term] {
        part
    }

    public static func buildEither(second part: [CompositeScore.Term]) -> [CompositeScore.Term] {
        part
    }

    public static func buildArray(_ parts: [[CompositeScore.Term]]) -> [CompositeScore.Term] {
        parts.flatMap(\.self)
    }

    public static func buildLimitedAvailability(
        _ part: [CompositeScore.Term]
    ) -> [CompositeScore.Term] {
        part
    }
}
