import SwiftSyntax
import SwiftSyntaxMacros

/// `@Levels` makes an enum an ordered scale. Declaration order runs low to
/// high, and that order is what `Comparable` compares.
public struct LevelsMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard
            let cases = AnswerSpace.cases(
                of: declaration, notAnEnum: .levelsNeedEnum, at: node, in: context, reporting: true
            )
        else { return [] }
        guard cases.count >= 2 else {
            context.report(.levelsNeedTwoCases, at: node)
            return []
        }

        let access = accessPrefix(of: declaration.modifiers)
        var members = AnswerSpace.members(
            of: cases,
            projection: "Rating<\(type.trimmedDescription)>",
            access: access
        )
        members.append(
            """
                \(access)static func < (low: Self, high: Self) -> Bool {
                    allCases.firstIndex(of: low)! < allCases.firstIndex(of: high)!
                }
            """
        )
        return AnswerSpace.extended(type, conformingTo: protocols, members: members)
    }
}
