import Foundation
import Testing

@testable import DecisionModels

@Suite("Codable round trips")
struct CodableRoundTripTests {
    func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// For types that are Codable but not Equatable, such as `Choice`.
    func decode<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    @Test("State encodes as plain JSON")
    func stateEncodesAsPlainJSON() throws {
        let state: State = [
            "name": "Ada",
            "orders": .number(3),
            "vip": .bool(true),
            "tags": ["new", "priority"],
            "note": .null,
        ]
        #expect(try json(state) == """
            {"name":"Ada","note":null,"orders":3,"tags":["new","priority"],"vip":true}
            """)
        #expect(try json(State.text("hello")) == "\"hello\"")
        #expect(try roundTrip(state) == state)
    }

    @Test("State decodes plain JSON")
    func stateDecodesPlainJSON() throws {
        let data = Data("""
            {"a":[1,true,null,"x"],"b":{"c":1.5}}
            """.utf8)
        let state = try JSONDecoder().decode(State.self, from: data)
        #expect(state == .object([
            "a": .array([.number(1), .bool(true), .null, .text("x")]),
            "b": .object(["c": .number(1.5)]),
        ]))
    }

    @Test("State can take any Encodable value")
    func stateFromEncodable() throws {
        let customer = Customer(name: "Ada", orders: 3, vip: true)
        let state = try State(encoding: customer)
        #expect(state == .object([
            "name": .text("Ada"),
            "orders": .number(3),
            "vip": .bool(true),
        ]))
        #expect(try roundTrip(state) == state)
    }

    @Test("State takes the three literal forms")
    func stateLiterals() {
        let text: State = "hello"
        let list: State = ["a", "b"]
        let object: State = ["key": "value"]
        #expect(text == .text("hello"))
        #expect(list == .array([.text("a"), .text("b")]))
        #expect(object == .object(["key": .text("value")]))
    }

    @Test("Criterion round-trips")
    func criterionRoundTrips() throws {
        let criterion = Criterion(
            "Exchanges and refunds",
            notFor: "Payment disputes",
            examples: ["wrong size"],
            signals: ["mentions a return label"]
        )
        #expect(try roundTrip(criterion) == criterion)
        #expect(try roundTrip(Criterion("plain")) == Criterion("plain"))
    }

    @Test("ProbabilityQuality round-trips")
    func probabilityQualityRoundTrips() throws {
        for quality: ProbabilityQuality in [.pointEstimate, .sampled(count: 5), .calibrated] {
            #expect(try roundTrip(quality) == quality)
        }
    }

    @Test("A question spec round-trips in every kind")
    func questionSpecRoundTrips() throws {
        let specs = [
            Choose("skill", "Which skill fits the request?", among: catalog).spec,
            Rate<Severity>("severity", "How severe is the issue?").spec,
            Verify("refund", "Does the customer want money back?", ifTrue: "Wants money").spec,
            Verify("plain", ["question": "Is the total right?", "focus": "arithmetic"]).spec,
        ]
        for spec in specs {
            #expect(try roundTrip(spec) == spec)
        }
        #expect(try roundTrip(Questionnaire(specs)) == Questionnaire(specs))
    }

    @Test("An answer record round-trips in every kind")
    func answerRecordRoundTrips() throws {
        let records: [AnswerRecord] = [
            .choice(reported: "returns", probabilities: ["returns": 0.9, "billing": 0.1], confidence: 0.88),
            .choice(reported: "returns", probabilities: ["returns": 1], confidence: nil),
            .rating(score: 1.3, probabilities: [0: 0, 1: 0.7, 2: 0.3], confidence: nil),
            .verdict(probability: 0.87),
        ]
        for record in records {
            #expect(try roundTrip(record) == record)
        }
        let answers = Answers(
            records: ["team": records[0], "severity": records[2], "refund": records[3]],
            quality: .sampled(count: 8)
        )
        #expect(try roundTrip(answers) == answers)
    }

    @Test("Typed answers round-trip")
    func typedAnswersRoundTrip() throws {
        let choice = Choice(
            distribution: Distribution(
                probabilities: [Team.returns: 0.9, .shipping: 0.06, .billing: 0.04],
                quality: .calibrated
            ),
            reported: .returns,
            reportedConfidence: 0.88
        )
        let decodedChoice = try decode(choice)
        #expect(decodedChoice.probabilities == choice.probabilities)
        #expect(decodedChoice.reported == .returns)
        #expect(decodedChoice.reportedConfidence == 0.88)
        #expect(decodedChoice.quality == .calibrated)

        let rating = Rating(
            distribution: Distribution(
                probabilities: [Severity.cosmetic: 0, .degraded: 0.7, .blocking: 0.3],
                quality: .calibrated
            ),
            score: 1.3
        )
        let decodedRating = try decode(rating)
        #expect(decodedRating.probabilities == rating.probabilities)
        #expect(decodedRating.score == 1.3)

        let verdict = Verdict(probability: 0.87, quality: .calibrated)
        #expect(try roundTrip(verdict) == verdict)
    }

    @Test("A distribution round-trips and hashes")
    func distributionRoundTrips() throws {
        let distribution = Distribution(
            probabilities: [Team.returns: 0.9, .shipping: 0.1],
            quality: .sampled(count: 4)
        )
        #expect(try roundTrip(distribution) == distribution)
        #expect(Set([distribution, distribution]).count == 1)
    }
}
