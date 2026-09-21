import Testing

@testable import DecisionModels

/// The session completes every record against the question that asked for it,
/// so `AnswerRecord.confidence` on a returned record is exact.
@Suite("Resolved answers")
struct ResolvedAnswersTests {
    let severity = Rate<Severity>("severity", "How severe is the issue?")
    let skill = Choose("skill", "Which skill fits the request?", among: catalog)
    let refund = Verify("refund", "Does the customer ask for a refund?")

    /// A session over a model that answers with these records.
    func session(_ records: [String: AnswerRecord]) -> DecisionSession {
        DecisionSession(
            model: FakeModel(answers: Answers(records: records, quality: .calibrated))
        )
    }

    @Test("A rating that leaves out a level gets it back at zero")
    func ratingGainsTheAbsentLevel() async throws {
        let session = session([
            "severity": .rating(score: 0.3, probabilities: [0: 0.7, 1: 0.3], confidence: nil)
        ])

        let got = try await session.decide(Questionnaire { severity }, about: "a report")

        let record = try #require(got.records["severity"])
        #expect(
            record == .rating(score: 0.3, probabilities: [0: 0.7, 1: 0.3, 2: 0], confidence: nil)
        )
        #expect(isClose(record.confidence, 0.5417, within: 0.001))
        let answer = try got[severity]
        #expect(isClose(answer.confidence, record.confidence, within: 1e-9))
        // The gap this closes: the same record on its own reads the scale as
        // two levels and reports a sixth of the confidence.
        let bare = AnswerRecord.rating(score: 0.3, probabilities: [0: 0.7, 1: 0.3], confidence: nil)
        #expect(isClose(bare.confidence, 0.0835, within: 0.001))
    }

    @Test("A choice that leaves out an option gets it back at zero")
    func choiceGainsTheAbsentOption() async throws {
        let session = session([
            "skill": .choice(
                reported: "refund", probabilities: ["refund": 0.7, "search": 0.3], confidence: nil
            )
        ])

        let got = try await session.decide(Questionnaire { skill }, about: "Give my money back")

        let record = try #require(got.records["skill"])
        #expect(
            record == .choice(
                reported: "refund",
                probabilities: ["refund": 0.7, "search": 0.3, "escalate": 0],
                confidence: nil
            )
        )
        #expect(isClose(record.confidence, 0.4439, within: 0.001))
        let answer = try got[skill]
        #expect(isClose(answer.confidence, record.confidence, within: 1e-9))
        let bare = AnswerRecord.choice(
            reported: "refund", probabilities: ["refund": 0.7, "search": 0.3], confidence: nil
        )
        #expect(isClose(bare.confidence, 0.1189, within: 0.001))
    }

    @Test("The provider's numbers are kept, not rescaled")
    func numbersAreKept() async throws {
        let session = session([
            "skill": .choice(
                reported: "refund", probabilities: ["refund": 0.6, "search": 0.6], confidence: nil
            )
        ])

        let got = try await session.decide(Questionnaire { skill }, about: "Give my money back")

        let record = try #require(got.records["skill"])
        guard case .choice(_, let probabilities, _) = record else {
            Issue.record("The record is not a choice.")
            return
        }
        #expect(probabilities == ["refund": 0.6, "search": 0.6, "escalate": 0])
        // The typed answer scales the same numbers to sum to one.
        let answer = try got[skill]
        #expect(isClose(answer[catalog[1]], 0.5))
        #expect(isClose(answer[catalog[0]], 0.5))
    }

    @Test("A verdict passes through the same check")
    func verdictPassesThrough() async throws {
        let session = session(["refund": .verdict(probability: 0.87)])

        let got = try await session.decide(Questionnaire { refund }, about: "a report")

        let record = try #require(got.records["refund"])
        #expect(record == .verdict(probability: 0.87))
        #expect(isClose(record.confidence, 0.74))
    }

    @Test("The typed path returns complete records too")
    func typedPathReturnsCompleteRecords() async throws {
        var records = triageAnswers.records
        records["severity"] = .rating(score: 1.3, probabilities: [1: 0.7, 2: 0.3], confidence: nil)
        let session = session(records)

        let response: DecisionResponse<TicketTriage> = try await session.respond(about: "broken")

        #expect(
            response.answers.records["severity"]
                == .rating(score: 1.3, probabilities: [0: 0, 1: 0.7, 2: 0.3], confidence: nil)
        )
        #expect(response.decision.severity == .degraded)
    }

    // MARK: Malformed records

    /// Runs a call that must throw `malformedResponse`, and checks that the
    /// reason names the question and every other word the case is about.
    func expectMalformed(
        _ id: String,
        contains words: [String] = [],
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            Issue.record("Expected a malformed response for question \(id).")
        } catch let error as DecisionError {
            guard case .malformedResponse(let reason) = error else {
                Issue.record("Expected malformedResponse, got \(error)")
                return
            }
            #expect(reason.contains(id))
            for word in words { #expect(reason.contains(word)) }
        } catch {
            Issue.record("Expected malformedResponse, got \(error)")
        }
    }

    @Test("A probability key that is not an option throws")
    func unknownProbabilityKey() async {
        let session = session([
            "skill": .choice(
                reported: "refund", probabilities: ["refund": 0.7, "upgrade": 0.3], confidence: nil
            )
        ])
        await expectMalformed("skill", contains: ["upgrade"]) {
            _ = try await session.decide(Questionnaire { skill }, about: "a report")
        }
    }

    @Test("A reported id that is not an option throws")
    func unknownReportedID() async {
        let session = session([
            "skill": .choice(
                reported: "upgrade", probabilities: ["refund": 1], confidence: nil
            )
        ])
        await expectMalformed("skill", contains: ["upgrade"]) {
            _ = try await session.decide(Questionnaire { skill }, about: "a report")
        }
    }

    @Test("A level index off the scale throws")
    func levelIndexOffTheScale() async {
        let session = session([
            "severity": .rating(score: 0.3, probabilities: [0: 0.7, 3: 0.3], confidence: nil)
        ])
        await expectMalformed("severity", contains: ["3"]) {
            _ = try await session.decide(Questionnaire { severity }, about: "a report")
        }
    }

    @Test("A negative probability throws")
    func negativeProbability() async {
        let session = session([
            "severity": .rating(score: 0.3, probabilities: [0: -0.1, 1: 1.1], confidence: nil)
        ])
        await expectMalformed("severity") {
            _ = try await session.decide(Questionnaire { severity }, about: "a report")
        }
    }

    @Test("A reported confidence outside 0...1 throws")
    func reportedConfidenceOffRange() async {
        let session = session([
            "severity": .rating(score: 1.3, probabilities: [0: 0, 1: 0.7, 2: 0.3], confidence: 1.5)
        ])
        await expectMalformed("severity", contains: ["confidence"]) {
            _ = try await session.decide(Questionnaire { severity }, about: "a report")
        }
    }

    @Test("A verdict probability outside 0...1 throws")
    func verdictProbabilityOffRange() async {
        let session = session(["refund": .verdict(probability: 1.5)])
        await expectMalformed("refund") {
            _ = try await session.decide(Questionnaire { refund }, about: "a report")
        }
    }

    @Test("A kind that does not match the question throws")
    func kindMismatch() async {
        let session = session(["severity": .verdict(probability: 0.5)])
        await expectMalformed("severity", contains: ["rating", "verdict"]) {
            _ = try await session.decide(Questionnaire { severity }, about: "a report")
        }
    }

    @Test("A question with no record stays absent")
    func questionWithNoRecord() async throws {
        let session = session(["refund": .verdict(probability: 0.87)])

        let got = try await session.decide(
            Questionnaire { severity; refund }, about: "a report"
        )

        #expect(got.records.keys.sorted() == ["refund"])
        #expect(isClose(try got[refund].confidence, 0.74))
        // The gap passes through, and the read that needs it says so.
        let error = #expect(throws: DecisionError.self) {
            _ = try got[severity]
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "severity")
    }

    @Test("A record with no question throws")
    func recordWithNoQuestion() async {
        let session = session([
            "severity": .rating(score: 1.3, probabilities: [0: 0, 1: 0.7, 2: 0.3], confidence: nil),
            "extra": .verdict(probability: 0.5),
        ])
        await expectMalformed("extra") {
            _ = try await session.decide(Questionnaire { severity }, about: "a report")
        }
    }

    @Test("Two options with one id are an invalid question at the wire level")
    func duplicateOptionIDs() {
        let spec = QuestionSpec(
            id: "skill",
            instructions: "Which skill fits the request?",
            kind: .choice(options: [
                .init(id: "refund", criterion: "Give money back"),
                .init(id: "refund", criterion: "Refund, version two"),
            ])
        )
        let record = AnswerRecord.choice(
            reported: "refund", probabilities: ["refund": 1], confidence: nil
        )
        let error = #expect(throws: DecisionError.self) {
            try AnswerReader.resolved(record, against: spec)
        }
        guard case .invalidQuestion(let id, _) = error else {
            Issue.record("Expected invalidQuestion, got \(String(describing: error))")
            return
        }
        #expect(id == "skill")
    }

    @Test("The resolver leaves a complete record alone")
    func completeRecordIsUnchanged() throws {
        let record = AnswerRecord.rating(
            score: 1.3, probabilities: [0: 0, 1: 0.7, 2: 0.3], confidence: 0.9
        )
        #expect(try AnswerReader.resolved(record, against: severity.spec) == record)
    }
}
