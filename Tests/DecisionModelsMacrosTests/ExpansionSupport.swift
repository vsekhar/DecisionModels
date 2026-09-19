import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

@testable import DecisionModelsMacros

/// The five macros, with the conformances the compiler asks each one for.
/// `Codable` reaches a macro as its two halves, so the lists spell them out.
let decisionMacros: [String: MacroSpec] = [
    "Ask": MacroSpec(type: AskMacro.self),
    "Criterion": MacroSpec(type: CriterionMacro.self),
    "Decision": MacroSpec(type: DecisionMacro.self, conformances: ["Decision", "Sendable"]),
    "Levels": MacroSpec(
        type: LevelsMacro.self,
        conformances: ["RatingLevel", "Askable", "Decodable", "Encodable", "Comparable"]
    ),
    "Options": MacroSpec(
        type: OptionsMacro.self,
        conformances: ["ChoiceOption", "CaseIterable", "Askable", "Decodable", "Encodable"]
    ),
]

/// `assertMacroExpansion`, with Swift Testing as the failure handler.
func expectExpansion(
    of original: String,
    is expanded: String,
    diagnostics: [DiagnosticSpec] = [],
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    assertMacroExpansion(
        original,
        expandedSource: expanded,
        diagnostics: diagnostics,
        macroSpecs: decisionMacros,
        failureHandler: { failure in
            Issue.record(
                Comment(rawValue: failure.message),
                sourceLocation: SourceLocation(
                    fileID: "\(failure.location.fileID)",
                    filePath: "\(failure.location.filePath)",
                    line: Int(failure.location.line),
                    column: Int(failure.location.column)
                )
            )
        },
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
    )
}
