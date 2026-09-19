import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("Set fan-out expansion")
struct FanOutExpansionTests {
    @Test("A set reads the options at or above one half")
    func setForm() {
        expectExpansion(
            of: """
                struct Watchlist {
                    @Ask("Does the request mention {option}?")
                    var symbols: Set<Symbol>
                }
                """,
            is: """
                struct Watchlist {
                    var symbols: Set<Symbol> {
                        get {
                            Set<Symbol>.read($symbols)
                        }
                    }

                    var $symbols: Set<Symbol>.Projection
                }
                """
        )
    }

    @Test("A set reads through its threshold")
    func minimumProbabilityForm() {
        expectExpansion(
            of: """
                struct Watchlist {
                    @Ask("Does the request mention {option}?", minimumProbability: 0.9)
                    var symbols: Set<Symbol>
                }
                """,
            is: """
                struct Watchlist {
                    var symbols: Set<Symbol> {
                        get {
                            Set<Symbol>.read($symbols, minimumProbability: 0.9)
                        }
                    }

                    var $symbols: Set<Symbol>.Projection
                }
                """
        )
    }

    @Test("A labelled set question expands the same way")
    func labelledForm() {
        expectExpansion(
            of: """
                struct Watchlist {
                    @Ask(instructions: "Mentions {option}?", minimumProbability: 0.9)
                    var symbols: Set<Symbol>
                }
                """,
            is: """
                struct Watchlist {
                    var symbols: Set<Symbol> {
                        get {
                            Set<Symbol>.read($symbols, minimumProbability: 0.9)
                        }
                    }

                    var $symbols: Set<Symbol>.Projection
                }
                """
        )
    }

    @Test("A threshold on a property that is not a set still expands")
    func thresholdOnAPlainProperty() {
        // The macro checks no types. Only `Set` has the two-argument read on
        // probability, so this expansion fails to type-check at the use site,
        // which is the diagnostic the design asks for.
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?", minimumProbability: 0.9)
                    var team: Team
                }
                """,
            is: """
                struct Ticket {
                    var team: Team {
                        get {
                            Team.read($team, minimumProbability: 0.9)
                        }
                    }

                    var $team: Team.Projection
                }
                """
        )
    }

    @Test("A property gives one threshold, not two")
    func oneThresholdOnly() {
        expectExpansion(
            of: """
                struct Watchlist {
                    @Ask("Mentions {option}?", minimumConfidence: 0.7, minimumProbability: 0.9)
                    var symbols: Set<Symbol>
                }
                """,
            is: """
                struct Watchlist {
                    var symbols: Set<Symbol> {
                        get {
                            fatalError()
                        }
                    }
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message:
                        "Give minimumConfidence or minimumProbability, not both. "
                        + "An optional gates on confidence; a set gates on the probability "
                        + "of each option.",
                    line: 2,
                    column: 76
                )
            ]
        )
    }
}
