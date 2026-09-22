import DecisionModels
import Foundation

/// Renders a request into the text the on-device model reads.
///
/// Nothing here touches FoundationModels, so the shape of a prompt is
/// testable without a model, and the token counter comes in from outside.
///
/// The name keeps its distance from `FoundationModels.PromptBuilder`, which
/// is a result builder for `Prompt` values.
enum DecisionPromptBuilder {
    /// Tokens kept free for the answer.
    ///
    /// One answer is short: an option id, a level index, or a boolean. The
    /// JSON around them grows with the questionnaire, so the reserve is
    /// eight tokens a question, and never less than 256.
    static func responseReserve(questions: Int) -> Int {
        max(256, 8 * questions)
    }

    /// Counts the tokens of a text.
    typealias TokenCounter = @Sendable (String) async throws -> Int

    // MARK: Instructions

    /// The standing instructions of the session.
    ///
    /// The caller's own instructions follow the task, so they can add rules
    /// without losing the ones the schema needs.
    static func instructions(adding extra: String? = nil) -> String {
        var lines = [
            "You answer questions about a state.",
            "",
            "Read the state, then answer every question.",
            "Reply with JSON only. It must match the schema: one field per question,",
            "every field present.",
            "Be literal. Judge what the state says, and add nothing to it.",
            "For a choice question, give exactly one option id from that question's list.",
            "For a rating question, give the index of the level that fits.",
            "For a yes or no question, give true or false.",
        ]
        if let extra, !extra.isEmpty {
            lines.append("")
            lines.append(extra)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: The prompt

    /// Renders the state and every question.
    ///
    /// Each question heads its JSON field name, and names its id too when
    /// the two differ, so the model and the reader agree on which is which.
    static func prompt(
        state: State?,
        questionnaire: Questionnaire,
        fieldNames: [String: String]
    ) -> String {
        var out = ""
        if let state {
            out += "STATE\n"
            out += json(state)
            out += "\n"
        }
        for spec in questionnaire.specs {
            let field = fieldNames[spec.id] ?? spec.id
            out += (out.isEmpty ? "## " : "\n## ") + field
            if field != spec.id { out += " (question \"" + spec.id + "\")" }
            out += "\n"
            out += text(of: spec.instructions) + "\n"
            switch spec.kind {
            case .choice(let options):
                out += "Give one of these option ids:\n"
                for option in options {
                    out += "- " + option.id + ": " + rendered(option.criterion) + "\n"
                }
            case .rating(let levels):
                out += "Give one of these level indexes:\n"
                for (index, level) in levels.enumerated() {
                    out += "- \(index): " + rendered(level) + "\n"
                }
            case .verdict(let ifTrue, let ifFalse):
                out += "Answer true or false.\n"
                if let ifTrue { out += "- true: " + rendered(ifTrue) + "\n" }
                if let ifFalse { out += "- false: " + rendered(ifFalse) + "\n" }
            }
        }
        return out
    }

    /// What one option or level means, on one line.
    static func rendered(_ criterion: Criterion) -> String {
        var out = criterion.summary
        if let notFor = criterion.notFor {
            out += " [not for: " + notFor + "]"
        }
        if !criterion.examples.isEmpty {
            out += " [examples: " + criterion.examples.joined(separator: "; ") + "]"
        }
        if !criterion.signals.isEmpty {
            out += " [signals: " + criterion.signals.joined(separator: "; ") + "]"
        }
        return out
    }

    /// Instructions as the model sees them: a text stays a text, anything
    /// else becomes JSON.
    static func text(of state: State) -> String {
        if case .text(let text) = state { return text }
        return json(state)
    }

    // MARK: Fitting the context

    /// Estimates the tokens of one request and checks that the answer still
    /// fits.
    ///
    /// Returns the estimate, or `nil` when there is no counter. Throws
    /// `DecisionError.contextSizeExceeded` when the request leaves less room
    /// than `responseReserve(questions:)` asks for.
    static func estimate(
        instructions: String,
        prompt: String,
        schemaTokens: Int = 0,
        questions: Int,
        limit: Int?,
        counter: TokenCounter?
    ) async throws -> Int? {
        guard let counter else { return nil }
        let instructionTokens = try await counter(instructions)
        let promptTokens = try await counter(prompt)
        let estimated = instructionTokens + promptTokens + schemaTokens
        if let limit, estimated > limit - responseReserve(questions: questions) {
            throw DecisionError.contextSizeExceeded(limit: limit, estimated: estimated)
        }
        return estimated
    }

    // MARK: JSON

    /// Renders state as pretty JSON.
    ///
    /// The package writes this itself so that the text is stable: fields
    /// come out in name order and whole numbers keep no decimal point.
    static func json(_ state: State, indent: String = "") -> String {
        switch state {
        case .text(let text):
            return quoted(text)
        case .number(let number):
            if number.isFinite, number == number.rounded(), abs(number) < 1e15 {
                return String(Int(number))
            }
            return number.isFinite ? String(number) : "null"
        case .bool(let flag):
            return flag ? "true" : "false"
        case .null:
            return "null"
        case .array(let values):
            guard !values.isEmpty else { return "[]" }
            let inner = indent + "  "
            let body = values
                .map { inner + json($0, indent: inner) }
                .joined(separator: ",\n")
            return "[\n" + body + "\n" + indent + "]"
        case .object(let fields):
            guard !fields.isEmpty else { return "{}" }
            let inner = indent + "  "
            let body = fields
                .sorted { $0.key < $1.key }
                .map { inner + quoted($0.key) + ": " + json($0.value, indent: inner) }
                .joined(separator: ",\n")
            return "{\n" + body + "\n" + indent + "}"
        }
    }

    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
