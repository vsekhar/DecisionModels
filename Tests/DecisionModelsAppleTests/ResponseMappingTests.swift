#if canImport(FoundationModels)
import DecisionModels
import FoundationModels
import Testing

@testable import DecisionModelsApple

@Suite("ResponseMapping")
struct ResponseMappingTests {
    private let fieldNames = ["team": "team", "bug.severity": "bug_severity", "refund": "refund"]

    // MARK: Reading one generation

    @Test("One generation reads into one outcome per question")
    func readsEveryKind() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let content = try GeneratedContent(
            json: #"{"team": "shipping", "bug_severity": 2, "refund": true}"#
        )

        let outcomes = try ResponseMapping.outcomes(
            from: content, questionnaire: mappingQuestionnaire, fieldNames: fieldNames
        )

        #expect(outcomes["team"] == .choice(optionID: "shipping"))
        #expect(outcomes["bug.severity"] == .rating(index: 2))
        #expect(outcomes["refund"] == .verdict(true))
    }

    @Test("Content built from properties reads the same way")
    func readsBuiltProperties() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let content = GeneratedContent(
            properties: ["team": "billing", "bug_severity": 0, "refund": false]
        )

        let outcomes = try ResponseMapping.outcomes(
            from: content, questionnaire: mappingQuestionnaire, fieldNames: fieldNames
        )

        #expect(outcomes["team"] == .choice(optionID: "billing"))
        #expect(outcomes["bug.severity"] == .rating(index: 0))
        #expect(outcomes["refund"] == .verdict(false))
    }

    @Test("An option the question does not list is malformed")
    func unknownOptionIsMalformed() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let content = try GeneratedContent(
            json: #"{"team": "legal", "bug_severity": 1, "refund": true}"#
        )

        expectMalformed("an unlisted option") {
            _ = try ResponseMapping.outcomes(
                from: content, questionnaire: mappingQuestionnaire, fieldNames: fieldNames
            )
        }
    }

    @Test("A level off the scale is malformed")
    func outOfRangeLevelIsMalformed() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let content = try GeneratedContent(
            json: #"{"team": "returns", "bug_severity": 7, "refund": true}"#
        )

        expectMalformed("a level off the scale") {
            _ = try ResponseMapping.outcomes(
                from: content, questionnaire: mappingQuestionnaire, fieldNames: fieldNames
            )
        }
    }

    @Test("A missing property is malformed")
    func missingPropertyIsMalformed() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let content = try GeneratedContent(json: #"{"team": "returns", "bug_severity": 1}"#)

        expectMalformed("a missing field") {
            _ = try ResponseMapping.outcomes(
                from: content, questionnaire: mappingQuestionnaire, fieldNames: fieldNames
            )
        }
    }

    @Test("A field of the wrong type is malformed")
    func wrongTypeIsMalformed() throws {
        guard #available(macOS 26, iOS 26, *) else { return needsMacOS26() }
        let content = try GeneratedContent(
            json: #"{"team": "returns", "bug_severity": "high", "refund": true}"#
        )

        expectMalformed("a rating that is not a number") {
            _ = try ResponseMapping.outcomes(
                from: content, questionnaire: mappingQuestionnaire, fieldNames: fieldNames
            )
        }
    }

    // MARK: One draw

    @Test("One draw gives one-hot probabilities and a point estimate")
    func oneDrawIsOneHot() throws {
        let draw: [String: QuestionOutcome] = [
            "team": .choice(optionID: "returns"),
            "bug.severity": .rating(index: 1),
            "refund": .verdict(true),
        ]

        let answers = try ResponseMapping.answers(from: [draw], questionnaire: mappingQuestionnaire)

        #expect(answers.quality == .pointEstimate)
        guard case .choice(let reported, let options, let confidence)? = answers.records["team"]
        else {
            Issue.record("The team answer is not a choice.")
            return
        }
        #expect(reported == "returns")
        #expect(confidence == nil)
        #expect(options == ["returns": 1, "shipping": 0, "billing": 0])

        guard case .rating(let score, let levels, let ratingConfidence)?
            = answers.records["bug.severity"]
        else {
            Issue.record("The severity answer is not a rating.")
            return
        }
        #expect(score == 1)
        #expect(ratingConfidence == nil)
        #expect(levels == [0: 0, 1: 1, 2: 0])

        #expect(answers.records["refund"] == .verdict(probability: 1))
    }

    @Test("A false verdict reads as probability zero")
    func falseVerdict() throws {
        let draw: [String: QuestionOutcome] = [
            "team": .choice(optionID: "billing"),
            "bug.severity": .rating(index: 0),
            "refund": .verdict(false),
        ]

        let answers = try ResponseMapping.answers(from: [draw], questionnaire: mappingQuestionnaire)

        #expect(answers.records["refund"] == .verdict(probability: 0))
    }

    // MARK: Many draws

    @Test("Three draws average into an empirical distribution")
    func threeDrawsAverage() throws {
        let draws: [[String: QuestionOutcome]] = [
            [
                "team": .choice(optionID: "returns"),
                "bug.severity": .rating(index: 1),
                "refund": .verdict(true),
            ],
            [
                "team": .choice(optionID: "returns"),
                "bug.severity": .rating(index: 2),
                "refund": .verdict(true),
            ],
            [
                "team": .choice(optionID: "shipping"),
                "bug.severity": .rating(index: 2),
                "refund": .verdict(false),
            ],
        ]

        let answers = try ResponseMapping.answers(from: draws, questionnaire: mappingQuestionnaire)

        #expect(answers.quality == .sampled(count: 3))

        guard case .choice(let reported, let options, _)? = answers.records["team"] else {
            Issue.record("The team answer is not a choice.")
            return
        }
        #expect(reported == "returns")
        #expect(isClose(options["returns"] ?? 0, 2.0 / 3))
        #expect(isClose(options["shipping"] ?? 0, 1.0 / 3))
        #expect(options["billing"] == 0)
        #expect(isClose(options.values.reduce(0, +), 1))

        guard case .rating(let score, let levels, _)? = answers.records["bug.severity"] else {
            Issue.record("The severity answer is not a rating.")
            return
        }
        #expect(isClose(score, 5.0 / 3))
        #expect(levels[0] == 0)
        #expect(isClose(levels[1] ?? 0, 1.0 / 3))
        #expect(isClose(levels[2] ?? 0, 2.0 / 3))

        #expect(answers.records["refund"] == .verdict(probability: 2.0 / 3))
    }

    @Test("A tie keeps the first option of the question")
    func tieTakesTheFirstOption() throws {
        let draws: [[String: QuestionOutcome]] = [
            [
                "team": .choice(optionID: "shipping"),
                "bug.severity": .rating(index: 0),
                "refund": .verdict(true),
            ],
            [
                "team": .choice(optionID: "returns"),
                "bug.severity": .rating(index: 0),
                "refund": .verdict(false),
            ],
        ]

        let answers = try ResponseMapping.answers(from: draws, questionnaire: mappingQuestionnaire)

        guard case .choice(let reported, _, _)? = answers.records["team"] else {
            Issue.record("The team answer is not a choice.")
            return
        }
        #expect(reported == "returns")
    }

    @Test("A draw that lost a question is malformed")
    func missingOutcomeIsMalformed() {
        let draw: [String: QuestionOutcome] = ["team": .choice(optionID: "returns")]

        expectMalformed("a draw with no rating") {
            _ = try ResponseMapping.answers(from: [draw], questionnaire: mappingQuestionnaire)
        }
    }

    @Test("No draw at all is malformed")
    func noDrawsIsMalformed() {
        expectMalformed("no draws") {
            _ = try ResponseMapping.answers(from: [], questionnaire: mappingQuestionnaire)
        }
    }
}

let mappingQuestionnaire = Questionnaire([
    QuestionSpec(
        id: "team",
        instructions: "Which team should handle this?",
        kind: .choice(options: [
            QuestionSpec.OptionSpec(id: "returns", criterion: "Exchanges and refunds"),
            QuestionSpec.OptionSpec(id: "shipping", criterion: "Delivery issues"),
            QuestionSpec.OptionSpec(id: "billing", criterion: "Payment problems"),
        ])
    ),
    QuestionSpec(
        id: "bug.severity",
        instructions: "How severe is the problem?",
        kind: .rating(levels: ["Cosmetic", "A way around exists", "Blocking"])
    ),
    QuestionSpec(
        id: "refund",
        instructions: "Does the customer ask for money back?",
        kind: .verdict(ifTrue: nil, ifFalse: nil)
    ),
])
#endif
