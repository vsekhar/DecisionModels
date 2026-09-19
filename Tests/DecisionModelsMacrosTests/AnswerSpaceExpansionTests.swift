import Testing

@Suite("@Options and @Levels expansion")
struct AnswerSpaceExpansionTests {
    @Test("Every case carries the criterion it was given")
    func optionsWithCriteria() {
        expectExpansion(
            of: """
                @Options
                enum Team {
                    @Criterion("Exchanges and refunds", notFor: "Payment disputes")
                    case returns
                    @Criterion("Delivery issues")
                    case shipping
                }
                """,
            is: """
                enum Team {
                    case returns
                    case shipping
                }

                extension Team: ChoiceOption, CaseIterable, Askable, Decodable, Encodable {
                    typealias Projection = Choice<Team>

                    var optionID: String {
                        switch self {
                        case .returns:
                            "returns"
                        case .shipping:
                            "shipping"
                        }
                    }

                    var criterion: Criterion {
                        switch self {
                        case .returns:
                            Criterion("Exchanges and refunds", notFor: "Payment disputes")
                        case .shipping:
                            Criterion("Delivery issues")
                        }
                    }
                }
                """
        )
    }

    @Test("A case without a criterion says its name in words")
    func optionsWithoutCriteria() {
        expectExpansion(
            of: """
                @Options
                public enum Desk {
                    case billing
                    case everythingElse
                    case out_of_hours
                }
                """,
            is: """
                public enum Desk {
                    case billing
                    case everythingElse
                    case out_of_hours
                }

                extension Desk: ChoiceOption, CaseIterable, Askable, Decodable, Encodable {
                    public typealias Projection = Choice<Desk>

                    public var optionID: String {
                        switch self {
                        case .billing:
                            "billing"
                        case .everythingElse:
                            "everythingElse"
                        case .out_of_hours:
                            "out_of_hours"
                        }
                    }

                    public var criterion: Criterion {
                        switch self {
                        case .billing:
                            Criterion("billing")
                        case .everythingElse:
                            Criterion("everything else")
                        case .out_of_hours:
                            Criterion("out of hours")
                        }
                    }
                }
                """
        )
    }

    @Test("A scale compares by declaration order")
    func levels() {
        expectExpansion(
            of: """
                @Levels
                enum Severity {
                    @Criterion("Cosmetic; no impact to functionality")
                    case cosmetic
                    @Criterion("Broken or degraded feature, but a workaround exists")
                    case degraded
                    @Criterion("Blocking issue; no workaround exists")
                    case blocking
                }
                """,
            is: """
                enum Severity {
                    case cosmetic
                    case degraded
                    case blocking
                }

                extension Severity: RatingLevel, Askable, Decodable, Encodable, Comparable {
                    typealias Projection = Rating<Severity>

                    var optionID: String {
                        switch self {
                        case .cosmetic:
                            "cosmetic"
                        case .degraded:
                            "degraded"
                        case .blocking:
                            "blocking"
                        }
                    }

                    var criterion: Criterion {
                        switch self {
                        case .cosmetic:
                            Criterion("Cosmetic; no impact to functionality")
                        case .degraded:
                            Criterion("Broken or degraded feature, but a workaround exists")
                        case .blocking:
                            Criterion("Blocking issue; no workaround exists")
                        }
                    }

                    static func < (low: Self, high: Self) -> Bool {
                        allCases.firstIndex(of: low)! < allCases.firstIndex(of: high)!
                    }
                }
                """
        )
    }

    @Test("Several cases on one line each get a criterion")
    func casesOnOneLine() {
        expectExpansion(
            of: """
                @Options
                enum Answer {
                    case yes, no
                }
                """,
            is: """
                enum Answer {
                    case yes, no
                }

                extension Answer: ChoiceOption, CaseIterable, Askable, Decodable, Encodable {
                    typealias Projection = Choice<Answer>

                    var optionID: String {
                        switch self {
                        case .yes:
                            "yes"
                        case .no:
                            "no"
                        }
                    }

                    var criterion: Criterion {
                        switch self {
                        case .yes:
                            Criterion("yes")
                        case .no:
                            Criterion("no")
                        }
                    }
                }
                """
        )
    }

    @Test("A case named for a keyword keeps its backticks, and its id does not")
    func rawIdentifierCase() {
        expectExpansion(
            of: """
                @Options
                enum Fallback {
                    case `default`
                    case escalate
                }
                """,
            is: """
                enum Fallback {
                    case `default`
                    case escalate
                }

                extension Fallback: ChoiceOption, CaseIterable, Askable, Decodable, Encodable {
                    typealias Projection = Choice<Fallback>

                    var optionID: String {
                        switch self {
                        case .`default`:
                            "default"
                        case .escalate:
                            "escalate"
                        }
                    }

                    var criterion: Criterion {
                        switch self {
                        case .`default`:
                            Criterion("default")
                        case .escalate:
                            Criterion("escalate")
                        }
                    }
                }
                """
        )
    }
}
