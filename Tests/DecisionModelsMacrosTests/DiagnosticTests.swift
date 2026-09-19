import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("Macro diagnostics")
struct DiagnosticTests {
    @Test("An optional question must give a threshold")
    func optionalNeedsThreshold() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?")
                    var team: Team?
                }
                """,
            is: """
                struct Ticket {
                    var team: Team? {
                        get {
                            fatalError()
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "An optional property must give minimumConfidence. A threshold is a decision.",
                    line: 2,
                    column: 5
                )
            ]
        )
    }

    @Test("A let cannot take an answer")
    func letCannotAsk() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?")
                    let team: Team
                }
                """,
            is: """
                struct Ticket {
                    let team: Team
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Ask marks a var. A let cannot take the answer.",
                    line: 3,
                    column: 5
                )
            ]
        )
    }

    @Test("An implicitly unwrapped optional is not a question type")
    func noImplicitlyUnwrapped() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?", minimumConfidence: 0.7)
                    var team: Team!
                }
                """,
            is: """
                struct Ticket {
                    var team: Team! {
                        get {
                            fatalError()
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "Write `Team?`; @Ask does not take an implicitly unwrapped optional.",
                    line: 3,
                    column: 15
                )
            ]
        )
    }

    @Test("An observer cannot watch an answer")
    func observersAreOut() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?")
                    var team: Team {
                        didSet {
                            print(team)
                        }
                    }
                }
                """,
            is: """
                struct Ticket {
                    var team: Team {
                        didSet {
                            print(team)
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Ask does not take a property with a willSet or didSet observer.",
                    line: 3,
                    column: 20
                )
            ]
        )
    }

    /// The expansion machinery turns a marker on two bindings down before the
    /// macro runs, so `@Ask` never gets to say it. The test keeps a record of
    /// what the toolchain says in its place.
    @Test("One marker asks one question")
    func oneMarkerOneProperty() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?")
                    var team: Team, severity: Severity
                }
                """,
            is: """
                struct Ticket {
                    var team: Team, severity: Severity
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "accessor macro can only be applied to a single variable",
                    line: 2,
                    column: 5
                ),
                DiagnosticSpec(
                    message: "peer macro can only be applied to a single variable",
                    line: 2,
                    column: 5
                ),
            ]
        )
    }

    @Test("A decision asks at least one question")
    func decisionNeedsAQuestion() {
        expectExpansion(
            of: """
                @Decision
                struct Ticket {
                    var note: String = ""
                }
                """,
            is: """
                struct Ticket {
                    var note: String = ""

                    static var questions: Questionnaire {
                        Questionnaire([])
                    }

                    init(answers: Answers) throws {
                    }

                    var answers: Answers {
                        Answers(merging: [])
                    }

                    init() {
                    }
                }

                extension Ticket: Decision, Sendable, Askable {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Decision needs at least one @Ask property.",
                    line: 1,
                    column: 1
                )
            ]
        )
    }

    @Test("A computed property cannot take an answer")
    func computedCannotAsk() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?")
                    var team: Team { .returns }
                }
                """,
            is: """
                struct Ticket {
                    var team: Team { .returns }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Ask marks a stored property. This one computes its value.",
                    line: 3,
                    column: 20
                )
            ]
        )
    }

    @Test("A property with a value cannot take an answer")
    func initializedCannotAsk() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?")
                    var team: Team = .returns
                }
                """,
            is: """
                struct Ticket {
                    var team: Team = .returns
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "@Ask marks a property with no initial value. The answer gives the value.",
                    line: 3,
                    column: 20
                )
            ]
        )
    }

    @Test("A static property cannot take an answer")
    func staticCannotAsk() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?")
                    static var team: Team
                }
                """,
            is: """
                struct Ticket {
                    static var team: Team {
                        get {
                            fatalError()
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Ask marks an instance property.",
                    line: 3,
                    column: 5
                )
            ]
        )
    }

    @Test("A nested decision takes no branches")
    func nestedTakesNoBranches() {
        expectExpansion(
            of: """
                struct Intake {
                    @Ask(ifTrue: "The customer wants money back")
                    var bug: BugReport
                }
                """,
            is: """
                struct Intake {
                    var bug: BugReport {
                        get {
                            fatalError()
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Ask() asks a nested decision, which takes no ifTrue or ifFalse.",
                    line: 2,
                    column: 18
                )
            ]
        )
    }

    @Test("An enum decision needs its question text")
    func enumNeedsInstructions() {
        expectExpansion(
            of: """
                @Decision
                enum Command {
                    case stop
                }
                """,
            is: """
                enum Command {
                    case stop
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "@Decision on an enum needs the question text: "
                        + "@Decision(\"Which command...\").",
                    line: 1,
                    column: 1
                )
            ]
        )
    }

    @Test("A decision is a struct or an enum")
    func onlyStructsOrEnums() {
        expectExpansion(
            of: """
                @Decision
                class Ticket {
                }
                """,
            is: """
                class Ticket {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "A decision is a struct or an enum.",
                    line: 1,
                    column: 1
                )
            ]
        )
    }

    @Test("A stored property of a decision asks or holds a value")
    func unaskedProperty() {
        expectExpansion(
            of: """
                @Decision
                struct Ticket {
                    @Ask("Which team handles this ticket?")
                    var team: Team

                    var note: String
                }
                """,
            is: """
                struct Ticket {
                    var team: Team {
                        get {
                            Team.read($team)
                        }
                    }

                    var $team: Team.Projection

                    var note: String

                    static var questions: Questionnaire {
                        Questionnaire(
                            Team.questions(id: "team", Inquiry("Which team handles this ticket?"))
                        )
                    }

                    init(answers: Answers) throws {
                        $team = try Team.projection(in: answers, id: "team")
                    }

                    var answers: Answers {
                        Answers(merging: [
                            Team.answers(from: $team, id: "team"),
                        ])
                    }

                    init(team: Team) {
                        $team = Team.certain(team)
                    }
                }

                extension Ticket: Decision, Sendable, Askable {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "A stored property of a decision needs an @Ask marker or an initial value.",
                    line: 6,
                    column: 5
                )
            ]
        )
    }

    @Test("An answer space is an enum")
    func optionsNeedEnum() {
        expectExpansion(
            of: """
                @Options
                struct Team {
                    var name: String
                }
                """,
            is: """
                struct Team {
                    var name: String
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "@Options marks an enum.", line: 1, column: 1)
            ]
        )
    }

    @Test("An answer space needs a case")
    func optionsNeedACase() {
        expectExpansion(
            of: """
                @Options
                enum Team {
                }
                """,
            is: """
                enum Team {
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "@Options needs at least one case.", line: 1, column: 1)
            ]
        )
    }

    @Test("An answer space takes no associated values")
    func plainCasesOnly() {
        expectExpansion(
            of: """
                @Options
                enum Team {
                    case returns
                    case desk(String)
                }
                """,
            is: """
                enum Team {
                    case returns
                    case desk(String)
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "An answer space needs cases without associated values.",
                    line: 4,
                    column: 10
                )
            ]
        )
    }

    @Test("A scale needs two levels")
    func levelsNeedTwoCases() {
        expectExpansion(
            of: """
                @Levels
                enum Severity {
                    case blocking
                }
                """,
            is: """
                enum Severity {
                    case blocking
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "@Levels needs at least two levels.", line: 1, column: 1)
            ]
        )
    }

    @Test("A scale is an enum")
    func levelsNeedEnum() {
        expectExpansion(
            of: """
                @Levels
                struct Severity {
                    var value: Int
                }
                """,
            is: """
                struct Severity {
                    var value: Int
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "@Levels marks an enum.", line: 1, column: 1)
            ]
        )
    }

    @Test("A criterion belongs to a case")
    func criterionNeedsACase() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Criterion("Exchanges and refunds")
                    var team: Team
                }
                """,
            is: """
                struct Ticket {
                    var team: Team
                }
                """,
            diagnostics: [
                DiagnosticSpec(message: "@Criterion marks an enum case.", line: 2, column: 5)
            ]
        )
    }
}
