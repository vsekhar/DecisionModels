import SwiftSyntax
import SwiftSyntaxMacros

/// One `@Ask` property, as the macros write it out.
///
/// A macro sees syntax, not types, so everything here is text. The declared
/// type goes out verbatim and the type system picks the question kind.
struct AskedProperty {
    /// The question id, which is the property name without backticks.
    let id: String
    /// The property name as Swift writes it, backticks and all.
    let spelling: String
    /// The declared type, `?` included.
    let type: String
    /// `public `, `package `, or nothing.
    let access: String
    /// The `Inquiry(...)` the questionnaire asks with.
    let inquiry: String
    /// The threshold, when the marker gives one.
    let minimumConfidence: String?

    /// The peer that holds the rich answer. A `$` name takes no backticks,
    /// because the `$` already keeps it apart from every keyword.
    var peer: String { "$\(id)" }
}

extension AskedProperty {
    /// Reads a marker and its property. A property with a problem gives `nil`,
    /// and reports when `reporting` says to.
    static func parse(
        marker: AttributeSyntax,
        on declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext,
        reporting: Bool
    ) -> AskedProperty? {
        func fail(_ problem: DecisionMacroDiagnostic, at node: some SyntaxProtocol) -> Self? {
            if reporting { context.report(problem, at: node) }
            return nil
        }

        guard let variable = declaration.as(VariableDeclSyntax.self) else {
            return fail(.askNeedsProperty, at: declaration)
        }
        guard variable.bindingSpecifier.tokenKind == .keyword(.var) else {
            return fail(.askNeedsVar, at: variable.bindingSpecifier)
        }
        for modifier in variable.modifiers
        where modifier.name.tokenKind == .keyword(.static)
            || modifier.name.tokenKind == .keyword(.class) {
            return fail(.askNeedsInstance, at: modifier)
        }
        guard variable.bindings.count == 1 else {
            return fail(.askNeedsOneProperty, at: variable.bindings)
        }
        guard
            let binding = variable.bindings.first,
            let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
        else {
            return fail(.askNeedsProperty, at: variable)
        }
        if let initializer = binding.initializer {
            return fail(.askNeedsNoValue, at: initializer)
        }
        if let accessors = binding.accessorBlock {
            return fail(
                observesOnly(accessors) ? .askTakesNoObservers : .askNeedsStorage,
                at: accessors
            )
        }
        guard let annotation = binding.typeAnnotation else {
            return fail(.askNeedsType, at: pattern)
        }

        let marks = Marks(of: marker)
        if marks.instructions == nil, let branch = marks.ifTrue ?? marks.ifFalse {
            return fail(.nestedTakesNoBranches, at: branch)
        }
        let type = annotation.type
        if let unwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            return fail(
                .noImplicitlyUnwrapped(unwrapped.wrappedType.trimmedDescription),
                at: type
            )
        }
        if isOptional(type), marks.minimumConfidence == nil {
            return fail(.optionalNeedsThreshold, at: marker)
        }

        return AskedProperty(
            id: pattern.identifier.plainText,
            spelling: pattern.identifier.trimmedDescription,
            type: type.trimmedDescription,
            access: accessPrefix(of: variable.modifiers),
            inquiry: marks.inquiry,
            minimumConfidence: marks.minimumConfidence?.trimmedDescription
        )
    }

    /// True when a getter is legal on the property as written, so that a
    /// property the macro turns down still compiles as a computed one and the
    /// compiler adds no second message.
    static func takesAccessors(_ declaration: some DeclSyntaxProtocol) -> Bool {
        guard
            let variable = declaration.as(VariableDeclSyntax.self),
            variable.bindingSpecifier.tokenKind == .keyword(.var),
            variable.bindings.count == 1,
            let binding = variable.bindings.first,
            binding.pattern.is(IdentifierPatternSyntax.self),
            binding.initializer == nil,
            binding.accessorBlock == nil,
            binding.typeAnnotation != nil
        else { return false }
        return true
    }

    /// An optional answer gates on a threshold, and the macro must see that in
    /// the syntax: `T?` or `Optional<T>`.
    private static func isOptional(_ type: TypeSyntax) -> Bool {
        if type.is(OptionalTypeSyntax.self) { return true }
        if let named = type.as(IdentifierTypeSyntax.self) {
            return named.name.text == "Optional" && named.genericArgumentClause != nil
        }
        return false
    }

    /// True when the property stores its value and only watches it change.
    private static func observesOnly(_ accessors: AccessorBlockSyntax) -> Bool {
        guard case .accessors(let list) = accessors.accessors else { return false }
        let observers: Set<TokenKind> = [.keyword(.willSet), .keyword(.didSet)]
        return !list.isEmpty
            && list.allSatisfy { observers.contains($0.accessorSpecifier.tokenKind) }
    }

    /// What the `@Ask` arguments say, expression by expression.
    private struct Marks {
        var instructions: ExprSyntax?
        var minimumConfidence: ExprSyntax?
        var ifTrue: ExprSyntax?
        var ifFalse: ExprSyntax?

        init(of marker: AttributeSyntax) {
            guard let arguments = marker.arguments?.as(LabeledExprListSyntax.self) else { return }
            for argument in arguments {
                switch argument.label?.text {
                case nil, "instructions": instructions = argument.expression
                case "minimumConfidence": minimumConfidence = argument.expression
                case "ifTrue": ifTrue = argument.expression
                case "ifFalse": ifFalse = argument.expression
                default: continue
                }
            }
        }

        /// The arguments, as the framework takes them. The expressions go out
        /// verbatim, so a structured state or a named value still works.
        var inquiry: String {
            var parts: [String] = []
            if let instructions { parts.append(instructions.trimmedDescription) }
            if let ifTrue { parts.append("ifTrue: \(ifTrue.trimmedDescription)") }
            if let ifFalse { parts.append("ifFalse: \(ifFalse.trimmedDescription)") }
            return "Inquiry(\(parts.joined(separator: ", ")))"
        }
    }
}
