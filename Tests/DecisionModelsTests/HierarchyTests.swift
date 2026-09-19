import Testing

@testable import DecisionModels

/// A run-time option, named after the branch it stands for.
private func skill(_ id: String) -> Skill {
    Skill(id: id, summary: "The \(id) branch")
}

/// A model that answers every choice from a table of sibling sets.
///
/// The key of the table is the option ids of one question, sorted and joined,
/// so the fake answers by depth without knowing the question ids. A set the
/// table does not hold gets weights that fall with the sorted order, so every
/// answer is the same twice.
private func treeModel(_ table: [String: [String: Double]]) -> FakeModel {
    FakeModel { request in
        var records: [String: AnswerRecord] = [:]
        for spec in request.questionnaire.specs {
            guard case .choice(let options) = spec.kind else { continue }
            let ids = options.map(\.id)
            let probabilities =
                table[ids.sorted().joined(separator: ",")] ?? ranked(ids)
            let reported =
                probabilities.sorted { $0.value > $1.value }.first?.key ?? (ids.first ?? "")
            records[spec.id] = .choice(
                reported: reported,
                probabilities: probabilities,
                confidence: nil
            )
        }
        return ModelResponse(
            answers: Answers(records: records, quality: .calibrated),
            usage: Usage(requests: 1),
            requestID: "fake"
        )
    }
}

/// Weights that fall with the sorted order and sum to one.
private func ranked(_ ids: [String]) -> [String: Double] {
    let sorted = ids.sorted()
    let total = Double(sorted.count * (sorted.count + 1) / 2)
    return Dictionary(
        uniqueKeysWithValues: sorted.enumerated().map { place, id in
            (id, Double(sorted.count - place) / total)
        }
    )
}

/// A tree of `depth` levels where every node but the leaves has two children.
private func binaryTree(_ id: String, depth: Int) -> OptionTree<Skill> {
    guard depth > 1 else { return OptionTree(skill(id)) }
    return OptionTree(
        skill(id),
        children: [
            binaryTree(id + "L", depth: depth - 1),
            binaryTree(id + "R", depth: depth - 1),
        ]
    )
}

/// Two branches, two leaves each.
private let supportAndSales = [
    OptionTree(skill("support")) {
        OptionTree(skill("refund"))
        OptionTree(skill("escalate"))
    },
    OptionTree(skill("sales")) {
        OptionTree(skill("quote"))
        OptionTree(skill("demo"))
    },
]

private let branchTable: [String: [String: Double]] = [
    "sales,support": ["support": 0.8, "sales": 0.2],
    "escalate,refund": ["refund": 0.6, "escalate": 0.4],
    "demo,quote": ["demo": 0.9, "quote": 0.1],
]

private let instructions: State = "Which branch fits the request?"
private let message = "The customer wants money back."

@Suite("Hierarchy")
struct HierarchyTests {
    @Test("The builder collects the children")
    func builder() {
        let extras = ["upgrade"]
        let tree = OptionTree(skill("support")) {
            OptionTree(skill("refund"))
            if extras.count == 1 { OptionTree(skill("escalate")) }
            for id in extras { OptionTree(skill(id)) }
        }

        #expect(tree.option.id == "support")
        #expect(tree.children.map(\.option.id) == ["refund", "escalate", "upgrade"])
        #expect(tree.children[0].children.isEmpty)
    }

    @Test("A greedy walk returns the best leaf and the geometric mean")
    func greedyWalk() async throws {
        let model = treeModel(branchTable)
        let session = DecisionSession(model: model)

        let results = try await session.classify(
            supportAndSales,
            instructions: instructions,
            about: message
        )

        #expect(results.count == 1)
        let best = try #require(results.first)
        #expect(best.path.map(\.id) == ["support", "refund"])
        #expect(best.leaf?.id == "refund")
        #expect(best.reachedLeaf)
        #expect(best.steps.count == 2)
        // sqrt(0.8 * 0.6)
        #expect(isClose(best.score, (0.8 * 0.6).squareRoot(), within: 1e-12))
        #expect(isClose(best.steps[0][skill("support")], 0.8, within: 1e-12))
        #expect(isClose(best.steps[1][skill("refund")], 0.6, within: 1e-12))

        #expect(model.callCount == 2)
        #expect(model.requests[0].questionnaire.specs.map(\.id) == ["0.0"])
        #expect(model.requests[1].questionnaire.specs.map(\.id) == ["1.0"])
        #expect(model.requests[0].state == .text(message))
    }

    @Test("A beam of two keeps two paths and asks both sibling sets at once")
    func beamOfTwo() async throws {
        let model = treeModel(branchTable)
        let session = DecisionSession(model: model)

        let results = try await session.classify(
            supportAndSales,
            instructions: instructions,
            about: message,
            beamWidth: 2
        )

        #expect(model.callCount == 2)
        let second = try #require(model.requests.last)
        #expect(second.questionnaire.specs.map(\.id) == ["1.0", "1.1"])
        guard case .choice(let underSupport) = second.questionnaire.specs[0].kind,
            case .choice(let underSales) = second.questionnaire.specs[1].kind
        else {
            Issue.record("Both questions of the second request are choices.")
            return
        }
        #expect(underSupport.map(\.id) == ["refund", "escalate"])
        #expect(underSales.map(\.id) == ["quote", "demo"])

        #expect(results.count == 2)
        #expect(results.map { $0.path.map(\.id) } == [["support", "refund"], ["support", "escalate"]])
        #expect(isClose(results[0].score, (0.8 * 0.6).squareRoot(), within: 1e-12))
        #expect(isClose(results[1].score, (0.8 * 0.4).squareRoot(), within: 1e-12))
    }

