import DecisionModels
import Testing

// A set property, written with the macros and nothing else. See DESIGN.md
// section 16.

@Options
enum Ticker {
    @Criterion("NVIDIA") case nvda
    @Criterion("the S&P 500 ETF") case spy
    @Criterion("Bitcoin") case btc
}

@Decision
struct Watchlist {
    @Ask("Does the request mention {option}?")
    var symbols: Set<Ticker>
}

/// The same question, read at a higher bar.
///
/// A `minimumProbability` on a property that is not a set fails to
/// type-check, because only `Set` has the two-argument read. That is the
/// diagnostic the design asks for, and a compile error cannot be a test case,
/// so nothing below tries it.
@Decision
struct StrictWatchlist {
    @Ask("Does the request mention {option}?", minimumProbability: 0.9)
    var symbols: Set<Ticker>
}

/// What the fake answers for the watchlist: one verdict per case.
let watchlistAnswers = Answers(
    records: [
        "symbols.nvda": .verdict(probability: 0.95),
        "symbols.spy": .verdict(probability: 0.6),
        "symbols.btc": .verdict(probability: 0.1),
    ],
    quality: .calibrated
)

@Suite("A set of options end to end")
struct FanOutEndToEndTests {
    @Test("A set property asks one question per case in one request")
    func fanOutRunsThroughASession() async throws {
        let model = FakeModel(answers: watchlistAnswers)
        let session = DecisionSession(model: model)

        let watchlist: Watchlist = try await session.decide(about: "Buy NVDA and some SPY.")

        #expect(watchlist.symbols == [.nvda, .spy])
        #expect(isClose(watchlist.$symbols[.nvda].probability, 0.95))
        #expect(isClose(watchlist.$symbols[.btc].probability, 0.1))

        let specs = try #require(model.requests.first?.questionnaire.specs)
        #expect(specs.map(\.id) == ["symbols.nvda", "symbols.spy", "symbols.btc"])
        #expect(specs.map(\.instructions) == [
            .text("Does the request mention NVIDIA?"),
            .text("Does the request mention the S&P 500 ETF?"),
            .text("Does the request mention Bitcoin?"),
        ])
    }

    @Test("A threshold keeps only the options the model is sure about")
    func thresholdNarrowsTheSet() async throws {
        let session = DecisionSession(model: FakeModel(answers: watchlistAnswers))

        let watchlist = try await session.decide(
            StrictWatchlist.self,
            about: "Buy NVDA and some SPY."
        )

        #expect(watchlist.symbols == [.nvda])
        #expect(isClose(watchlist.$symbols[.spy].probability, 0.6))
    }

    @Test("The plain-value initializer round-trips through answers")
    func plainSetRoundTrips() throws {
        let watchlist = Watchlist(symbols: [.nvda])

        #expect(watchlist.symbols == [.nvda])
        #expect(isClose(watchlist.$symbols[.nvda].probability, 1))
        #expect(isClose(watchlist.$symbols[.spy].probability, 0))
        #expect(
            watchlist.answers.records.keys.sorted()
                == ["symbols.btc", "symbols.nvda", "symbols.spy"]
        )

        let again = try Watchlist(answers: watchlist.answers)

        #expect(again.symbols == [.nvda])
    }
}

// A fan-out inside another decision takes the outer prefix.
@Decision
struct TradingIntake {
    @Ask("Is this message about trading?") var trading: Bool
    @Ask() var watchlist: Watchlist
}

extension FanOutEndToEndTests {
    @Test("A fan-out nests under a dotted prefix and round-trips")
    func nestedFanOut() async throws {
        var records = watchlistAnswers.prefixed("watchlist").records
        records["trading"] = .verdict(probability: 0.8)
        let model = FakeModel(answers: Answers(records: records, quality: .calibrated))
        let session = DecisionSession(model: model)

        let intake: TradingIntake = try await session.decide(about: "Buy NVDA and some SPY.")

        #expect(intake.trading)
        #expect(intake.watchlist.symbols == [.nvda, .spy])
        let ids = try #require(model.requests.first?.questionnaire.specs.map(\.id))
        #expect(ids == [
            "trading", "watchlist.symbols.nvda", "watchlist.symbols.spy", "watchlist.symbols.btc",
        ])
        let again = try TradingIntake(answers: intake.answers)
        #expect(again.watchlist.symbols == intake.watchlist.symbols)
        #expect(isClose(again.watchlist.$symbols[.nvda].probability, 0.95))
    }
}
