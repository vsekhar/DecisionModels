import SwiftSyntax
import SwiftSyntaxMacros

/// What `@Options` and `@Levels` share: an enum of plain cases, each with a
/// criterion that tells the model what the case means.
enum AnswerSpace {
    /// One case of an answer space.
    struct Case {
        /// The option id, which is the case name without backticks.
        let name: String
        /// The case name as Swift writes it, backticks and all.
        let spelling: String
        /// The `Criterion(...)` the question carries.
        let criterion: String
    }

    /// Reads the cases, or reports why it cannot.
    static func cases(
        of declaration: some DeclGroupSyntax,
        notAnEnum: DecisionMacroDiagnostic,
        at marker: AttributeSyntax,
        in context: some MacroExpansionContext,
        reporting: Bool
    ) -> [Case]? {
        guard let enumeration = declaration.as(EnumDeclSyntax.self) else {
            if reporting { context.report(notAnEnum, at: marker) }
            return nil
        }

        var cases: [Case] = []
        var sound = true
        for member in enumeration.memberBlock.members {
            guard let group = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            let written = group.attributes.marker(named: "Criterion")
            for element in group.elements {
                if element.parameterClause != nil {
                    if reporting { context.report(.plainCasesOnly, at: element) }
                    sound = false
                    continue
                }
                let name = element.name.plainText
                cases.append(
                    Case(
                        name: name,
                        spelling: element.name.trimmedDescription,
                        criterion: criterion(written, name: name)
                    )
                )
            }
        }
        return sound ? cases : nil
    }

    /// The arguments of `@Criterion` go out verbatim. A case without one says
    /// its own name, in words.
    private static func criterion(_ marker: AttributeSyntax?, name: String) -> String {
        guard
            let arguments = marker?.arguments?.as(LabeledExprListSyntax.self),
            !arguments.isEmpty
        else {
            return "Criterion(\"\(humanized(name))\")"
        }
        return "Criterion(\(arguments.trimmedDescription))"
    }

    /// The members both macros write: the projection that picks the question
    /// kind, the wire id, and what every case means.
    static func members(
        of cases: [Case],
        projection: String,
        access: String
    ) -> [String] {
        // A switch, not `String(describing:)`: a `CustomStringConvertible`
        // conformance must not be able to rename what goes on the wire.
        var ids = ["    \(access)var optionID: String {", "        switch self {"]
        for option in cases {
            ids.append("        case .\(option.spelling): \"\(option.name)\"")
        }
        ids.append("        }")
        ids.append("    }")

        var legend = ["    \(access)var criterion: Criterion {", "        switch self {"]
        for option in cases {
            legend.append("        case .\(option.spelling): \(option.criterion)")
        }
        legend.append("        }")
        legend.append("    }")

        return [
            "    \(access)typealias Projection = \(projection)",
            ids.joined(separator: "\n"),
            legend.joined(separator: "\n"),
        ]
    }

    /// Wraps the members in the extension the macro returns.
    static func extended(
        _ type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        members: [String]
    ) -> [ExtensionDeclSyntax] {
        let inherited = protocols.map(\.trimmedDescription).joined(separator: ", ")
        let clause = protocols.isEmpty ? "" : ": \(inherited)"
        let source = """
            extension \(type.trimmedDescription)\(clause) {
            \(members.joined(separator: "\n\n"))
            }
            """
        guard let extended = DeclSyntax("\(raw: source)").as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [extended]
    }
}
