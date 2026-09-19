import DecisionModels

/// Runs a labeled set through one or more models and scores what comes back.
///
/// Every model gets its own session, so the models never share usage or
/// options. The run is sequential and in order, so two runs of the same set
/// against the same models give the same report.
///
/// ```swift
/// let report = try await Evaluation(models: [live, onDevice])
///     .run(TicketTriage.self, on: labeled)
/// print(report[live.identity]?.question("team")?.brierScore ?? 0)
/// ```
public struct Evaluation: Sendable {
    /// The models to compare, on equal terms.
    public let models: [any DecisionModel]
    /// The options every session starts from.
    public let options: DecisionOptions

    /// Builds an evaluation.
    ///
    /// Every model needs its own identity, because the report is keyed on it.
    /// Two models that share one is a programmer error: give the second a
    /// distinct `DecisionModelIdentity`, such as a different `name`.
    public init(models: [any DecisionModel], options: DecisionOptions = .init()) {
        let identities = models.map(\.identity)
        precondition(
            Set(identities).count == identities.count,
            """
            Two models share an identity. The report is keyed on the identity, \
            so give every model a distinct DecisionModelIdentity.
            """
        )
        self.models = models
        self.options = options
    }

    /// Asks every model about every state and scores the answers.
    ///
    /// The labels are whole decisions, so a test writes
    /// `TicketTriage(team: .returns, severity: .blocking, requestsRefund: true)`
    /// and the evaluation reads `expected.answers.records`. Nothing here
    /// reflects on the Swift type.
    ///
    /// Both sides are wire records. The answer is the `answers.records` of
    /// the decision the session built, not the raw response, and that is on
    /// purpose: it is the same round trip a call site makes, so the
    /// confidences the report counts are the numbers the call site puts its
    /// thresholds against.
    public func run<D: Decision>(
        _ type: D.Type = D.self,
        on labeled: [(state: State, expected: D)]
    ) async throws -> Report {
        let ids = D.questions.specs.map(\.id)
        var reports: [ModelReport] = []
        for model in models {
            let session = DecisionSession(model: model, options: options)
            var samples: [String: [Sample]] = [:]
            for example in labeled {
                let predicted = try await session.decide(D.self, about: example.state)
                let predictedRecords = predicted.answers.records
                let expectedRecords = example.expected.answers.records
                for id in ids {
                    guard let predictedRecord = predictedRecords[id] else {
                        throw DecisionError.invalidQuestion(
                            id: id, reason: "The answer holds no record."
                        )
                    }
                    guard let expectedRecord = expectedRecords[id] else {
                        throw DecisionError.invalidQuestion(
                            id: id, reason: "The label holds no record."
                        )
                    }
                    samples[id, default: []].append(
                        try Sample(predicted: predictedRecord, expected: expectedRecord, id: id)
                    )
                }
            }
            reports.append(ModelReport(model: model.identity, questions: ids, samples: samples))
        }
        return Report(reports: reports)
    }

    // MARK: The report

    /// What every model scored.
    public struct Report: Sendable {
        /// The models, in the order the evaluation ran them.
        public let models: [DecisionModelIdentity]
        private let reports: [DecisionModelIdentity: ModelReport]

        init(reports: [ModelReport]) {
            self.models = reports.map(\.model)
            self.reports = Dictionary(
                reports.map { ($0.model, $0) },
                uniquingKeysWith: { _, last in last }
            )
        }

        /// What one model scored, or `nil` when it did not run.
        public subscript(identity: DecisionModelIdentity) -> ModelReport? {
            reports[identity]
        }
    }

    /// What one model scored, question by question.
    public struct ModelReport: Sendable {
        /// Which model this is.
        public let model: DecisionModelIdentity
        /// The question ids, in questionnaire order.
        public let questions: [String]
        private let reports: [String: QuestionReport]

        init(model: DecisionModelIdentity, questions: [String], samples: [String: [Sample]]) {
            self.model = model
            self.questions = questions
            var reports: [String: QuestionReport] = [:]
            for id in questions {
                reports[id] = QuestionReport(id: id, samples: samples[id] ?? [])
            }
            self.reports = reports
        }

        /// What one question scored, or `nil` when the run never asked it.
        public func question(_ id: String) -> QuestionReport? {
            reports[id]
        }
    }

