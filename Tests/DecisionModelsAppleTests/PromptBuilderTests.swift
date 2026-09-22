import DecisionModels
import Testing

@testable import DecisionModelsApple

@Suite("DecisionPromptBuilder")
struct PromptBuilderTests {
    private let state: State = [
        "message": .text("The shoes came in the wrong size."),
        "orders": .number(3),
        "vip": .bool(true),
    ]

    private var prompt: String {
        DecisionPromptBuilder.prompt(
            state: state,
            questionnaire: promptQuestionnaire,
            fieldNames: ["team": "team", "bug.severity": "bug_severity", "refund": "refund"]
        )
    }

    @Test("The prompt carries the state as JSON")
    func carriesTheState() {
        #expect(prompt.contains("\"message\": \"The shoes came in the wrong size.\""))
        #expect(prompt.contains("\"orders\": 3"))
        #expect(prompt.contains("\"vip\": true"))
    }

    @Test("A prompt with no state starts at the first question")
    func noStateStartsAtTheFirstQuestion() {
        let stateless = DecisionPromptBuilder.prompt(
            state: nil,
            questionnaire: promptQuestionnaire,
            fieldNames: ["team": "team", "bug.severity": "bug_severity", "refund": "refund"]
        )

        #expect(!stateless.contains("STATE"))
        #expect(!stateless.contains("null"))
        #expect(stateless.hasPrefix("## "))
    }

    @Test("A null state is no state for the prompt")
    func nullStateStartsAtTheFirstQuestion() {
        let stateless = DecisionPromptBuilder.prompt(
            state: .null,
            questionnaire: promptQuestionnaire,
            fieldNames: ["team": "team", "bug.severity": "bug_severity", "refund": "refund"]
        )

        #expect(!stateless.contains("STATE"))
        #expect(!stateless.contains("null"))
        #expect(stateless.hasPrefix("## "))
    }

    @Test("The prompt names every question")
    func namesEveryQuestion() {
        for spec in promptQuestionnaire.specs {
            #expect(prompt.contains(spec.id), "The prompt drops question \(spec.id).")
        }
        // A dotted id keeps its safe field name beside it.
        #expect(prompt.contains("## bug_severity (question \"bug.severity\")"))
    }

    @Test("The prompt carries every option and every level")
    func carriesTheAnswerSpace() {
        #expect(prompt.contains("- returns: Exchanges and refunds"))
        #expect(prompt.contains("- shipping: Delivery issues"))
        #expect(prompt.contains("- billing: Payment problems"))
        #expect(prompt.contains("- 0: Cosmetic; nothing stops working"))
        #expect(prompt.contains("- 2: Blocking; no way around it"))
        #expect(prompt.contains("- true: The message asks for money back"))
        #expect(prompt.contains("- false: The message asks for something else"))
    }

    @Test("A structured criterion renders its parts")
    func rendersStructuredCriteria() {
        #expect(prompt.contains("[not for: Payment disputes]"))
        #expect(prompt.contains("[examples: wrong size; arrived damaged]"))
        #expect(prompt.contains("[signals: reports an error]"))
    }

    @Test("Instructions keep the task and add the caller's rules")
    func instructionsCarryBoth() {
        let instructions = DecisionPromptBuilder.instructions(adding: "Answer in the shop's voice.")

        #expect(instructions.contains("You answer questions about a state."))
        #expect(instructions.contains("Answer in the shop's voice."))
        #expect(DecisionPromptBuilder.instructions().contains("Reply with JSON only."))
        #expect(!DecisionPromptBuilder.instructions().contains("shop's voice"))
    }

