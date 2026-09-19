import SwiftSyntax
import SwiftSyntaxMacros

/// `@Criterion` says what one case means. It writes nothing of its own;
/// `@Options` and `@Levels` read its arguments. The macro exists so that the
/// attribute is legal on a case.
public struct CriterionMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(EnumCaseDeclSyntax.self) else {
            context.report(.criterionNeedsACase, at: node)
            return []
        }
        return []
    }
}
