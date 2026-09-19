import Testing

@Suite("@Ask expansion")
struct AskExpansionTests {
    @Test("A question becomes a getter over a peer")
    func stringForm() {
        expectExpansion(
            of: """
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
                }
                """
        )
    }

    @Test("An optional reads through its threshold")
    func minimumConfidenceForm() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?", minimumConfidence: 0.7)
                    var team: Team?
                }
                """,
            is: """
                struct Ticket {
                    var team: Team? {
                        get {
                            Team?.read($team, minimumConfidence: 0.7)
                        }
                    }

                    var $team: Team?.Projection
                }
                """
        )
    }

    @Test("A nested decision reads as itself")
    func nestedForm() {
        expectExpansion(
            of: """
                struct Intake {
                    @Ask()
                    var bug: BugReport
                }
                """,
            is: """
                struct Intake {
                    var bug: BugReport {
                        get {
                            BugReport.read($bug)
                        }
                    }

                    var $bug: BugReport.Projection
                }
                """
        )
    }

    @Test("The long spelling of an optional works the same way")
    func writtenOutOptional() {
        expectExpansion(
            of: """
                struct Ticket {
                    @Ask("Which team handles this ticket?", minimumConfidence: 0.7)
                    var team: Optional<Team>
                }
                """,
            is: """
                struct Ticket {
                    var team: Optional<Team> {
                        get {
                            Optional<Team>.read($team, minimumConfidence: 0.7)
                        }
                    }

                    var $team: Optional<Team>.Projection
                }
                """
        )
    }

    @Test("The peer keeps the access of the property")
    func peerKeepsAccess() {
        expectExpansion(
            of: """
                public struct Ticket {
                    @Ask("Which team handles this ticket?")
                    public var team: Team
                }
                """,
            is: """
                public struct Ticket {
                    public var team: Team {
                        get {
                            Team.read($team)
                        }
                    }

                    public var $team: Team.Projection
                }
                """
        )
    }
}
