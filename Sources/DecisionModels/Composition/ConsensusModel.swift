/// Asks one model the same request many times and merges the draws.
///
/// The runs go out together. Probabilities average per question, the reported
/// value comes from the average, and the reported confidence goes away, so the
/// section 6.1 formula speaks for the merged distribution. Every run's
/// probabilities scale to sum to one first, so a run that names only its top
/// option weighs as much as a run that lists them all. DESIGN.md section 10.2.
///
/// A call that asks for more than one draw sets the count for that call. Every
/// other call takes the count of the model. Each run asks the inner model for
/// one draw, because the repetition happens here.
///
/// Put a cache outside the consensus, never inside: a `CachedModel` under a
/// `ConsensusModel` serves every run the same stored answer, so the runs
/// collapse to one real draw.
public struct ConsensusModel: DecisionModel {
    /// The model that answers every run.
    public let model: any DecisionModel
    /// How many runs to take when the call does not say.
    public let samples: Int

    public init(_ model: some DecisionModel, samples: Int) {
        precondition(samples >= 1, "Consensus takes at least one sample.")
        self.model = model
        self.samples = samples
    }

    /// A distinct identity, because the merged answers are not the inner
    /// model's own.
    public var identity: DecisionModelIdentity {
        DecisionModelIdentity(
            provider: "consensus",
            name: "\(model.identity.name)×\(samples)"
        )
    }

    /// The inner model's, and it repeats.
    ///
    /// More than one draw reaches an empirical distribution. One draw adds
    /// nothing, so the inner quality stands.
    public var capabilities: DecisionModelCapabilities {
        var merged = model.capabilities
        if samples > 1 {
            merged.probabilityQuality = max(merged.probabilityQuality, .sampled(count: samples))
        }
        merged.supportsRepeatedSamples = true
        return merged
    }

    public var availability: DecisionModelAvailability {
        get async { await model.availability }
    }

    public func prewarm() async {
        await model.prewarm()
    }

