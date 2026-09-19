import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("@Decision expansion on an enum")
struct CommandExpansionTests {
    @Test("A command enum expands to its answer space and its projection")
    func command() {
        expectExpansion(
            of: """
                @Decision("Which command does the user want?")
                enum Command {
                    @Criterion("Plot a chart of one symbol")
                    case plot(PlotArguments)
                    @Criterion("Set a price alert")
                    case alert(AlertArguments)
                    @Criterion("Do nothing")
                    case cancel
                }
                """,
            is: """
                enum Command {
                    case plot(PlotArguments)
                    case alert(AlertArguments)
                    case cancel

                    enum Kind: ChoiceOption, CaseIterable, Askable, Codable {
                        case plot, alert, cancel
                        typealias Projection = Choice<Kind>
                        var optionID: String {
                            switch self {
                            case .plot:
                                "plot"
                            case .alert:
                                "alert"
                            case .cancel:
                                "cancel"
                            }
                        }
                        var criterion: Criterion {
                            switch self {
                            case .plot:
                                Criterion("Plot a chart of one symbol")
                            case .alert:
                                Criterion("Set a price alert")
                            case .cancel:
                                Criterion("Do nothing")
                            }
                        }
                    }

                    struct Answered: Decision {
                        var $kind: Choice<Kind>
                        var kind: Kind {
                            Kind.read($kind)
                        }
                        let command: Command
                        static var questions: Questionnaire {
                            Questionnaire(
                                Kind.questions(id: "kind", Inquiry("Which command does the user want?"))
                                    + PlotArguments.questions(id: "plot", Inquiry())
                                    + AlertArguments.questions(id: "alert", Inquiry())
                            )
                        }
                        init(answers: Answers) throws {
                            $kind = try Kind.projection(in: answers, id: "kind")
                            switch $kind.value {
                            case .plot:
                                command = .plot(try PlotArguments.projection(in: answers, id: "plot"))
                            case .alert:
                                command = .alert(try AlertArguments.projection(in: answers, id: "alert"))
                            case .cancel:
                                command = .cancel
                            }
                        }
                        var answers: Answers {
                            var parts = [Kind.answers(from: $kind, id: "kind")]
                            switch command {
                            case .plot(let arguments):
                                parts.append(PlotArguments.answers(from: arguments, id: "plot"))
                            case .alert(let arguments):
                                parts.append(AlertArguments.answers(from: arguments, id: "alert"))
                            case .cancel:
                                break
                            }
                            return Answers(merging: parts)
                        }
                        init(_ command: Command) {
                            self.command = command
                            switch command {
                            case .plot:
                                $kind = Kind.certain(.plot)
                            case .alert:
                                $kind = Kind.certain(.alert)
                            case .cancel:
                                $kind = Kind.certain(.cancel)
                            }
                        }
                    }

                    typealias Projection = Answered

                    static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec] {
                        Answered.questions(id: id, inquiry)
                    }

                    static func projection(in answers: Answers, id: String) throws -> Answered {
                        try Answered.projection(in: answers, id: id)
                    }

                    static func read(_ projection: Answered) -> Command {
                        projection.command
                    }

                    static func answers(from projection: Answered, id: String) -> Answers {
                        Answered.answers(from: projection, id: id)
                    }

                    static func certain(_ value: Command) -> Answered {
                        Answered(value)
                    }
                }

                extension Command: Askable, Sendable {
                }
                """
        )
    }

    @Test("A case takes its arguments without a label")
    func labelledPayload() {
        expectExpansion(
            of: """
                @Decision("Which command does the user want?")
                enum Command {
                    case plot(arguments: PlotArguments)
                }
                """,
            is: """
                enum Command {
                    case plot(arguments: PlotArguments)
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "A command case takes its arguments without a label: "
                        + "case plot(PlotArguments).",
                    line: 3,
                    column: 10
                )
            ]
        )
    }

    @Test("A case takes one set of arguments at most")
    func twoPayloads() {
        expectExpansion(
            of: """
                @Decision("Which command does the user want?")
                enum Command {
                    case plot(PlotArguments, AlertArguments)
                }
                """,
            is: """
                enum Command {
                    case plot(PlotArguments, AlertArguments)
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "A command case takes one decision as its arguments, or none at all.",
                    line: 3,
                    column: 10
                )
            ]
        )
    }

    @Test("A command enum takes no raw value")
    func rawValues() {
        expectExpansion(
            of: """
                @Decision("Which command does the user want?")
                enum Command: String {
                    case cancel
                }
                """,
            is: """
                enum Command: String {
                    case cancel
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "A command enum takes no raw value. The case names are the wire ids.",
                    line: 2,
                    column: 15
                )
            ]
        )
    }

    @Test("A command enum needs a case")
    func noCases() {
        expectExpansion(
            of: """
                @Decision("Which command does the user want?")
                enum Command {
                }
                """,
            is: """
                enum Command {
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Decision on an enum needs at least one case.",
                    line: 1,
                    column: 1
                )
            ]
        )
    }

    // A missing question text is `DiagnosticTests.enumNeedsInstructions`.

    @Test("The question text must say something")
    func emptyInstructions() {
        expectExpansion(
            of: """
                @Decision(.null)
                enum Command {
                    case cancel
                }
                """,
            is: """
                enum Command {
                    case cancel
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "The question text of @Decision on an enum cannot be empty.",
                    line: 1,
                    column: 1
                )
            ]
        )
    }

    @Test("An empty text asks nothing either")
    func emptyStringInstructions() {
        expectExpansion(
            of: """
                @Decision("")
                enum Command {
                    case cancel
                }
                """,
            is: """
                enum Command {
                    case cancel
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "The question text of @Decision on an enum cannot be empty.",
                    line: 1,
                    column: 1
                )
            ]
        )
    }

    @Test("A struct takes no question text of its own")
    func structTakesNoInstructions() {
        expectExpansion(
            of: """
                @Decision("Which team handles this ticket?")
                struct Ticket {
                    @Ask("Which team handles this ticket?")
                    var team: Team
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
                        "@Decision on a struct takes no question text; each @Ask carries its own.",
                    line: 1,
                    column: 1
                )
            ]
        )
    }
}
