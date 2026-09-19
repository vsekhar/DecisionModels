import Testing

@Suite("@Decision expansion")
struct DecisionExpansionTests {
    @Test("The section 4 struct expands as DESIGN.md section 12 says")
    func sectionFour() {
        expectExpansion(
            of: """
                @Decision
                struct TicketTriage {
                    @Ask("Which team handles this ticket?")
                    var team: Team

                    @Ask("How severe is the reported issue?")
                    var severity: Severity

                    @Ask("Does the customer ask for a refund?")
                    var requestsRefund: Bool

                    var needsHuman: Bool {
                        $team.confidence < 0.5
                    }
                }
                """,
            is: """
                struct TicketTriage {
                    var team: Team {
                        get {
                            Team.read($team)
                        }
                    }

                    var $team: Team.Projection
                    var severity: Severity {
                        get {
                            Severity.read($severity)
                        }
                    }

                    var $severity: Severity.Projection
                    var requestsRefund: Bool {
                        get {
                            Bool.read($requestsRefund)
                        }
                    }

                    var $requestsRefund: Bool.Projection

                    var needsHuman: Bool {
                        $team.confidence < 0.5
                    }

                    static var questions: Questionnaire {
                        Questionnaire(
                            Team.questions(id: "team", Inquiry("Which team handles this ticket?"))
                                + Severity.questions(id: "severity", Inquiry("How severe is the reported issue?"))
                                + Bool.questions(id: "requestsRefund", Inquiry("Does the customer ask for a refund?"))
                        )
                    }

                    init(answers: Answers) throws {
                        $team = try Team.projection(in: answers, id: "team")
                        $severity = try Severity.projection(in: answers, id: "severity")
                        $requestsRefund = try Bool.projection(in: answers, id: "requestsRefund")
                    }

                    var answers: Answers {
                        Answers(merging: [
                            Team.answers(from: $team, id: "team"),
                            Severity.answers(from: $severity, id: "severity"),
                            Bool.answers(from: $requestsRefund, id: "requestsRefund"),
                        ])
                    }

                    init(team: Team, severity: Severity, requestsRefund: Bool) {
                        $team = Team.certain(team)
                        $severity = Severity.certain(severity)
                        $requestsRefund = Bool.certain(requestsRefund)
                    }
                }

                extension TicketTriage: Decision, Sendable, Askable {
                }
                """
        )
    }

    @Test("A yes or no question carries what each side means")
    func branchForm() {
        expectExpansion(
            of: """
                @Decision
                struct Refund {
                    @Ask("Does the customer ask for a refund?",
                         ifTrue: "The customer wants money back",
                         ifFalse: Criterion("The customer wants a fix"))
                    var requestsRefund: Bool
                }
                """,
            is: """
                struct Refund {
                    var requestsRefund: Bool {
                        get {
                            Bool.read($requestsRefund)
                        }
                    }

                    var $requestsRefund: Bool.Projection

                    static var questions: Questionnaire {
                        Questionnaire(
                            Bool.questions(id: "requestsRefund", Inquiry("Does the customer ask for a refund?", ifTrue: "The customer wants money back", ifFalse: Criterion("The customer wants a fix")))
                        )
                    }

                    init(answers: Answers) throws {
                        $requestsRefund = try Bool.projection(in: answers, id: "requestsRefund")
                    }

                    var answers: Answers {
                        Answers(merging: [
                            Bool.answers(from: $requestsRefund, id: "requestsRefund"),
                        ])
                    }

                    init(requestsRefund: Bool) {
                        $requestsRefund = Bool.certain(requestsRefund)
                    }
                }

                extension Refund: Decision, Sendable, Askable {
                }
                """
        )
    }

    @Test("Structured instructions travel verbatim")
    func structuredInstructions() {
        expectExpansion(
            of: """
                @Decision
                struct Invoice {
                    @Ask(instructions: ["question": "Do the totals match?", "focus": "arithmetic only"])
                    var totalsMatch: Bool
                }
                """,
            is: """
                struct Invoice {
                    var totalsMatch: Bool {
                        get {
                            Bool.read($totalsMatch)
                        }
                    }

                    var $totalsMatch: Bool.Projection

                    static var questions: Questionnaire {
                        Questionnaire(
                            Bool.questions(id: "totalsMatch", Inquiry(["question": "Do the totals match?", "focus": "arithmetic only"]))
                        )
                    }

                    init(answers: Answers) throws {
                        $totalsMatch = try Bool.projection(in: answers, id: "totalsMatch")
                    }

                    var answers: Answers {
                        Answers(merging: [
                            Bool.answers(from: $totalsMatch, id: "totalsMatch"),
                        ])
                    }

                    init(totalsMatch: Bool) {
                        $totalsMatch = Bool.certain(totalsMatch)
                    }
                }

                extension Invoice: Decision, Sendable, Askable {
                }
                """
        )
    }

    @Test("A nested decision and an optional expand together")
    func nestedAndOptional() {
        expectExpansion(
            of: """
                @Decision
                public struct Intake {
                    @Ask("Which team handles this ticket?", minimumConfidence: 0.7)
                    public var team: Team?

                    @Ask()
                    public var bug: BugReport
                }
                """,
            is: """
                public struct Intake {
                    public var team: Team? {
                        get {
                            Team?.read($team, minimumConfidence: 0.7)
                        }
                    }

                    public var $team: Team?.Projection
                    public var bug: BugReport {
                        get {
                            BugReport.read($bug)
                        }
                    }

                    public var $bug: BugReport.Projection

                    public static var questions: Questionnaire {
                        Questionnaire(
                            Team?.questions(id: "team", Inquiry("Which team handles this ticket?"))
                                + BugReport.questions(id: "bug", Inquiry())
                        )
                    }

                    public init(answers: Answers) throws {
                        $team = try Team?.projection(in: answers, id: "team")
                        $bug = try BugReport.projection(in: answers, id: "bug")
                    }

                    public var answers: Answers {
                        Answers(merging: [
                            Team?.answers(from: $team, id: "team"),
                            BugReport.answers(from: $bug, id: "bug"),
                        ])
                    }

                    public init(team: Team?, bug: BugReport) {
                        $team = Team?.certain(team)
                        $bug = BugReport.certain(bug)
                    }
                }

                extension Intake: Decision, Sendable, Askable {
                }
                """
        )
    }

    @Test("A property named for a keyword keeps its backticks")
    func rawIdentifier() {
        expectExpansion(
            of: """
                @Decision
                struct Routing {
                    @Ask("Which team handles this ticket?")
                    var `default`: Team
                }
                """,
            is: """
                struct Routing {
                    var `default`: Team {
                        get {
                            Team.read($default)
                        }
                    }

                    var $default: Team.Projection

                    static var questions: Questionnaire {
                        Questionnaire(
                            Team.questions(id: "default", Inquiry("Which team handles this ticket?"))
                        )
                    }

                    init(answers: Answers) throws {
                        $default = try Team.projection(in: answers, id: "default")
                    }

                    var answers: Answers {
                        Answers(merging: [
                            Team.answers(from: $default, id: "default"),
                        ])
                    }

                    init(`default`: Team) {
                        $default = Team.certain(`default`)
                    }
                }

                extension Routing: Decision, Sendable, Askable {
                }
                """
        )
    }
}
