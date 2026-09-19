/// One named part of a state object.
public struct Field: Sendable, Hashable {
    public let name: String
    public let value: State

    public init(_ name: String, _ value: some StateRepresentable) {
        self.name = name
        self.value = value.stateRepresentation
    }

    /// Encodes any `Encodable` value into the field through JSON.
    public init(_ name: String, encoding value: some Encodable) throws {
        self.name = name
        self.value = try State(encoding: value)
    }
}

/// Assembles named fields into a `State.object`.
///
/// The builder supports `if`, `if let`, `for`, and `try`.
@resultBuilder
public enum StateBuilder {
    public static func buildExpression(_ field: Field) -> [Field] { [field] }

    public static func buildExpression(_ fields: [Field]) -> [Field] { fields }

    public static func buildBlock(_ parts: [Field]...) -> [Field] { parts.flatMap(\.self) }

    public static func buildOptional(_ part: [Field]?) -> [Field] { part ?? [] }

    public static func buildEither(first part: [Field]) -> [Field] { part }

    public static func buildEither(second part: [Field]) -> [Field] { part }

    public static func buildArray(_ parts: [[Field]]) -> [Field] { parts.flatMap(\.self) }

    public static func buildLimitedAvailability(_ part: [Field]) -> [Field] { part }

    public static func buildFinalResult(_ parts: [Field]) -> State {
        var object: [String: State] = [:]
        for field in parts { object[field.name] = field.value }
        return .object(object)
    }
}
