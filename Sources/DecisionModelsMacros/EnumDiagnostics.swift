/// What can go wrong with `@Decision` on an enum. The struct form keeps its
/// own messages in `Diagnostics.swift`.
extension DecisionMacroDiagnostic {
    /// Replaces `onlyStructs`, which speaks of a time when a decision could
    /// only be a struct.
    static let structOrEnum = Self(
        "A decision is a struct or an enum.",
        id: "structOrEnum"
    )
    static let commandNeedsInstructions = Self(
        "@Decision on an enum needs the question text: @Decision(\"Which command...\").",
        id: "commandNeedsInstructions"
    )
    static let commandNeedsRealInstructions = Self(
        "The question text of @Decision on an enum cannot be empty.",
        id: "commandNeedsRealInstructions"
    )
    static let commandTakesNoInstructions = Self(
        "@Decision on a struct takes no question text; each @Ask carries its own.",
        id: "commandTakesNoInstructions"
    )
    static let commandNeedsACase = Self(
        "@Decision on an enum needs at least one case.",
        id: "commandNeedsACase"
    )
    static let commandTakesNoRawValue = Self(
        "A command enum takes no raw value. The case names are the wire ids.",
        id: "commandTakesNoRawValue"
    )
    static let commandNeedsOneArgument = Self(
        "A command case takes one decision as its arguments, or none at all.",
        id: "commandNeedsOneArgument"
    )
    static let commandTakesNoLabel = Self(
        "A command case takes its arguments without a label: case plot(PlotArguments).",
        id: "commandTakesNoLabel"
    )
}
