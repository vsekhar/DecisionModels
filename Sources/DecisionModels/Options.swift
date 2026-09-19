/// A value a model can choose.
public protocol ChoiceOption: Hashable, Sendable {
    /// The id that goes on the wire.
    var optionID: String { get }
    /// What the option means.
    var criterion: Criterion { get }
}

/// One step on an ordered scale.
///
/// Declaration order is low to high.
public protocol RatingLevel: ChoiceOption, CaseIterable, Comparable {}

extension RatingLevel {
    /// The levels in order, low to high.
    static var levels: [Self] { Array(allCases) }

    /// The position of this level on the scale, from zero.
    var levelIndex: Int {
        Self.levels.firstIndex(of: self) ?? 0
    }
}
