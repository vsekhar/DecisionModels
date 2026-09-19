import SwiftSyntax
import SwiftSyntaxMacros

/// `@Decision` reads the `@Ask` properties and writes the whole of the
/// `Decision` conformance: the questionnaire, the two initializers, and the
/// answers. See DESIGN.md section 12.
///
/// The members go in the type itself, not in the extension, so that generated
/// code can name whatever the type can name. A decision nested in an enum
/// namespace sees its siblings; an extension at file scope would not.
///
/// On an enum the macro writes a command instead; `DecisionEnumMacro` does
/// that work.
public struct DecisionMacro: ExtensionMacro, MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // The member role reports the problems, so one mistake gives one
        // message. This role carries the conformance and nothing else.
        guard !protocols.isEmpty else { return [] }

        let asked = protocols.map(\.trimmedDescription)
        let inherited: String
        if declaration.is(StructDeclSyntax.self) {
            inherited = asked.joined(separator: ", ")
        } else if let enumeration = declaration.as(EnumDeclSyntax.self) {
            // An enum stores no projection, so it is askable through its
            // nested `Answered` and is never a decision itself.
            guard DecisionEnumMacro.isCommand(enumeration, marker: node, in: context) else {
                return []
            }
            inherited = (["Askable"] + asked.filter { $0 != "Decision" && $0 != "Askable" })
                .joined(separator: ", ")
        } else {
            return []
        }
        guard !inherited.isEmpty else { return [] }

        let source = """
            extension \(type.trimmedDescription): \(inherited) {
            }
            """
        guard let extended = DeclSyntax("\(raw: source)").as(ExtensionDeclSyntax.self) else {
            return []
        }
        return [extended]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        if let enumeration = declaration.as(EnumDeclSyntax.self) {
            return DecisionEnumMacro.members(of: enumeration, marker: node, in: context)
        }
        guard let structure = declaration.as(StructDeclSyntax.self) else {
            context.report(.structOrEnum, at: node)
            return []
        }
        if DecisionEnumMacro.instructions(of: node) != nil {
            // A struct's questions come from its properties, one text each.
            context.report(.commandTakesNoInstructions, at: node)
        }

        let access = accessPrefix(of: structure.modifiers)
        let properties = askedProperties(of: structure, in: context, at: node)
        return [
            "\(raw: questionnaire(of: properties, access: access))",
            "\(raw: reader(of: properties, access: access))",
            "\(raw: writer(of: properties, access: access))",
            "\(raw: initializer(of: properties, access: access))",
        ]
    }

    // MARK: Reading the struct

    /// Every asked property, in declaration order.
    ///
    /// `@Ask` itself reports what is wrong with a property, so this pass
    /// reports only what the struct as a whole gets wrong: a stored property
    /// that asks nothing and holds nothing, which `init(answers:)` could not
    /// give a value, and a decision that asks nothing at all.
    private static func askedProperties(
        of structure: StructDeclSyntax,
        in context: some MacroExpansionContext,
        at marker: AttributeSyntax
    ) -> [AskedProperty] {
        var properties: [AskedProperty] = []
        var asked = 0
        for member in structure.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            if let ask = variable.attributes.marker(named: "Ask") {
                asked += 1
                let property = AskedProperty.parse(
                    marker: ask, on: variable, in: context, reporting: false
                )
                if let property { properties.append(property) }
            } else if isBareStorage(variable) {
                context.report(.unaskedProperty, at: variable)
            }
        }
        if asked == 0 { context.report(.decisionNeedsAQuestion, at: marker) }
        return properties
    }

    /// True for an instance property that stores a value and starts empty.
    private static func isBareStorage(_ variable: VariableDeclSyntax) -> Bool {
        for modifier in variable.modifiers
        where modifier.name.tokenKind == .keyword(.static)
            || modifier.name.tokenKind == .keyword(.class) {
            return false
        }
        for binding in variable.bindings {
            if binding.initializer != nil { continue }
            guard let accessors = binding.accessorBlock else { return true }
            // `willSet` and `didSet` still leave the property stored.
            guard case .accessors(let list) = accessors.accessors else { return false }
            let observers: Set<TokenKind> = [.keyword(.willSet), .keyword(.didSet)]
            if list.allSatisfy({ observers.contains($0.accessorSpecifier.tokenKind) }) {
                return true
            }
        }
        return false
    }

    // MARK: Writing the members

    /// The questionnaire computes itself, so that a generic decision compiles:
    /// a generic type takes no stored static.
    private static func questionnaire(of properties: [AskedProperty], access: String) -> String {
        var lines = ["\(access)static var questions: Questionnaire {"]
        guard !properties.isEmpty else {
            lines.append("    Questionnaire([])")
            lines.append("}")
            return lines.joined(separator: "\n")
        }
        let asked = properties.map {
            "\($0.type).questions(id: \"\($0.id)\", \($0.inquiry))"
        }
        lines.append("    Questionnaire(")
        lines.append("        \(asked[0])")
        for question in asked.dropFirst() { lines.append("            + \(question)") }
        lines.append("    )")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func reader(of properties: [AskedProperty], access: String) -> String {
        var lines = ["\(access)init(answers: Answers) throws {"]
        for property in properties {
            lines.append(
                "    \(property.peer) = try \(property.type)"
                    + ".projection(in: answers, id: \"\(property.id)\")"
            )
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func writer(of properties: [AskedProperty], access: String) -> String {
        var lines = ["\(access)var answers: Answers {"]
        guard !properties.isEmpty else {
            lines.append("    Answers(merging: [])")
            lines.append("}")
            return lines.joined(separator: "\n")
        }
        lines.append("    Answers(merging: [")
        for property in properties {
            lines.append(
                "        \(property.type).answers(from: \(property.peer), "
                    + "id: \"\(property.id)\"),"
            )
        }
        lines.append("    ])")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// The plain-value initializer, for unit tests and previews. Every answer
    /// it builds is certain, except a `nil`, which says nothing.
    private static func initializer(of properties: [AskedProperty], access: String) -> String {
        let parameters = properties.map { "\($0.spelling): \($0.type)" }.joined(separator: ", ")
        var lines = ["\(access)init(\(parameters)) {"]
        for property in properties {
            lines.append("    \(property.peer) = \(property.type).certain(\(property.spelling))")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }
}
