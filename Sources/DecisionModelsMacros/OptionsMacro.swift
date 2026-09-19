import SwiftSyntax
import SwiftSyntaxMacros

/// `@Options` makes an enum an answer space: the model names one case.
///
/// `Hashable` and `Sendable` come with the enum itself; `CaseIterable` and
/// `Codable` synthesize from the conformances this extension adds.
public struct OptionsMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard
            let cases = AnswerSpace.cases(
                of: declaration, notAnEnum: .optionsNeedEnum, at: node, in: context, reporting: true
            )
        else { return [] }
        guard !cases.isEmpty else {
            context.report(.optionsNeedACase, at: node)
            return []
        }

        let access = accessPrefix(of: declaration.modifiers)
        return AnswerSpace.extended(
            type,
            conformingTo: protocols,
            members: AnswerSpace.members(
                of: cases,
                projection: "Choice<\(type.trimmedDescription)>",
                access: access
            )
        )
    }
}
