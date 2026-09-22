import Foundation

/// One option and the options under it.
///
/// A tree of these is the answer space of `classify`. DESIGN.md section 16.
public struct OptionTree<Option: ChoiceOption>: Sendable {
    /// The option at this node.
    public let option: Option
    /// The options one step down. An empty list is a leaf.
    public let children: [OptionTree]

    public init(_ option: Option, children: [OptionTree] = []) {
        self.option = option
        self.children = children
    }

    public init(_ option: Option, @OptionTreeBuilder children: () -> [OptionTree]) {
        self.init(option, children: children())
    }
}

/// Collects the children of a node. It supports `if` and `for`.
@resultBuilder
public enum OptionTreeBuilder {
    public static func buildExpression<Option: ChoiceOption>(
        _ tree: OptionTree<Option>
    ) -> [OptionTree<Option>] { [tree] }

    public static func buildExpression<Option: ChoiceOption>(
        _ trees: [OptionTree<Option>]
    ) -> [OptionTree<Option>] { trees }

    public static func buildBlock<Option: ChoiceOption>(
        _ parts: [OptionTree<Option>]...
    ) -> [OptionTree<Option>] { parts.flatMap(\.self) }

    public static func buildOptional<Option: ChoiceOption>(
        _ part: [OptionTree<Option>]?
    ) -> [OptionTree<Option>] { part ?? [] }

    public static func buildEither<Option: ChoiceOption>(
        first part: [OptionTree<Option>]
    ) -> [OptionTree<Option>] { part }

    public static func buildEither<Option: ChoiceOption>(
        second part: [OptionTree<Option>]
    ) -> [OptionTree<Option>] { part }

    public static func buildArray<Option: ChoiceOption>(
        _ parts: [[OptionTree<Option>]]
    ) -> [OptionTree<Option>] { parts.flatMap(\.self) }
}

/// One walk down the tree: what the model chose at every depth.
public struct HierarchicalChoice<Option: ChoiceOption>: Sendable {
    /// The options the model chose, from the root down.
    public let path: [Option]
    /// The answer at every depth, with the full distribution over the siblings.
    /// A step with one option only is certain: nobody asked.
    public let steps: [Choice<Option>]
    /// Whether the walk ended at a leaf. `false` means `maxDepth` stopped it.
    public let reachedLeaf: Bool

    public init(path: [Option], steps: [Choice<Option>], reachedLeaf: Bool) {
        self.path = path
        self.steps = steps
        self.reachedLeaf = reachedLeaf
    }

    /// The last option on the path.
    public var leaf: Option? { path.last }

    /// The geometric mean of the probabilities along the path.
    ///
    /// Every step with a real choice contributes the probability of the option
    /// it chose. A step that had one option only says nothing about the walk,
    /// so it counts for nothing. A path of such steps scores 1, and so does an
    /// empty path.
    public var score: Double {
        var product = 1.0
        var chosen = 0
        for (step, option) in zip(steps, path) where step.distribution.probabilities.count > 1 {
            product *= step[option]
            chosen += 1
        }
        guard chosen > 0 else { return 1 }
        return pow(product, 1 / Double(chosen))
    }
}

extension DecisionSession {
    /// Walks a tree of options with beam search, one request per depth.
    ///
    /// Every candidate that has more than one child asks one question over
    /// those children, and all the questions of one depth travel in one
    /// request. A question id is `"<depth>.<candidate>"`, where the candidate
    /// is its place in the beam. A candidate with one child only takes it
    /// without a request, because there is nothing to choose. A candidate that
    /// reached a leaf stays as it is and keeps competing on score.
    ///
    /// The walk stops when no candidate can go deeper or at `maxDepth`, which
    /// bounds the requests. The result holds up to `beamWidth` paths, the best
    /// score first, and every path says whether it reached a leaf.
    public func classify<Option: ChoiceOption>(
        _ roots: [OptionTree<Option>],
        instructions: State,
        about state: some StateRepresentable,
        beamWidth: Int = 1,
        maxDepth: Int = 8,
        options: DecisionOptions? = nil
    ) async throws -> [HierarchicalChoice<Option>] {
        try await classify(
            roots,
            instructions: instructions,
            state: state.stateRepresentation,
            beamWidth: beamWidth,
            maxDepth: maxDepth,
            options: options
        )
    }

