#if canImport(FoundationModels)
import DecisionModels
import Foundation
import Testing

@testable import DecisionModelsApple

@Suite("SchemaBuilder")
struct SchemaBuilderTests {
    @Test("Every question becomes one property")
    func propertyPerQuestion() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let built = try SchemaBuilder.build(sampleQuestionnaire)
        let properties = try schemaProperties(built)

        #expect(properties.count == 3)
        #expect(properties.keys.sorted() == ["bug_severity", "refund", "team"])
        #expect(built.fieldNames.count == 3)
    }

    @Test("A dotted id round-trips through a safe name")
    func dottedIDsRoundTrip() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let built = try SchemaBuilder.build(sampleQuestionnaire)

        #expect(built.fieldNames["bug.severity"] == "bug_severity")
        #expect(built.fieldNames["team"] == "team")
        #expect(built.questionIDs["bug_severity"] == "bug.severity")
        for (id, name) in built.fieldNames {
            #expect(built.questionIDs[name] == id)
        }
    }

    @Test("Two ids that collapse to one name get an index")
    func collidingNamesGetAnIndex() {
        let names = SchemaBuilder.fieldNames(for: ["a.b", "a_b", "a/b", "a_b_2"])

        #expect(names["a.b"] == "a_b")
        #expect(names["a_b"] == "a_b_2")
        #expect(names["a/b"] == "a_b_3")
        #expect(names["a_b_2"] == "a_b_2_2")
        #expect(Set(names.values).count == 4)
    }

    @Test("An id the schema cannot take becomes a name it can")
    func namesStayValid() {
        #expect(SchemaBuilder.fieldName(for: "bug.severity") == "bug_severity")
        #expect(SchemaBuilder.fieldName(for: "2fast") == "_2fast")
        #expect(SchemaBuilder.fieldName(for: "") == "field")
        #expect(SchemaBuilder.fieldName(for: "a b-c") == "a_b_c")
    }

    @Test("A choice takes only its own option ids")
    func choiceIsConstrained() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let properties = try schemaProperties(try SchemaBuilder.build(sampleQuestionnaire))
        let team = try #require(properties["team"] as? [String: Any])

        #expect(team["type"] as? String == "string")
        #expect(team["enum"] as? [String] == ["returns", "shipping", "billing"])
    }

    @Test("A rating takes only the indexes of its levels")
    func ratingIsRanged() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let properties = try schemaProperties(try SchemaBuilder.build(sampleQuestionnaire))
        let severity = try #require(properties["bug_severity"] as? [String: Any])

        #expect(severity["type"] as? String == "integer")
        #expect(severity["minimum"] as? Int == 0)
        #expect(severity["maximum"] as? Int == 2)
    }

    @Test("A verdict is a boolean")
    func verdictIsBoolean() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let properties = try schemaProperties(try SchemaBuilder.build(sampleQuestionnaire))
        let refund = try #require(properties["refund"] as? [String: Any])

        #expect(refund["type"] as? String == "boolean")
    }

    /// `GenerationSchema` is `Codable`, so a built schema reads back as the
    /// JSON schema the model gets.
    @available(macOS 26, iOS 26, *)
    private func schemaProperties(_ built: QuestionnaireSchema) throws -> [String: Any] {
        let data = try JSONEncoder().encode(built.schema)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(object?["properties"] as? [String: Any])
    }
}

/// Three questions, one of every kind, with one dotted id.
let sampleQuestionnaire = Questionnaire([
    QuestionSpec(
        id: "team",
        instructions: "Which team should handle this?",
        kind: .choice(options: [
            QuestionSpec.OptionSpec(
                id: "returns",
                criterion: Criterion(
                    "Exchanges and refunds",
                    notFor: "Payment disputes",
                    examples: ["wrong size", "arrived damaged"]
                )
            ),
            QuestionSpec.OptionSpec(id: "shipping", criterion: "Delivery issues"),
            QuestionSpec.OptionSpec(id: "billing", criterion: "Payment problems"),
        ])
    ),
    QuestionSpec(
        id: "bug.severity",
        instructions: "How severe is the problem?",
        kind: .rating(levels: [
            "Cosmetic; nothing stops working",
            Criterion("A feature is broken, but a way around exists", signals: ["reports an error"]),
            "Blocking; no way around it",
        ])
    ),
    QuestionSpec(
        id: "refund",
        instructions: "Does the customer ask for money back?",
        kind: .verdict(
            ifTrue: "The message asks for money back",
            ifFalse: "The message asks for something else"
        )
    ),
])
#endif
