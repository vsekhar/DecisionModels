import SwiftSyntax
import SwiftSyntaxMacros

/// `@Ask` rewrites a property into a getter over a `$name` peer, in the way
/// `@Observable` rewrites a tracked property over `_name` storage.
///
/// The peer holds the rich answer. The getter reduces it to the plain value,
/// through the threshold when the property is optional.
public struct AskMacro: PeerMacro, AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Every problem with the property is reported here, once. The accessor
        // role and `@Decision` stay quiet about them.
        guard
            let property = AskedProperty.parse(
                marker: node, on: declaration, in: context, reporting: true
            )
        else { return [] }

        let peer = "\(property.access)var \(property.peer): \(property.type).Projection"
        return ["\(raw: peer)"]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard
            let property = AskedProperty.parse(
                marker: node, on: declaration, in: context, reporting: false
            )
        else {
            // The peer role has already said what is wrong. A placeholder
            // getter keeps the property computed, so the compiler does not
            // report the missing storage on top of it.
            return AskedProperty.takesAccessors(declaration) ? ["get { fatalError() }"] : []
        }

        // Only `Optional` has the two-argument read on confidence and only
        // `Set` the one on probability, so a threshold on any other property
        // fails to type-check at the use site, which is the diagnostic we
        // want. The macro writes what the marker says and checks no types.
        let read: String
        if let threshold = property.minimumConfidence {
            read = "\(property.type).read(\(property.peer), minimumConfidence: \(threshold))"
        } else if let threshold = property.minimumProbability {
            read = "\(property.type).read(\(property.peer), minimumProbability: \(threshold))"
        } else {
            read = "\(property.type).read(\(property.peer))"
        }
        return ["get { \(raw: read) }"]
    }
}