    /// Classifies with no state, for trees whose questions carry their own
    /// facts. The standing context, if any, is the whole state.
    ///
    /// See the overload above for the walk's rules.
    public func classify<Option: ChoiceOption>(
        _ roots: [OptionTree<Option>],
        instructions: State,
        beamWidth: Int = 1,
        maxDepth: Int = 8,
        options: DecisionOptions? = nil
    ) async throws -> [HierarchicalChoice<Option>] {
        try await classify(
            roots,
            instructions: instructions,
            state: nil,
            beamWidth: beamWidth,
            maxDepth: maxDepth,
            options: options
        )
    }

    /// The walk both overloads above run. Only the state differs.
    private func classify<Option: ChoiceOption>(
        _ roots: [OptionTree<Option>],
        instructions: State,
        state: State?,
        beamWidth: Int,
        maxDepth: Int,
        options: DecisionOptions?
    ) async throws -> [HierarchicalChoice<Option>] {
        precondition(beamWidth >= 1, "A beam holds at least one path.")
        precondition(maxDepth >= 1, "A walk takes at least one step.")
        guard !roots.isEmpty else { return [] }

        var candidates = [BeamCandidate(path: [], steps: [], frontier: roots)]
        for depth in 0..<maxDepth {
            takeForcedSteps(&candidates)
            var questions: [Int: Choose<Option>] = [:]
            var questionnaire = Questionnaire()
            for (place, candidate) in candidates.enumerated() where !candidate.frontier.isEmpty {
                let question = Choose(
                    "\(depth).\(place)",
                    instructions,
                    among: candidate.frontier.map(\.option)
                )
                questions[place] = question
                questionnaire.add(question)
            }
            guard !questions.isEmpty else { break }

            let answers: Answers
            if let state {
                answers = try await decide(questionnaire, about: state, options: options)
            } else {
                answers = try await decide(questionnaire, options: options)
            }
            var grown: [BeamCandidate<Option>] = []
            for (place, candidate) in candidates.enumerated() {
                guard let question = questions[place] else {
                    grown.append(candidate)
                    continue
                }
                let step = try answers[question]
                for child in candidate.frontier {
                    grown.append(
                        BeamCandidate(
                            path: candidate.path + [child.option],
                            steps: candidate.steps + [step],
                            frontier: child.children
                        )
                    )
                }
            }
            candidates = best(beamWidth, of: grown)
        }
        return candidates.map {
            HierarchicalChoice(
                path: $0.path,
                steps: $0.steps,
                reachedLeaf: $0.frontier.isEmpty
            )
        }
    }
}

/// One path under construction, with the options it can still go to.
private struct BeamCandidate<Option: ChoiceOption> {
    var path: [Option]
    var steps: [Choice<Option>]
    var frontier: [OptionTree<Option>]

    var score: Double {
        HierarchicalChoice(path: path, steps: steps, reachedLeaf: frontier.isEmpty).score
    }
}

/// Takes every step that has one option only.
///
/// Such a step needs no model: there is nothing to choose. The walk records it
/// as a certain answer, so the path and the steps stay in step, and the score
/// passes it by.
private func takeForcedSteps<Option: ChoiceOption>(_ candidates: inout [BeamCandidate<Option>]) {
    for place in candidates.indices {
        while candidates[place].frontier.count == 1 {
            let only = candidates[place].frontier[0]
            candidates[place].path.append(only.option)
            candidates[place].steps.append(Choice(certain: only.option))
            candidates[place].frontier = only.children
        }
    }
}

/// The best candidates, highest score first. A tie keeps the earlier one.
private func best<Option: ChoiceOption>(
    _ width: Int,
    of candidates: [BeamCandidate<Option>]
) -> [BeamCandidate<Option>] {
    let ranked = candidates.enumerated().sorted { left, right in
        let leftScore = left.element.score
        let rightScore = right.element.score
        return leftScore == rightScore ? left.offset < right.offset : leftScore > rightScore
    }
    return ranked.prefix(width).map(\.element)
}
