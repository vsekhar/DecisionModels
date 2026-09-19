import Foundation

/// The material a model judges: a JSON-like value.
///
/// A provider sends a text, an object, or an array. `State` carries all three
/// without loss.
public enum State: Sendable, Hashable, Codable,
                   ExpressibleByStringInterpolation,
                   ExpressibleByDictionaryLiteral,
                   ExpressibleByArrayLiteral {
    case text(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([State])
    case object([String: State])

    /// Builds state from any `Encodable` value through JSON.
    public init(encoding value: some Encodable) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(State.self, from: data)
    }

    public init(stringLiteral value: String) {
        self = .text(value)
    }

    public init(dictionaryLiteral elements: (String, State)...) {
        var object: [String: State] = [:]
        for (key, value) in elements { object[key] = value }
        self = .object(object)
    }

    public init(arrayLiteral elements: State...) {
        self = .array(elements)
    }

    // MARK: Codable

    /// Encodes as plain JSON. A text is a JSON string, an object is a JSON
    /// object. Nothing wraps the case name.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .number(let number): try container.encode(number)
        case .bool(let flag): try container.encode(flag)
        case .null: try container.encodeNil()
        case .array(let values): try container.encode(values)
        case .object(let fields): try container.encode(fields)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let flag = try? container.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .text(text)
        } else if let values = try? container.decode([State].self) {
            self = .array(values)
        } else if let fields = try? container.decode([String: State].self) {
            self = .object(fields)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "The value is not JSON that State can hold."
            )
        }
    }
}

/// A type that renders itself as state.
public protocol StateRepresentable: Sendable {
    var stateRepresentation: State { get }
}

extension State: StateRepresentable {
    public var stateRepresentation: State { self }
}

extension String: StateRepresentable {
    public var stateRepresentation: State { .text(self) }
}

extension Bool: StateRepresentable {
    public var stateRepresentation: State { .bool(self) }
}

extension Int: StateRepresentable {
    public var stateRepresentation: State { .number(Double(self)) }
}

extension Double: StateRepresentable {
    public var stateRepresentation: State { .number(self) }
}

extension Array: StateRepresentable where Element: StateRepresentable {
    public var stateRepresentation: State { .array(map(\.stateRepresentation)) }
}

extension Dictionary: StateRepresentable where Key == String, Value: StateRepresentable {
    public var stateRepresentation: State {
        .object(mapValues(\.stateRepresentation))
    }
}
