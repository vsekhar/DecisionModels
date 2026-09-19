import DecisionModels
import Testing

// The section 16 command example, written with the macros and nothing else.

@Options
enum Symbol {
    @Criterion("NVIDIA") case nvda
    @Criterion("Apple") case aapl
}

@Options
enum Window {
    @Criterion("The last day") case day
    @Criterion("The last month") case month
}

@Options
enum Direction {
    @Criterion("The price goes above the level") case above
    @Criterion("The price goes below the level") case below
}

@Decision
struct PlotArguments {
    @Ask("Which symbol?")
    var symbol: Symbol

    @Ask("Which window?")
    var window: Window
}

@Decision
struct AlertArguments {
    @Ask("Which symbol?")
    var symbol: Symbol

    @Ask("Above or below?")
    var direction: Direction
}

@Decision("Which command does the user want?")
enum Command: Equatable {
    @Criterion("Plot a chart of one symbol") case plot(PlotArguments)
    @Criterion("Set a price alert") case alert(AlertArguments)
    @Criterion("Do nothing") case cancel
}

/// A command nests in a decision like any other askable type.
@Decision
struct Assistant {
    @Ask("What should the assistant do?")
    var command: Command
}

/// A command whose cases all take no arguments still asks one choice.
@Decision("Which way does the user want to go?")
enum Heading {
    @Criterion("Go on") case forward
    case back
}

/// A public command, to prove the access modifiers travel. `FrontDesk` is the
/// public decision of `EndToEndTests`.
@Decision("What should the front desk do?")
public enum DeskCommand {
    @Criterion("Give the ticket to a desk") case handOff(FrontDesk)
    @Criterion("Answer it here") case keep
}

// The arguments compare by their plain values, so a test can name the whole
// command. The projections themselves hold probabilities.

extension PlotArguments: Equatable {
    public static func == (left: Self, right: Self) -> Bool {
        left.symbol == right.symbol && left.window == right.window
    }
}

extension AlertArguments: Equatable {
    public static func == (left: Self, right: Self) -> Bool {
        left.symbol == right.symbol && left.direction == right.direction
    }
}

/// What the fake answers for the whole command request.
private let plotAnswers = Answers(
    records: [
        "kind": .choice(
            reported: "plot",
            probabilities: ["plot": 0.88, "alert": 0.1, "cancel": 0.02],
            confidence: 0.85
        ),
        "plot.symbol": .choice(
            reported: "nvda", probabilities: ["nvda": 0.97, "aapl": 0.03], confidence: nil
        ),
        "plot.window": .choice(
            reported: "month", probabilities: ["day": 0.2, "month": 0.8], confidence: nil
        ),
        "alert.symbol": .choice(
            reported: "nvda", probabilities: ["nvda": 0.9, "aapl": 0.1], confidence: nil
        ),
        "alert.direction": .choice(
            reported: "above", probabilities: ["above": 0.6, "below": 0.4], confidence: nil
        ),
    ],
    quality: .calibrated
)

