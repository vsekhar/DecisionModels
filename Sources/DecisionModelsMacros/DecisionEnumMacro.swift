import SwiftSyntax
import SwiftSyntaxMacros

/// `@Decision` on an enum: a command with arguments.
///
/// One choice names the case; the arguments of every case travel in the same
/// request, and only the chosen case's arguments are read. An enum stores no
/// projection, so the macro writes two nested types: `Kind`, the answer space
/// over the case names, and `Answered`, the decision that holds the chosen
/// kind and the command it built. The enum itself is `Askable`, with
/// `Answered` as its projection. See DESIGN.md section 16.
enum DecisionEnumMacro {
    /// One case: the option it becomes, and the type of its arguments.
    struct Branch {
        let option: AnswerSpace.Case
        /// The one unlabeled associated value, when the case takes one.
        let arguments: String?
    }

    /// The question text `@Decision("...")` carries, when it carries one.
    static func instructions(of marker: AttributeSyntax) -> String? {
        guard
            let arguments = marker.arguments?.as(LabeledExprListSyntax.self),
            let first = arguments.first
        else { return nil }
        return first.expression.trimmedDescription
    }

    /// True when the question text says nothing: `.null`, or a text with no
    /// letters in it. Such a question fails pre-flight at the first request,
    /// so the macro turns it down here.
    static func isSilent(_ instructions: String) -> Bool {
        if instructions == ".null" || instructions == "State.null" { return true }
        guard instructions.hasPrefix("\""), instructions.hasSuffix("\"") else { return false }
        return instructions.dropFirst().dropLast().allSatisfy(\.isWhitespace)
    }

