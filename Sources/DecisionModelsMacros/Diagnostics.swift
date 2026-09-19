import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// One message from a DecisionModels macro.
struct DecisionMacroDiagnostic: DiagnosticMessage {
    let message: String
    let severity: DiagnosticSeverity
    private let identifier: String

    init(_ message: String, id identifier: String, severity: DiagnosticSeverity = .error) {
        self.message = message
        self.identifier = identifier
        self.severity = severity
    }

    var diagnosticID: MessageID { MessageID(domain: "DecisionModels", id: identifier) }
}

extension DecisionMacroDiagnostic {
    // MARK: @Decision

    static let unaskedProperty = Self(
        "A stored property of a decision needs an @Ask marker or an initial value.",
        id: "unaskedProperty"
    )
    static let decisionNeedsAQuestion = Self(
        "@Decision needs at least one @Ask property.",
        id: "decisionNeedsAQuestion"
    )

    // MARK: @Ask

    static let askNeedsProperty = Self(
        "@Ask marks a stored property.",
        id: "askNeedsProperty"
    )
    static let askNeedsVar = Self(
        "@Ask marks a var. A let cannot take the answer.",
        id: "askNeedsVar"
    )
    static let askNeedsStorage = Self(
        "@Ask marks a stored property. This one computes its value.",
        id: "askNeedsStorage"
    )
    static let askTakesNoObservers = Self(
        "@Ask does not take a property with a willSet or didSet observer.",
        id: "askTakesNoObservers"
    )
    static let askNeedsOneProperty = Self(
        "@Ask marks one property; declare them separately.",
        id: "askNeedsOneProperty"
    )
    static let askNeedsNoValue = Self(
        "@Ask marks a property with no initial value. The answer gives the value.",
        id: "askNeedsNoValue"
    )
    static let askNeedsInstance = Self(
        "@Ask marks an instance property.",
        id: "askNeedsInstance"
    )
    static let askNeedsType = Self(
        "@Ask marks a property with a declared type, which picks the question kind.",
        id: "askNeedsType"
    )
    static let optionalNeedsThreshold = Self(
        "An optional property must give minimumConfidence. A threshold is a decision.",
        id: "optionalNeedsThreshold"
    )
    /// The `!` sugar reads back as `T!` in every position the expansion
    /// writes, and the compiler allows it in none of them.
    static func noImplicitlyUnwrapped(_ wrapped: String) -> Self {
        Self(
            "Write `\(wrapped)?`; @Ask does not take an implicitly unwrapped optional.",
            id: "noImplicitlyUnwrapped"
        )
    }

    static let oneThresholdOnly = Self(
        "Give minimumConfidence or minimumProbability, not both. "
            + "An optional gates on confidence; a set gates on the probability of each option.",
        id: "oneThresholdOnly"
    )

    static let nestedTakesNoBranches = Self(
        "@Ask() asks a nested decision, which takes no ifTrue or ifFalse.",
        id: "nestedTakesNoBranches"
    )

    // MARK: @Options and @Levels

    static let optionsNeedEnum = Self(
        "@Options marks an enum.",
        id: "optionsNeedEnum"
    )
    static let levelsNeedEnum = Self(
        "@Levels marks an enum.",
        id: "levelsNeedEnum"
    )
    static let plainCasesOnly = Self(
        "An answer space needs cases without associated values.",
        id: "plainCasesOnly"
    )
    static let optionsNeedACase = Self(
        "@Options needs at least one case.",
        id: "optionsNeedACase"
    )
    static let levelsNeedTwoCases = Self(
        "@Levels needs at least two levels.",
        id: "levelsNeedTwoCases"
    )

    // MARK: @Criterion

    static let criterionNeedsACase = Self(
        "@Criterion marks an enum case.",
        id: "criterionNeedsACase"
    )
}

extension MacroExpansionContext {
    /// Reports one problem against a piece of the source.
    func report(_ diagnostic: DecisionMacroDiagnostic, at node: some SyntaxProtocol) {
        diagnose(Diagnostic(node: Syntax(node), message: diagnostic))
    }
}
