// The markers the compiler plugin expands. See DESIGN.md sections 5 and 12.

/// Makes a struct a decision: one request answers all of its `@Ask`
/// properties.
///
/// The macro adds the `Decision` conformance and writes `questions`,
/// `init(answers:)`, `answers`, and a plain-value initializer that builds
/// certain answers for tests and previews.
@attached(extension, conformances: Decision, Sendable)
@attached(
    member,
    names: named(questions), named(init(answers:)), named(answers), arbitrary
)
public macro Decision() = #externalMacro(module: "DecisionModelsMacros", type: "DecisionMacro")

/// Asks one question about the state and keeps the answer in `$name`.
///
/// The declared type picks the question kind: an `@Options` enum asks a
/// choice, an `@Levels` enum a rating, a `Bool` a yes or no.
@attached(peer, names: prefixed(`$`))
@attached(accessor)
public macro Ask(
    _ instructions: State,
    ifTrue: Criterion? = nil,
    ifFalse: Criterion? = nil
) = #externalMacro(module: "DecisionModelsMacros", type: "AskMacro")

/// Asks one question and gates the answer on its confidence. The property type
/// must be optional, because the answer can fall short.
@attached(peer, names: prefixed(`$`))
@attached(accessor)
public macro Ask(
    _ instructions: State,
    minimumConfidence: Double,
    ifTrue: Criterion? = nil,
    ifFalse: Criterion? = nil
) = #externalMacro(module: "DecisionModelsMacros", type: "AskMacro")

/// Asks one question with instructions under a label, structured or not.
@attached(peer, names: prefixed(`$`))
@attached(accessor)
public macro Ask(
    instructions: State,
    ifTrue: Criterion? = nil,
    ifFalse: Criterion? = nil
) = #externalMacro(module: "DecisionModelsMacros", type: "AskMacro")

/// Asks one labelled question and gates the answer on its confidence.
@attached(peer, names: prefixed(`$`))
@attached(accessor)
public macro Ask(
    instructions: State,
    minimumConfidence: Double,
    ifTrue: Criterion? = nil,
    ifFalse: Criterion? = nil
) = #externalMacro(module: "DecisionModelsMacros", type: "AskMacro")

/// Asks a nested decision, which brings its own questions.
@attached(peer, names: prefixed(`$`))
@attached(accessor)
public macro Ask() = #externalMacro(module: "DecisionModelsMacros", type: "AskMacro")

/// Makes an enum an answer space: one case, chosen.
///
/// Every case carries a `Criterion`, from `@Criterion` or from the case name.
@attached(
    extension,
    conformances: ChoiceOption, CaseIterable, Askable, Codable,
    names: named(optionID), named(criterion), named(Projection)
)
public macro Options() = #externalMacro(module: "DecisionModelsMacros", type: "OptionsMacro")

/// Makes an enum an ordered scale. Declaration order runs low to high.
@attached(
    extension,
    conformances: RatingLevel, Askable, Codable, Comparable,
    names: named(optionID), named(criterion), named(Projection), named(<)
)
public macro Levels() = #externalMacro(module: "DecisionModelsMacros", type: "LevelsMacro")

/// Says what one case means. `@Options` and `@Levels` read it.
@attached(peer)
public macro Criterion(
    _ summary: String,
    notFor: String? = nil,
    examples: [String] = [],
    signals: [String] = []
) = #externalMacro(module: "DecisionModelsMacros", type: "CriterionMacro")
