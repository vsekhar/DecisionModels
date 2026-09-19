#if canImport(FoundationModels)
import DecisionModels
import FoundationModels

/// The schema of one questionnaire, with the names that tie its JSON fields
/// back to the question ids.
@available(macOS 26, iOS 26, *)
struct QuestionnaireSchema: Sendable {
    /// What the model generates against.
    let schema: GenerationSchema
    /// Question id to JSON field name.
    let fieldNames: [String: String]
    /// JSON field name back to question id.
    let questionIDs: [String: String]
}

/// Turns a questionnaire into one generation schema: an object with a
/// property per question.
///
/// Only the two members that touch FoundationModels carry availability, so
/// the name mapping stays testable on any OS.
enum SchemaBuilder {
    /// The name of the object the model fills in.
    static let rootName = "Answers"

    /// Maps every question id to a JSON field name.
    ///
    /// A dotted id is not a valid field name, so `bug.severity` becomes
    /// `bug_severity`. Two ids that collapse to the same name get an index,
    /// so a second `a_b` becomes `a_b_2`.
    static func fieldNames(for ids: [String]) -> [String: String] {
        var used: Set<String> = []
        var names: [String: String] = [:]
        for id in ids {
            var name = fieldName(for: id)
            if used.contains(name) {
                var index = 2
                while used.contains("\(name)_\(index)") { index += 1 }
                name = "\(name)_\(index)"
            }
            used.insert(name)
            names[id] = name
        }
        return names
    }

    /// Turns one id into a name a JSON schema accepts.
    static func fieldName(for id: String) -> String {
        var name = ""
        for character in id {
            if character.isASCII, character.isLetter || character.isNumber || character == "_" {
                name.append(character)
            } else {
                name.append("_")
            }
        }
        if name.isEmpty { name = "field" }
        if let first = name.first, first.isNumber { name = "_" + name }
        return name
    }

    /// Builds the schema of one questionnaire.
    @available(macOS 26, iOS 26, *)
    static func build(_ questionnaire: Questionnaire) throws -> QuestionnaireSchema {
        let names = fieldNames(for: questionnaire.specs.map(\.id))
        var properties: [DynamicGenerationSchema.Property] = []
        var questionIDs: [String: String] = [:]
        for spec in questionnaire.specs {
            guard let name = names[spec.id] else { continue }
            questionIDs[name] = spec.id
            properties.append(
                DynamicGenerationSchema.Property(
                    name: name,
                    description: nil,
                    schema: schema(for: spec),
                    isOptional: false
                )
            )
        }
        let root = DynamicGenerationSchema(
            name: rootName,
            description: "One answer per question.",
            properties: properties
        )
        do {
            return QuestionnaireSchema(
                schema: try GenerationSchema(root: root, dependencies: []),
                fieldNames: names,
                questionIDs: questionIDs
            )
        } catch {
            throw DecisionError.invalidQuestion(
                id: "",
                reason: "The questionnaire does not make a schema: \(error)."
            )
        }
    }

    /// The answer space of one question.
    @available(macOS 26, iOS 26, *)
    private static func schema(for spec: QuestionSpec) -> DynamicGenerationSchema {
        switch spec.kind {
        case .choice(let options):
            return DynamicGenerationSchema(
                type: String.self,
                guides: [.anyOf(options.map(\.id))]
            )
        case .rating(let levels):
            let top = max(0, levels.count - 1)
            return DynamicGenerationSchema(type: Int.self, guides: [.range(0...top)])
        case .verdict:
            return DynamicGenerationSchema(type: Bool.self)
        }
    }
}
#endif
