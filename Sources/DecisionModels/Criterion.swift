/// What an option or a level means.
///
/// A provider that accepts structured criteria sends the fields as JSON. A
/// provider that does not gets a rendered string. The application does not
/// know which.
public struct Criterion: Sendable, Hashable, Codable, ExpressibleByStringLiteral {
    /// What the option or level covers.
    public var summary: String
    /// What it does not cover.
    public var notFor: String?
    /// Short examples that belong to it.
    public var examples: [String]
    /// Signals in the state that point to it.
    public var signals: [String]

    public init(
        _ summary: String,
        notFor: String? = nil,
        examples: [String] = [],
        signals: [String] = []
    ) {
        self.summary = summary
        self.notFor = notFor
        self.examples = examples
        self.signals = signals
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }
}
