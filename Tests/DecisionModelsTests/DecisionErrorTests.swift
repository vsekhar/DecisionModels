import Testing

@testable import DecisionModels

@Suite("Errors")
struct DecisionErrorTests {
    struct Network: Error {}

    @Test("Every case exists and carries its payload")
    func casesCarryTheirPayloads() {
        let errors: [DecisionError] = [
            .unavailable(.notConfigured("no key")),
            .unsupported(.tooManyOptions(id: "team", count: 300, limit: 255)),
            .unsupported(.structuredCriteria),
            .invalidQuestion(id: "team", reason: "no options"),
            .contextSizeExceeded(limit: 64_000, estimated: 70_000),
            .rateLimited(retryAfter: .seconds(2)),
            .overloaded,
            .unauthorized,
            .timeout,
            .refused,
            .guardrailViolation,
            .insufficientProbabilityQuality(got: .pointEstimate, required: .calibrated),
            .malformedResponse("bad json"),
            .transport(Network()),
        ]
        #expect(errors.count == 14)

        if case .unsupported(.tooManyOptions(let id, let count, let limit)) = errors[1] {
            #expect(id == "team")
            #expect(count == 300)
            #expect(limit == 255)
        } else {
            Issue.record("The case did not match.")
        }

        if case .transport(let underlying) = errors[13] {
            #expect(underlying is Network)
        } else {
            Issue.record("The case did not match.")
        }
    }

    @Test("A malformed response says which question broke")
    func malformedResponseNamesTheQuestion() {
        let answers = Answers(
            records: ["team": .verdict(probability: 0.5)],
            quality: .calibrated
        )
        do {
            _ = try answers.choice("team", as: Team.self)
            Issue.record("The read should have thrown.")
        } catch let error as DecisionError {
            guard case .malformedResponse(let reason) = error else {
                Issue.record("The error is not a malformed response.")
                return
            }
            #expect(reason.contains("team"))
        } catch {
            Issue.record("The error is not a DecisionError.")
        }
    }
}