    public func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        try await decideWithReport(request).response
    }

    /// Answers the request and names the questions the runs answered differently.
    ///
    /// Two runs differ when their answer values differ: the named option, the
    /// most likely level, or the side of a verdict.
    public func decideWithReport(_ request: DecisionRequest) async throws -> ConsensusReport {
        let runs = try await draw(request, count: runCount(for: request))
        let ids = Self.answeredIDs(runs, asking: request.questionnaire)

        var records: [String: AnswerRecord] = [:]
        var disagreements: [String] = []
        for id in ids {
            let drawn = runs.compactMap { $0.answers.records[id] }
            guard !drawn.isEmpty else { continue }
            records[id] = try Self.averaged(drawn, id: id)
            if Set(drawn.map(Self.value)).count > 1 { disagreements.append(id) }
        }

        return ConsensusReport(
            response: ModelResponse(
                answers: Answers(records: records, quality: Self.quality(of: runs, disagreements)),
                usage: runs.map(\.usage).reduce(.zero, +),
                requestID: runs.compactMap(\.requestID).first
            ),
            disagreements: disagreements
        )
    }

    /// How many runs one request takes. The call wins when it asks for more
    /// than one draw.
    private func runCount(for request: DecisionRequest) -> Int {
        request.samples > 1 ? request.samples : samples
    }

    /// Runs the inner model `count` times, in run order.
    ///
    /// Every run asks for one draw, because the repetition happens here.
    private func draw(_ request: DecisionRequest, count: Int) async throws -> [ModelResponse] {
        let single = DecisionRequest(
            state: request.state,
            questionnaire: request.questionnaire,
            samples: 1,
            timeout: request.timeout,
            metadata: request.metadata
        )
        let inner = model
        return try await withThrowingTaskGroup(
            of: (Int, ModelResponse).self,
            returning: [ModelResponse].self
        ) { group in
            for run in 0..<count {
                group.addTask {
                    let response = try await inner.decide(single)
                    return (run, response)
                }
            }
            var collected: [(Int, ModelResponse)] = []
            for try await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// What the merged probabilities are worth.
    ///
    /// One run says what it said. Many runs make an empirical distribution,
    /// unless the model calibrates its own numbers and every run agreed.
    private static func quality(
        of runs: [ModelResponse],
        _ disagreements: [String]
    ) -> ProbabilityQuality {
        guard runs.count > 1 else { return runs.first?.answers.quality ?? .pointEstimate }
        let calibrated = runs.allSatisfy { $0.answers.quality == .calibrated }
        return calibrated && disagreements.isEmpty ? .calibrated : .sampled(count: runs.count)
    }

    /// Every id the runs answered, the asked ones first and in order.
    private static func answeredIDs(
        _ runs: [ModelResponse],
        asking questionnaire: Questionnaire
    ) -> [String] {
        var ids = questionnaire.specs.map(\.id)
        let asked = Set(ids)
        var extra: Set<String> = []
        for run in runs {
            for id in run.answers.records.keys where !asked.contains(id) { extra.insert(id) }
        }
        ids.append(contentsOf: extra.sorted())
        return ids
    }

    /// Averages the draws of one question.
    ///
    /// Every run scales to sum to one first, so a short answer counts as much
    /// as a full one.
    private static func averaged(_ records: [AnswerRecord], id: String) throws -> AnswerRecord {
        let count = Double(records.count)
        switch records[0] {
        case .choice:
            var totals: [String: Double] = [:]
            for record in records {
                guard case .choice(_, let probabilities, _) = record else { throw mixed(id) }
                for (option, probability) in ConfidenceMath.normalized(probabilities) {
                    totals[option, default: 0] += probability
                }
            }
            let mean = totals.mapValues { $0 / count }
            return .choice(reported: argmax(mean), probabilities: mean, confidence: nil)
        case .rating:
            var totals: [Int: Double] = [:]
            var score = 0.0
            for record in records {
                guard case .rating(let drawn, let probabilities, _) = record else {
                    throw mixed(id)
                }
                score += drawn
                for (level, probability) in ConfidenceMath.normalized(probabilities) {
                    totals[level, default: 0] += probability
                }
            }
            return .rating(
                score: score / count,
                probabilities: totals.mapValues { $0 / count },
                confidence: nil
            )
        case .verdict:
            var total = 0.0
            for record in records {
                guard case .verdict(let probability) = record else { throw mixed(id) }
                total += probability
            }
            return .verdict(probability: total / count)
        }
    }

    /// The value one draw reports, as text, so that draws compare.
    private static func value(_ record: AnswerRecord) -> String {
        switch record {
        case .choice(let reported, _, _):
            "choice:\(reported)"
        case .rating(_, let probabilities, _):
            "rating:\(topLevel(probabilities))"
        case .verdict(let probability):
            "verdict:\(probability >= 0.5)"
        }
    }

    /// The most likely option. A tie goes to the smallest id.
    private static func argmax(_ probabilities: [String: Double]) -> String {
        probabilities.sorted { left, right in
            left.value == right.value ? left.key < right.key : left.value > right.value
        }.first?.key ?? ""
    }

    /// The most likely level. A tie goes to the lowest level.
    private static func topLevel(_ probabilities: [Int: Double]) -> Int {
        probabilities.sorted { left, right in
            left.value == right.value ? left.key < right.key : left.value > right.value
        }.first?.key ?? 0
    }

    private static func mixed(_ id: String) -> DecisionError {
        .malformedResponse("The runs answer question \(id) with different kinds of answer.")
    }
}

/// What a consensus answered, and where the runs did not agree.
public struct ConsensusReport: Sendable {
    /// The merged answers.
    public let response: ModelResponse
    /// The questions whose answer value changed from run to run.
    public let disagreements: [String]

    public init(response: ModelResponse, disagreements: [String]) {
        self.response = response
        self.disagreements = disagreements
    }
}
