import Foundation
import Testing

@testable import DecisionModels

@Suite("Set fan-out")
struct FanOutTests {
    private let answered = FanOut<Team>(verdicts: [
        .returns: Verdict(probability: 0.95, quality: .calibrated),
        .shipping: Verdict(probability: 0.6, quality: .calibrated),
        .billing: Verdict(probability: 0.1, quality: .calibrated),
    ])

    @Test("A set asks one yes or no question per case")
    func oneQuestionPerCase() {
        let specs = Set<Team>.questions(
            id: "symbols",
            Inquiry("Does the request mention {option}?")
        )

        #expect(specs.map(\.id) == ["symbols.returns", "symbols.shipping", "symbols.billing"])
        #expect(specs[0].instructions == .text("Does the request mention Exchanges and refunds?"))
        #expect(specs[1].instructions == .text("Does the request mention Delivery issues?"))
        #expect(specs[2].instructions == .text("Does the request mention Payment problems?"))
        for spec in specs {
            guard case .verdict = spec.kind else {
                Issue.record("The question \(spec.id) is not a verdict.")
                return
            }
        }
    }

    @Test("Both sides of the yes or no pass through to every question")
    func branchesPassThrough() {
        let specs = Set<Team>.questions(
            id: "symbols",
            Inquiry("Mentions {option}?", ifTrue: "named outright", ifFalse: "not named")
        )

        guard case .verdict(let ifTrue, let ifFalse) = specs[0].kind else {
            Issue.record("The question is not a verdict.")
            return
        }
        #expect(ifTrue == Criterion("named outright"))
        #expect(ifFalse == Criterion("not named"))
    }

    @Test("Structured instructions name the option in every string leaf")
    func structuredInstructionsSubstitute() {
        let instructions: State = [
            "question": "Does the request mention {option}?",
            "hints": ["{option} by name", "nothing but {option}"],
            "weight": .number(2),
            "strict": .bool(true),
        ]

        let specs = Set<Team>.questions(id: "symbols", Inquiry(instructions))

        #expect(
            specs[0].instructions
                == .object([
                    "question": .text("Does the request mention Exchanges and refunds?"),
                    "hints": .array([
                        .text("Exchanges and refunds by name"),
                        .text("nothing but Exchanges and refunds"),
                    ]),
                    "weight": .number(2),
                    "strict": .bool(true),
                ])
        )
    }

    @Test("The projection collects the verdict of every case")
    func projectionCollectsEveryCase() throws {
        let answers = Answers(
            records: [
                "symbols.returns": .verdict(probability: 0.95),
                "symbols.shipping": .verdict(probability: 0.6),
                "symbols.billing": .verdict(probability: 0.1),
            ],
            quality: .calibrated
        )

        let projection = try Set<Team>.projection(in: answers, id: "symbols")

        #expect(isClose(projection[.returns].probability, 0.95))
        #expect(isClose(projection[.shipping].probability, 0.6))
        #expect(isClose(projection[.billing].probability, 0.1))
        #expect(projection.quality == .calibrated)
    }

    @Test("A missing verdict names the question as the response knows it")
    func missingVerdictNamesTheDottedID() {
        let answers = Answers(
            records: [
                "symbols.returns": .verdict(probability: 0.95),
                "symbols.shipping": .verdict(probability: 0.6),
            ],
            quality: .calibrated
        )

        let error = #expect(throws: DecisionError.self) {
            try Set<Team>.projection(in: answers, id: "symbols")
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "symbols.billing")
    }

    @Test("The plain set holds the options at or above one half")
    func readAtOneHalf() {
        #expect(Set<Team>.read(answered) == [.returns, .shipping])
        #expect(answered.members(atLeast: 0.5) == [.returns, .shipping])
    }

    @Test("A threshold keeps only the options the model is sure about")
    func readAtAThreshold() {
        #expect(Set<Team>.read(answered, minimumProbability: 0.9) == [.returns])
        #expect(Set<Team>.read(answered, minimumProbability: 0) == [.returns, .shipping, .billing])
    }

    @Test("An option with no answer says nothing")
    func missingOptionIsUncertain() {
        let thin = FanOut<Team>(verdicts: [.returns: Verdict(certain: true)])

        #expect(isClose(thin[.shipping].probability, 0.5))
        #expect(thin.members(atLeast: 0.5) == [.returns])
    }

    @Test("A plain set round-trips through its answers")
    func certainRoundTrips() throws {
        let projection = Set<Team>.certain([.returns, .billing])

        #expect(isClose(projection[.returns].probability, 1))
        #expect(isClose(projection[.billing].probability, 1))
        #expect(isClose(projection[.shipping].probability, 0))

        let answers = Set<Team>.answers(from: projection, id: "symbols")

        #expect(
            answers.records.keys.sorted()
                == ["symbols.billing", "symbols.returns", "symbols.shipping"]
        )
        #expect(answers.quality == .pointEstimate)

        let again = try Set<Team>.projection(in: answers, id: "symbols")

        #expect(Set<Team>.read(again) == [.returns, .billing])
    }

    @Test("The quality is the weakest of the verdicts")
    func qualityIsTheMinimum() {
        let mixed = FanOut<Team>(verdicts: [
            .returns: Verdict(probability: 0.9, quality: .calibrated),
            .shipping: Verdict(probability: 0.4, quality: .sampled(count: 8)),
            .billing: Verdict(probability: 0.2, quality: .pointEstimate),
        ])

        #expect(mixed.quality == .pointEstimate)
        #expect(answered.quality == .calibrated)
        // Every case is missing, so every answer is invented: a point estimate.
        #expect(FanOut<Team>(verdicts: [:]).quality == .pointEstimate)
    }

    @Test("A fan-out survives a round trip through JSON")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(answered)
        let again = try JSONDecoder().decode(FanOut<Team>.self, from: data)

        #expect(again.verdicts == answered.verdicts)
    }
}

extension FanOutTests {
    @Test("A partial fan-out claims no more quality than it holds")
    func partialFanOutQuality() {
        let partial = FanOut<Team>(verdicts: [
            .returns: Verdict(probability: 0.9, quality: .calibrated)
        ])
        #expect(partial.quality == .pointEstimate)
        #expect(partial[.shipping].probability == 0.5)

        var full: [Team: Verdict] = [:]
        for team in Team.allCases { full[team] = Verdict(probability: 0.9, quality: .calibrated) }
        #expect(FanOut(verdicts: full).quality == .calibrated)
    }
}
