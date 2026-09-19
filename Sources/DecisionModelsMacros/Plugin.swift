import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler plugin that carries the DecisionModels macros.
@main
struct DecisionModelsPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        AskMacro.self,
        CriterionMacro.self,
        DecisionMacro.self,
        LevelsMacro.self,
        OptionsMacro.self,
    ]
}