    /// True when the enum can be a command, which is what the extension role
    /// needs to know. The member role reports what is wrong.
    static func isCommand(
        _ enumeration: EnumDeclSyntax,
        marker: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> Bool {
        guard let instructions = instructions(of: marker), !isSilent(instructions) else {
            return false
        }
        return branches(of: enumeration, marker: marker, in: context, reporting: false) != nil
    }

    /// The members `@Decision` writes into the enum, or nothing when the enum
    /// cannot be a command.
    static func members(
        of enumeration: EnumDeclSyntax,
        marker: AttributeSyntax,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard let instructions = instructions(of: marker) else {
            context.report(.commandNeedsInstructions, at: marker)
            return []
        }
        guard !isSilent(instructions) else {
            context.report(.commandNeedsRealInstructions, at: marker)
            return []
        }
        guard
            let branches = branches(of: enumeration, marker: marker, in: context, reporting: true)
        else { return [] }

        let access = accessPrefix(of: enumeration.modifiers)
        let name = enumeration.name.trimmedDescription
        var members = [
            kind(of: branches, access: access),
            answered(of: branches, named: name, asking: instructions, access: access),
        ]
        members.append(contentsOf: askable(named: name, access: access))
        return members.map { "\(raw: $0)" }
    }

    // MARK: Reading the enum

    /// Every case, in declaration order, or `nil` when one of them cannot be a
    /// command.
    private static func branches(
        of enumeration: EnumDeclSyntax,
        marker: AttributeSyntax,
        in context: some MacroExpansionContext,
        reporting: Bool
    ) -> [Branch]? {
        func fail(_ problem: DecisionMacroDiagnostic, at node: some SyntaxProtocol) {
            if reporting { context.report(problem, at: node) }
        }

        if let raw = rawValueType(of: enumeration) {
            fail(.commandTakesNoRawValue, at: raw)
            return nil
        }

        var branches: [Branch] = []
        var sound = true
        for member in enumeration.memberBlock.members {
            guard let group = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            let written = group.attributes.marker(named: "Criterion")
            for element in group.elements {
                if element.rawValue != nil {
                    fail(.commandTakesNoRawValue, at: element)
                    sound = false
                    continue
                }
                guard
                    let arguments = payload(of: element, in: context, reporting: reporting)
                else {
                    sound = false
                    continue
                }
                let name = element.name.plainText
                branches.append(
                    Branch(
                        option: AnswerSpace.Case(
                            name: name,
                            spelling: element.name.trimmedDescription,
                            criterion: criterion(written, name: name)
                        ),
                        arguments: arguments.isEmpty ? nil : arguments
                    )
                )
            }
        }
        guard sound else { return nil }
        guard !branches.isEmpty else {
            fail(.commandNeedsACase, at: marker)
            return nil
        }
        return branches
    }

    /// The type of the one unlabeled associated value, or an empty string for
    /// a case that takes none. `nil` says the case is not a command.
    private static func payload(
        of element: EnumCaseElementSyntax,
        in context: some MacroExpansionContext,
        reporting: Bool
    ) -> String? {
        guard let clause = element.parameterClause else { return "" }
        guard clause.parameters.count == 1, let only = clause.parameters.first else {
            if reporting { context.report(.commandNeedsOneArgument, at: element) }
            return nil
        }
        if only.firstName != nil {
            if reporting { context.report(.commandTakesNoLabel, at: element) }
            return nil
        }
        return only.type.trimmedDescription
    }

    /// The raw value type, when the enum declares one. A macro sees syntax, so
    /// the pass knows the standard raw types by name.
    private static func rawValueType(of enumeration: EnumDeclSyntax) -> TypeSyntax? {
        let raw: Set<String> = [
            "String", "Character", "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64", "Double", "Float",
        ]
        guard let first = enumeration.inheritanceClause?.inheritedTypes.first else { return nil }
        return raw.contains(first.type.trimmedDescription) ? first.type : nil
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

    // MARK: Writing the members

    /// The answer space over the case names.
    private static func kind(of branches: [Branch], access: String) -> String {
        var lines = ["\(access)enum Kind: ChoiceOption, CaseIterable, Askable, Codable {"]
        lines.append("    case " + branches.map(\.option.spelling).joined(separator: ", "))
        lines.append(
            AnswerSpace.members(
                of: branches.map(\.option), projection: "Choice<Kind>", access: access
            ).joined(separator: "\n")
        )
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// The projection: the chosen kind, and the command its arguments build.
    private static func answered(
        of branches: [Branch],
        named name: String,
        asking instructions: String,
        access: String
    ) -> String {
        var lines = [
            "\(access)struct Answered: Decision {",
            "    \(access)var $kind: Choice<Kind>",
            "    \(access)var kind: Kind {",
            "        Kind.read($kind)",
            "    }",
            "    \(access)let command: \(name)",
            "    \(access)static var questions: Questionnaire {",
            "        Questionnaire(",
            "            Kind.questions(id: \"kind\", Inquiry(\(instructions)))",
        ]
        for branch in branches {
            guard let arguments = branch.arguments else { continue }
            lines.append(
                "                + \(arguments).questions(id: \"\(branch.option.name)\", Inquiry())"
            )
        }
        lines.append("        )")
        lines.append("    }")

        lines.append("    \(access)init(answers: Answers) throws {")
        lines.append("        $kind = try Kind.projection(in: answers, id: \"kind\")")
        lines.append("        switch $kind.value {")
        for branch in branches {
            let option = branch.option.spelling
            if let arguments = branch.arguments {
                lines.append(
                    "        case .\(option): command = .\(option)("
                        + "try \(arguments).projection(in: answers, id: \"\(branch.option.name)\"))"
                )
            } else {
                lines.append("        case .\(option): command = .\(option)")
            }
        }
        lines.append("        }")
        lines.append("    }")

        lines.append("    \(access)var answers: Answers {")
        if branches.allSatisfy({ $0.arguments == nil }) {
            lines.append("        Answers(merging: [Kind.answers(from: $kind, id: \"kind\")])")
        } else {
            lines.append("        var parts = [Kind.answers(from: $kind, id: \"kind\")]")
            lines.append("        switch command {")
            for branch in branches {
                let option = branch.option.spelling
                if let arguments = branch.arguments {
                    lines.append(
                        "        case .\(option)(let arguments): parts.append("
                            + "\(arguments).answers(from: arguments, id: \"\(branch.option.name)\"))"
                    )
                } else {
                    lines.append("        case .\(option): break")
                }
            }
            lines.append("        }")
            lines.append("        return Answers(merging: parts)")
        }
        lines.append("    }")

        lines.append("    \(access)init(_ command: \(name)) {")
        lines.append("        self.command = command")
        lines.append("        switch command {")
        for branch in branches {
            let option = branch.option.spelling
            lines.append("        case .\(option): $kind = Kind.certain(.\(option))")
        }
        lines.append("        }")
        lines.append("    }")
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// The `Askable` members: the enum asks what `Answered` asks, and reads the
    /// command back out of it.
    private static func askable(named name: String, access: String) -> [String] {
        [
            "\(access)typealias Projection = Answered",
            """
            \(access)static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec] {
                Answered.questions(id: id, inquiry)
            }
            """,
            """
            \(access)static func projection(in answers: Answers, id: String) throws -> Answered {
                try Answered.projection(in: answers, id: id)
            }
            """,
            """
            \(access)static func read(_ projection: Answered) -> \(name) {
                projection.command
            }
            """,
            """
            \(access)static func answers(from projection: Answered, id: String) -> Answers {
                Answered.answers(from: projection, id: id)
            }
            """,
            """
            \(access)static func certain(_ value: \(name)) -> Answered {
                Answered(value)
            }
            """,
        ]
    }
}