    @Test("A candidate at a leaf keeps its place in the beam")
    func leafCandidateStays() async throws {
        let roots = [
            OptionTree(skill("leaf")),
            OptionTree(skill("branch")) {
                OptionTree(skill("left"))
                OptionTree(skill("right"))
            },
        ]
        let model = treeModel([
            "branch,leaf": ["leaf": 0.55, "branch": 0.45],
            "left,right": ["left": 0.7, "right": 0.3],
        ])
        let session = DecisionSession(model: model)

        let results = try await session.classify(
            roots,
            instructions: instructions,
            about: message,
            beamWidth: 2
        )

        #expect(model.callCount == 2)
        // Only the second candidate has children, so it asks question "1.1".
        #expect(model.requests[1].questionnaire.specs.map(\.id) == ["1.1"])
        #expect(results.map { $0.path.map(\.id) } == [["branch", "left"], ["leaf"]])
        #expect(isClose(results[0].score, (0.45 * 0.7).squareRoot(), within: 1e-12))
        #expect(isClose(results[1].score, 0.55, within: 1e-12))
    }

    @Test("A chain of single children costs no request and scores one")
    func forcedChainAsksNothing() async throws {
        let chain = [
            OptionTree(skill("a")) {
                OptionTree(skill("b")) {
                    OptionTree(skill("c"))
                }
            }
        ]
        let model = treeModel([:])
        let session = DecisionSession(model: model)

        let results = try await session.classify(
            chain,
            instructions: instructions,
            about: message
        )

        #expect(model.callCount == 0)
        let only = try #require(results.first)
        #expect(only.path.map(\.id) == ["a", "b", "c"])
        #expect(only.steps.count == 3)
        #expect(only.reachedLeaf)
        #expect(only.score == 1)
    }

    @Test("A forced step counts for nothing in the score")
    func forcedStepDoesNotScore() async throws {
        let roots = [
            OptionTree(skill("gate")) {
                OptionTree(skill("x")) {
                    OptionTree(skill("m"))
                    OptionTree(skill("n"))
                }
                OptionTree(skill("y"))
            }
        ]
        let model = treeModel([
            "x,y": ["x": 0.6, "y": 0.4],
            "m,n": ["m": 0.75, "n": 0.25],
        ])
        let session = DecisionSession(model: model)

        let results = try await session.classify(
            roots,
            instructions: instructions,
            about: message
        )

        #expect(model.callCount == 2)
        #expect(model.requests[0].questionnaire.specs.map(\.id) == ["0.0"])
        let best = try #require(results.first)
        #expect(best.path.map(\.id) == ["gate", "x", "m"])
        #expect(best.steps.count == 3)
        // The forced first step drops out: sqrt(0.6 * 0.75).
        #expect(isClose(best.score, (0.6 * 0.75).squareRoot(), within: 1e-12))
    }

    @Test("maxDepth stops the walk")
    func maxDepthStops() async throws {
        let model = treeModel(branchTable)
        let session = DecisionSession(model: model)

        let results = try await session.classify(
            supportAndSales,
            instructions: instructions,
            about: message,
            maxDepth: 1
        )

        #expect(model.callCount == 1)
        let best = try #require(results.first)
        #expect(best.path.map(\.id) == ["support"])
        #expect(!best.reachedLeaf)
        #expect(isClose(best.score, 0.8, within: 1e-12))
    }

    @Test("reachedLeaf tells a cut walk from a finished one")
    func reachedLeafReportsTheEnd() async throws {
        let deep = [binaryTree("a", depth: 4), binaryTree("b", depth: 4)]

        let cut = treeModel([:])
        let cutResults = try await DecisionSession(model: cut).classify(
            deep,
            instructions: instructions,
            about: message,
            maxDepth: 2
        )
        let stopped = try #require(cutResults.first)
        #expect(cut.callCount == 2)
        #expect(stopped.path.map(\.id) == ["a", "aL"])
        #expect(!stopped.reachedLeaf)

        let whole = treeModel([:])
        let wholeResults = try await DecisionSession(model: whole).classify(
            deep,
            instructions: instructions,
            about: message
        )
        let finished = try #require(wholeResults.first)
        #expect(whole.callCount == 4)
        #expect(finished.path.map(\.id) == ["a", "aL", "aLL", "aLLL"])
        #expect(finished.reachedLeaf)
    }

    @Test("A single root takes its step without a request")
    func rootWithoutChildren() async throws {
        let model = treeModel([:])
        let session = DecisionSession(model: model)

        let results = try await session.classify(
            [OptionTree(skill("solo"))],
            instructions: instructions,
            about: message
        )

        #expect(model.callCount == 0)
        let only = try #require(results.first)
        #expect(only.path.map(\.id) == ["solo"])
        #expect(only.leaf?.id == "solo")
        #expect(only.reachedLeaf)
        #expect(only.steps.count == 1)
        #expect(only.score == 1)
    }

    @Test("An empty tree asks nothing")
    func emptyTree() async throws {
        let model = treeModel([:])
        let session = DecisionSession(model: model)

        let results = try await session.classify(
            [] as [OptionTree<Skill>],
            instructions: instructions,
            about: message
        )

        #expect(results.isEmpty)
        #expect(model.callCount == 0)
    }

    @Test("An empty path scores one")
    func emptyPathScores() {
        let nothing = HierarchicalChoice<Skill>(path: [], steps: [], reachedLeaf: false)
        #expect(nothing.score == 1)
        #expect(nothing.leaf == nil)
    }
}