@Suite("Commands end to end")
struct CommandEndToEndTests {
    @Test("One request carries the choice and every case's arguments")
    func commandRunsAgainstAModel() async throws {
        let model = FakeModel(answers: plotAnswers)
        let session = DecisionSession(model: model)

        let command: Command = try await session.decide(about: "Chart NVDA for the last month.")

        #expect(
            model.requests.first?.questionnaire.specs.map(\.id)
                == ["kind", "plot.symbol", "plot.window", "alert.symbol", "alert.direction"]
        )
        #expect(command == .plot(PlotArguments(symbol: .nvda, window: .month)))
    }

    @Test("The choice question carries the criteria of the cases")
    func choiceCarriesCriteria() throws {
        let specs = Command.Answered.questions.specs

        #expect(specs[0].instructions == .text("Which command does the user want?"))
        guard case .choice(let options) = specs[0].kind else {
            Issue.record("The first question is not a choice.")
            return
        }
        #expect(options.map(\.id) == ["plot", "alert", "cancel"])
        #expect(options[0].criterion == Criterion("Plot a chart of one symbol"))
        #expect(options[2].criterion == Criterion("Do nothing"))
        #expect(Command.Kind.allCases.map(\.optionID) == ["plot", "alert", "cancel"])
    }

    @Test("respond gives the projection, with the confidence of the choice")
    func respondExposesTheChoice() async throws {
        let model = FakeModel(answers: plotAnswers)
        let session = DecisionSession(model: model)

        let response = try await session.respond(Command.self, about: "Chart NVDA.")

        #expect(isClose(response.decision.$kind.confidence, 0.85))
        #expect(response.decision.kind == .plot)
        #expect(response.decision.command == .plot(PlotArguments(symbol: .nvda, window: .month)))
        #expect(isClose(response.decision.$kind.probabilities[.alert] ?? 0, 0.1))
    }

    @Test("An unchosen case needs no answers")
    func unchosenArgumentsMayBeAbsent() async throws {
        let thin = Answers(
            records: [
                "kind": .choice(
                    reported: "plot",
                    probabilities: ["plot": 0.7, "alert": 0.2, "cancel": 0.1],
                    confidence: nil
                ),
                "plot.symbol": .choice(
                    reported: "aapl", probabilities: ["nvda": 0.1, "aapl": 0.9], confidence: nil
                ),
                "plot.window": .choice(
                    reported: "day", probabilities: ["day": 0.9, "month": 0.1], confidence: nil
                ),
            ],
            quality: .calibrated
        )
        let session = DecisionSession(model: FakeModel(answers: thin))

        let command = try await session.decide(Command.self, about: "Chart AAPL today.")

        #expect(command == .plot(PlotArguments(symbol: .aapl, window: .day)))
    }

    @Test("A case with no arguments needs no answers of its own")
    func caseWithoutArguments() async throws {
        let answers = Answers(
            records: [
                "kind": .choice(
                    reported: "cancel",
                    probabilities: ["plot": 0.05, "alert": 0.05, "cancel": 0.9],
                    confidence: nil
                )
            ],
            quality: .calibrated
        )
        let session = DecisionSession(model: FakeModel(answers: answers))

        let command = try await session.decide(Command.self, about: "Never mind.")

        #expect(command == .cancel)
    }

    @Test("A plain command round-trips through its answers")
    func plainValueRoundTrips() throws {
        let cancelled = Command.Answered(.cancel)

        #expect(cancelled.answers.records.keys.sorted() == ["kind"])
        #expect(isClose(cancelled.$kind.confidence, 1))
        #expect(try Command.Answered(answers: cancelled.answers).command == .cancel)

        let plotted = Command.Answered(.plot(PlotArguments(symbol: .aapl, window: .day)))

        #expect(
            plotted.answers.records.keys.sorted() == ["kind", "plot.symbol", "plot.window"]
        )
        #expect(
            try Command.Answered(answers: plotted.answers).command
                == .plot(PlotArguments(symbol: .aapl, window: .day))
        )
        #expect(Command.certain(.cancel).command == .cancel)
    }

    @Test("A command nests in another decision with dotted ids")
    func commandNestsInADecision() async throws {
        let answers = Answers(
            records: [
                "command.kind": .choice(
                    reported: "alert",
                    probabilities: ["plot": 0.1, "alert": 0.85, "cancel": 0.05],
                    confidence: nil
                ),
                "command.alert.symbol": .choice(
                    reported: "nvda", probabilities: ["nvda": 0.95, "aapl": 0.05], confidence: nil
                ),
                "command.alert.direction": .choice(
                    reported: "below", probabilities: ["above": 0.2, "below": 0.8], confidence: nil
                ),
            ],
            quality: .calibrated
        )
        let model = FakeModel(answers: answers)
        let session = DecisionSession(model: model)

        let assistant = try await session.decide(Assistant.self, about: "Tell me if NVDA drops.")

        #expect(
            model.requests.first?.questionnaire.specs.map(\.id) == [
                "command.kind", "command.plot.symbol", "command.plot.window",
                "command.alert.symbol", "command.alert.direction",
            ]
        )
        #expect(
            assistant.command == .alert(AlertArguments(symbol: .nvda, direction: .below))
        )
        #expect(assistant.$command.kind == .alert)
        #expect(
            Assistant(command: .cancel).answers.records.keys.sorted() == ["command.kind"]
        )
    }

    @Test("A public command keeps its access")
    func publicCommand() throws {
        #expect(DeskCommand.Answered.questions.specs.map(\.id) == ["kind", "handOff.desk"])

        let kept = DeskCommand.certain(.keep)
        let again = try DeskCommand.Answered(answers: kept.answers)

        #expect(kept.kind == .keep)
        #expect(again.kind == .keep)
        guard case .keep = DeskCommand.read(again) else {
            Issue.record("The command is not the one it was built from.")
            return
        }
    }

    @Test("A command whose cases take no arguments asks one question")
    func commandWithoutArguments() throws {
        #expect(Heading.Answered.questions.specs.map(\.id) == ["kind"])
        #expect(Heading.Kind.back.criterion == Criterion("back"))

        let heading = Heading.Answered(.back)

        #expect(heading.answers.records.keys.sorted() == ["kind"])
        #expect(try Heading.Answered(answers: heading.answers).command == .back)
    }
}