    /// What one question scored over the whole labeled set.
    public struct QuestionReport: Sendable {
        /// The question id.
        public let id: String
        /// How many examples the question answered.
        public let count: Int
        /// The fraction the model got right. A choice is right when it names
        /// the labeled option, a rating when its most likely level is the
        /// labeled one, and a verdict when both land on the same side of one
        /// half. A rating that ties for the highest probability counts as the
        /// lower level, on both sides, which is what `Rating.value` picks.
        public let accuracy: Double
        /// The mean Brier score, `Calibration.brierScore(predicted:expected:)`
        /// over the examples. Zero is perfect.
        public let brierScore: Double
        /// The gap between how sure the model was and how often it was right,
        /// over ten equal-width bins on the top probability. Zero is perfect.
        public let expectedCalibrationError: Double
        /// The confidence of every answer, in the order of the labeled set.
        /// These are the numbers a threshold compares against.
        public let confidences: [Double]

        init(id: String, samples: [Sample]) {
            self.id = id
            self.count = samples.count
            self.confidences = samples.map(\.confidence)
            guard !samples.isEmpty else {
                self.accuracy = 0
                self.brierScore = 0
                self.expectedCalibrationError = 0
                return
            }
            let size = Double(samples.count)
            self.accuracy = samples.reduce(0) { $0 + ($1.correct ? 1 : 0) } / size
            self.brierScore = samples.reduce(0) { $0 + $1.brierScore } / size
            self.expectedCalibrationError = Calibration.expectedCalibrationError(
                samples.map { (confidence: $0.topProbability, correct: $0.correct) }
            )
        }

        /// How many answers fall in each band, for a candidate pair of
        /// thresholds. This is how a team picks the thresholds it will ship.
        public func bands(
            escalateBelow low: Double,
            confirmBelow high: Double
        ) -> (act: Int, confirm: Int, escalate: Int) {
            Calibration.bands(confidences, escalateBelow: low, confirmBelow: high)
        }
    }

    /// One answer, scored against its label.
    struct Sample: Sendable {
        /// Whether the plain value matches the label.
        var correct: Bool
        /// The Brier score of this one answer.
        var brierScore: Double
        /// The probability of the answer the model named, which is not always
        /// the highest one in the map. Calibration bins on this, not on the
        /// confidence, because a bin asks how often a stated probability comes
        /// true, and the stated probability has to belong to the prediction
        /// that `correct` judges.
        var topProbability: Double
        /// The confidence a threshold compares against.
        var confidence: Double

        init(predicted: AnswerRecord, expected: AnswerRecord, id: String) throws {
            switch (predicted, expected) {
            case (
                .choice(let named, let probabilities, _),
                .choice(let labeled, _, _)
            ):
                let scaled = Calibration.normalized(probabilities)
                self.correct = named == labeled
                self.brierScore = Calibration.brierScore(predicted: scaled, expected: labeled)
                // The option the model named, not the highest one in the map.
                // A model may name an option it did not rank first, and the
                // bin has to describe the prediction, not a runner-up.
                self.topProbability = scaled[named] ?? 0

            case (
                .rating(_, let probabilities, _),
                .rating(_, let labeledProbabilities, _)
            ):
                let scaled = Calibration.normalized(probabilities)
                guard
                    let labeled = Calibration.mostLikely(
                        Calibration.normalized(labeledProbabilities)
                    )
                else {
                    throw DecisionError.invalidQuestion(
                        id: id, reason: "The label holds no level."
                    )
                }
                // The level `Rating.value` picks: the lowest of those tied for
                // the highest probability.
                let named = Calibration.mostLikely(scaled)
                self.correct = named == labeled
                self.brierScore = Calibration.brierScore(predicted: scaled, expected: labeled)
                self.topProbability = named.flatMap { scaled[$0] } ?? 0

            case (.verdict(let probability), .verdict(let labeledProbability)):
                let scaled = [true: probability, false: 1 - probability]
                let named = probability >= 0.5
                let labeled = labeledProbability >= 0.5
                self.correct = named == labeled
                self.brierScore = Calibration.brierScore(predicted: scaled, expected: labeled)
                // The side the verdict lands on: `max(p, 1 - p)`.
                self.topProbability = scaled[named] ?? 0

            default:
                throw DecisionError.malformedResponse(
                    "Question \(id): the answer and the label are not the same kind."
                )
            }
            self.confidence = predicted.confidence
        }
    }
}
