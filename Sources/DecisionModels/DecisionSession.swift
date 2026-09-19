import Synchronization

/// Holds the model, the standing context, and the running usage.
///
/// A session keeps no history, because every request is stateless. Concurrent
/// calls on one session are safe: the only mutable state is the usage counter
/// behind a `Mutex`.
public final class DecisionSession: Sendable {
    private let decisionModel: any DecisionModel
    /// The standing context, rendered once. The class holds only `Sendable`
    /// state, so `[any StateRepresentable]` does not survive the initializer.
    private let context: [String: State]
    private let defaults: DecisionOptions
    private let counter = Mutex<Usage>(.zero)

    /// Builds a session.
    ///
    /// The context is standing material that merges into the state of every
    /// call: an object state gains the fields, any other state moves under
    /// `state` beside them. It renders once, here, so the session holds only
    /// `Sendable` values.
    ///
    /// `options` are the defaults for every call. A per-call `options` value
    /// replaces them entirely; to change one field, copy `session.options`
    /// and edit the copy.
    public init(
        model: some DecisionModel,
        context: [String: any StateRepresentable] = [:],
        options: DecisionOptions = .init()
    ) {
        self.decisionModel = model
        self.context = context.mapValues { $0.stateRepresentation }
        self.defaults = options
    }

    /// The model this session asks.
    public var model: any DecisionModel { decisionModel }

    /// The options every call starts from. A per-call value replaces them
    /// entirely, so copy these to change one field.
    public var options: DecisionOptions { defaults }

    /// What every call so far has cost.
    public var usage: Usage { counter.withLock { $0 } }

    /// Gets the model ready.
    public func prewarm() async {
        await decisionModel.prewarm()
    }

    // MARK: Deciding

    /// Asks the decision's questions about a state and returns the decision.
    public func decide<D: Decision>(
        _ type: D.Type = D.self,
        about state: some StateRepresentable,
        options: DecisionOptions? = nil
    ) async throws -> D {
        try await respond(type, about: state, options: options).decision
    }

    /// Asks about a state the builder assembles.
    public func decide<D: Decision>(
        _ type: D.Type = D.self,
        options: DecisionOptions? = nil,
        @StateBuilder about state: () throws -> State
    ) async throws -> D {
        try await decide(type, about: state(), options: options)
    }

    /// Asks the decision's questions and returns the decision with the metadata
    /// of the call.
    public func respond<D: Decision>(
        _ type: D.Type = D.self,
        about state: some StateRepresentable,
        options: DecisionOptions? = nil
    ) async throws -> DecisionResponse<D> {
        let clock = ContinuousClock()
        let start = clock.now
        let response = try await send(
            D.questions,
            about: state.stateRepresentation,
            options: options ?? defaults
        )
        let decision = try D(answers: response.answers)
        return DecisionResponse(
            decision: decision,
            answers: response.answers,
            usage: response.usage,
            model: decisionModel.identity,
            requestID: response.requestID,
            duration: clock.now - start
        )
    }

    /// Asks questions that exist only at run time.
    public func decide(
        _ questionnaire: Questionnaire,
        about state: some StateRepresentable,
        options: DecisionOptions? = nil
    ) async throws -> Answers {
        try await send(
            questionnaire,
            about: state.stateRepresentation,
            options: options ?? defaults
        ).answers
    }

    // MARK: The pipeline

    private func send(
        _ questionnaire: Questionnaire,
        about state: State,
        options: DecisionOptions
    ) async throws -> ModelResponse {
        if case .unavailable(let reason) = await decisionModel.availability {
            throw DecisionError.unavailable(reason)
        }
        try Preflight.check(
            questionnaire,
            samples: options.samples,
            against: decisionModel.capabilities
        )
        let request = DecisionRequest(
            state: merged(state),
            questionnaire: questionnaire,
            samples: options.samples,
            timeout: options.timeout,
            metadata: options.metadata
        )
        let response = try await decisionModel.decide(request)
        // The provider was paid whether or not the answer is good enough.
        counter.withLock { $0 += response.usage }
        if let floor = options.minimumProbabilityQuality, response.answers.quality < floor {
            throw DecisionError.insufficientProbabilityQuality(
                got: response.answers.quality, required: floor
            )
        }
        return response
    }

    /// Merges the standing context into the state.
    ///
    /// An object state gains the context fields, and the state wins when both
    /// hold the same key. Any other state becomes the `state` field of an
    /// object that also holds the context. An empty context leaves the state
    /// alone.
    private func merged(_ state: State) -> State {
        guard !context.isEmpty else { return state }
        var object = context
        if case .object(let fields) = state {
            for (name, value) in fields { object[name] = value }
        } else {
            object["state"] = state
        }
        return .object(object)
    }
}