    @Test("Instructions without a state let the model use what it knows")
    func statelessInstructionsUseWhatTheModelKnows() {
        let instructions = DecisionPromptBuilder.instructions(hasState: false)

        #expect(instructions.contains("what you know"))
        #expect(instructions.contains("Reply with JSON only."))
        #expect(
            instructions.contains(
                "For a choice question, give exactly one option id from that question's list."
            )
        )
        #expect(
            instructions.contains(
                "For a rating question, give the index of the level that fits."
            )
        )
        #expect(instructions.contains("For a yes or no question, give true or false."))
        #expect(!instructions.contains("state"))

        let withExtra = DecisionPromptBuilder.instructions(
            adding: "Answer in the shop's voice.",
            hasState: false
        )
        #expect(withExtra.hasSuffix("\n\nAnswer in the shop's voice."))
    }

    @Test("Instructions with a state are unchanged")
    func statefulInstructionsAreUnchanged() {
        let expected = """
            You answer questions about a state.

            Read the state, then answer every question.
            Reply with JSON only. It must match the schema: one field per question,
            every field present.
            Be literal. Judge what the state says, and add nothing to it.
            For a choice question, give exactly one option id from that question's list.
            For a rating question, give the index of the level that fits.
            For a yes or no question, give true or false.
            """

        #expect(DecisionPromptBuilder.instructions() == expected)
        #expect(DecisionPromptBuilder.instructions(adding: nil, hasState: true) == expected)
    }

    @Test("A null state is no state for the instructions")
    func nullStateCarriesNothingToJudge() {
        #expect(DecisionPromptBuilder.hasState(.null) == false)
        #expect(DecisionPromptBuilder.hasState(nil) == false)
        #expect(DecisionPromptBuilder.hasState(.text("")) == true)
    }

    @Test("Structured instructions become JSON")
    func structuredInstructionsBecomeJSON() {
        let rendered = DecisionPromptBuilder.text(of: ["ask": "Which team?"])

        #expect(rendered.contains("\"ask\": \"Which team?\""))
        #expect(DecisionPromptBuilder.text(of: "Which team?") == "Which team?")
    }

    // MARK: The context guard

    /// A stub: four characters to the token, so a test can size a request
    /// without a model.
    private let counter: DecisionPromptBuilder.TokenCounter = { text in text.count / 4 }

    @Test("A request that fits reports its estimate")
    func fittingRequestPasses() async throws {
        let estimate = try await DecisionPromptBuilder.estimate(
            instructions: DecisionPromptBuilder.instructions(),
            prompt: prompt,
            schemaTokens: 40,
            questions: promptQuestionnaire.specs.count,
            limit: 4096,
            counter: counter
        )

        #expect((estimate ?? 0) > 40)
        #expect((estimate ?? .max) < 4096)
    }

    @Test("The reserve grows with the questionnaire")
    func reserveGrowsWithTheQuestionnaire() {
        // A short questionnaire keeps the floor.
        #expect(DecisionPromptBuilder.responseReserve(questions: 1) == 256)
        #expect(DecisionPromptBuilder.responseReserve(questions: 32) == 256)
        // A long one asks for eight tokens a question.
        #expect(DecisionPromptBuilder.responseReserve(questions: 33) == 264)
        #expect(DecisionPromptBuilder.responseReserve(questions: 100) == 800)
    }

    @Test("An oversized state throws contextSizeExceeded")
    func oversizedStateThrows() async throws {
        let huge = String(repeating: "wrong size shoes ", count: 4_000)
        do {
            _ = try await DecisionPromptBuilder.estimate(
                instructions: DecisionPromptBuilder.instructions(),
                prompt: DecisionPromptBuilder.prompt(
                    state: .text(huge),
                    questionnaire: promptQuestionnaire,
                    fieldNames: ["team": "team", "bug.severity": "bug_severity", "refund": "refund"]
                ),
                questions: promptQuestionnaire.specs.count,
                limit: 4096,
                counter: counter
            )
            Issue.record("The guard let an oversized request through.")
        } catch DecisionError.contextSizeExceeded(let limit, let estimated) {
            #expect(limit == 4096)
            let estimatedTokens = try #require(estimated)
            #expect(estimatedTokens > 4096 - DecisionPromptBuilder.responseReserve(questions: 3))
        }
    }

    @Test("The answer keeps its reserve")
    func reserveIsKept() async throws {
        let reserve = DecisionPromptBuilder.responseReserve(questions: 3)
        // Right at the edge: the estimate leaves exactly the reserve free.
        let text = String(repeating: "a", count: 4 * (4096 - reserve))
        let estimate = try await DecisionPromptBuilder.estimate(
            instructions: "", prompt: text, questions: 3, limit: 4096, counter: counter
        )
        #expect(estimate == 4096 - reserve)

        do {
            _ = try await DecisionPromptBuilder.estimate(
                instructions: "aaaa", prompt: text, questions: 3, limit: 4096, counter: counter
            )
            Issue.record("The guard let the reserve go.")
        } catch DecisionError.contextSizeExceeded {
            // Expected: one token more than the request may take.
        }
    }

    @Test("A long questionnaire keeps more room for its answer")
    func aLongQuestionnaireReservesMore() async throws {
        // A request that fits the 256-token floor, but not the reserve a
        // hundred questions ask for.
        let text = String(repeating: "a", count: 4 * (4096 - 300))
        let estimate = try await DecisionPromptBuilder.estimate(
            instructions: "", prompt: text, questions: 3, limit: 4096, counter: counter
        )
        #expect(estimate == 4096 - 300)

        do {
            _ = try await DecisionPromptBuilder.estimate(
                instructions: "", prompt: text, questions: 100, limit: 4096, counter: counter
            )
            Issue.record("The guard ignored the larger reserve.")
        } catch DecisionError.contextSizeExceeded {
            // Expected: 100 questions reserve 800 tokens, and only 300 are free.
        }
    }

    @Test("No counter means no estimate and no guard")
    func withoutACounter() async throws {
        let estimate = try await DecisionPromptBuilder.estimate(
            instructions: String(repeating: "a", count: 100_000),
            prompt: "",
            questions: 3,
            limit: 4096,
            counter: nil
        )

        #expect(estimate == nil)
    }
}

/// The same three questions the schema tests use, kept here so the two
/// suites stay independent.
let promptQuestionnaire = Questionnaire([
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
