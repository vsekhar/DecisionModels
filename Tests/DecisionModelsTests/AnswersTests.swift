import Testing

@testable import DecisionModels

@Suite("Answers")
struct AnswersTests {
    let answers = Answers(
        records: [
            "team": .choice(
                reported: "returns",
                probabilities: ["returns": 0.91, "shipping": 0.06, "billing": 0.03],
                confidence: 0.88
            ),
            "severity": .rating(
                score: 1.3,
                probabilities: [0: 0, 1: 0.7, 2: 0.3],
                confidence: nil
            ),
            "requestsRefund": .verdict(probability: 0.87),
            "skill": .choice(
                reported: "refund",
                probabilities: ["search": 0.1, "refund": 0.8, "escalate": 0.1],
                confidence: nil
            ),
        ],
        quality: .calibrated
    )

    @Test("A question value reads its own answer")
    func subscriptReadsTypedAnswers() throws {
        let skill = Choose("skill", "Which skill fits the request?", among: catalog)
        let severity = Rate<Severity>("severity", "How severe is the issue?")
        let refund = Verify("requestsRefund", "Does the customer ask for a refund?")

        #expect(try answers[skill].value == catalog[1])
        #expect(try isClose(answers[skill][catalog[1]], 0.8))
        #expect(try answers[severity].value == .degraded)
        #expect(try isClose(answers[severity].score, 1.3))
        #expect(try answers[refund].value)
        #expect(try answers[refund].isTrue(atLeast: 0.3))
        #expect(try !answers[refund].isTrue(atLeast: 0.9))
    }

    @Test("A run-time option list maps ids back to values")
    func choiceKeepsItsOptionList() throws {
        let skill = Choose("skill", "Which skill fits the request?", among: catalog)
        let choice = try answers[skill]
        #expect(choice.probabilities.count == catalog.count)
        #expect(choice.reported == catalog[1])
        #expect(choice.value.id == "refund")
    }

    @Test("The response quality reaches every answer")
    func qualityPropagates() throws {
        let severity = Rate<Severity>("severity", "How severe is the issue?")
        #expect(try answers[severity].quality == .calibrated)
        #expect(try answers.choice("team", as: Team.self).quality == .calibrated)
        #expect(try answers.verdict("requestsRefund").quality == .calibrated)
    }

    @Test("An enum reads its answer through CaseIterable")
    func enumHelpers() throws {
        let team = try answers.choice("team", as: Team.self)
        #expect(team.value == .returns)
        #expect(team.confidence == 0.88)
        #expect(isClose(team[.shipping], 0.06))

        let severity = try answers.rating("severity", as: Severity.self)
        #expect(severity.value == .degraded)
        #expect(severity.legend[.blocking]?.summary == "Blocking issue; no workaround exists")

        #expect(try isClose(answers.verdict("requestsRefund").probability, 0.87))
    }

    @Test("A missing id throws")
    func missingIDThrows() {
        #expect(throws: DecisionError.self) {
            try answers.verdict("absent")
        }
        #expect(throws: DecisionError.self) {
            try answers[Verify("absent", "Is anything there?")]
        }
        #expect(throws: DecisionError.self) {
            try answers.choice("absent", as: Team.self)
        }
    }

    @Test("An unknown option id throws")
    func unknownOptionThrows() {
        let strange = Answers(
            records: ["team": .choice(
                reported: "legal",
                probabilities: ["legal": 1],
                confidence: nil
            )],
            quality: .calibrated
        )
        #expect(throws: DecisionError.self) {
            try strange.choice("team", as: Team.self)
        }
        let wrongLevel = Answers(
            records: ["severity": .rating(score: 9, probabilities: [9: 1], confidence: nil)],
            quality: .calibrated
        )
        #expect(throws: DecisionError.self) {
            try wrongLevel.rating("severity", as: Severity.self)
        }
    }

    @Test("The wrong kind of record throws")
    func wrongKindThrows() {
        #expect(throws: DecisionError.self) {
            try answers.verdict("team")
        }
        #expect(throws: DecisionError.self) {
            try answers.rating("team", as: Severity.self)
        }
        #expect(throws: DecisionError.self) {
            try answers.choice("requestsRefund", as: Team.self)
        }
    }

    @Test("A prefix goes on and comes off")
    func prefixedAndScopedRoundTrip() {
        let nested = answers.prefixed("bug")
        #expect(nested.records["bug.severity"] != nil)
        #expect(nested.records["severity"] == nil)
        #expect(nested.scoped(to: "bug") == answers)
        #expect(nested.scoped(to: "other").records.isEmpty)
    }

    @Test("A nested decision reads through prefix and scope")
    func nestedQuestionsRoundTrip() throws {
        let severity = Rate<Severity>("severity", "How severe is the issue?")
        var inner = Questionnaire()
        inner.add(severity)

        let outer = inner.prefixed("bug")
        #expect(outer.specs.map(\.id) == ["bug.severity"])

        let response = Answers(
            records: [outer.specs[0].id: .rating(
                score: 1.3,
                probabilities: [0: 0, 1: 0.7, 2: 0.3],
                confidence: nil
            )],
            quality: .calibrated
        )
        #expect(throws: DecisionError.self) { try response[severity] }
        #expect(try response.scoped(to: "bug")[severity].value == .degraded)
    }

    @Test("An answer round-trips through its record")
    func answerRebuildsFromItsRecord() throws {
        let team = try answers.choice("team", as: Team.self)
        let again = try Answers(records: ["team": team.record], quality: .calibrated)
            .choice("team", as: Team.self)
        #expect(again.value == team.value)
        #expect(again.confidence == team.confidence)
        #expect(again.probabilities == team.probabilities)
    }
}

extension AnswersTests {
    @Test("Merging joins the records of several parts")
    func mergingJoinsRecords() {
        let merged = Answers(merging: [
            Answers(records: ["team": .verdict(probability: 0.9)], quality: .calibrated),
            Answers(records: ["refund": .verdict(probability: 0.1)], quality: .calibrated),
        ])

        #expect(merged.records.keys.sorted() == ["refund", "team"])
        #expect(merged.quality == .calibrated)
    }

    @Test("Merging keeps the lowest quality")
    func mergingTakesTheLowestQuality() {
        let merged = Answers(merging: [
            Answers(records: ["a": .verdict(probability: 1)], quality: .calibrated),
            Answers(records: ["b": .verdict(probability: 1)], quality: .sampled(count: 8)),
            Answers(records: ["c": .verdict(probability: 1)], quality: .pointEstimate),
        ])

        #expect(merged.quality == .pointEstimate)
    }

    @Test("A later part wins on a clash")
    func mergingLaterPartWins() {
        let merged = Answers(merging: [
            Answers(records: ["a": .verdict(probability: 0.1)], quality: .calibrated),
            Answers(records: ["a": .verdict(probability: 0.9)], quality: .calibrated),
        ])

        #expect(merged.records["a"] == .verdict(probability: 0.9))
    }

    @Test("Merging nothing gives an empty calibrated set")
    func mergingNothing() {
        let merged = Answers(merging: [])

        #expect(merged.records.isEmpty)
        #expect(merged.quality == .calibrated)
    }
}
