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
        try await answer(D.self, about: state.stateRepresentation, options: options)
    }

    // MARK: Deciding through a projection

    /// Asks for any `Askable` type whose projection is a decision, such as a
    /// `@Decision` enum, and returns the plain value.
    ///
    /// The request is the projection's own questionnaire, and `read` reduces
    /// the projection to the value. A plain `Decision` binds to the `Decision`
    /// call above, which is the more specialized of the two.
    ///
    /// An optional decision answers the same way and never comes back `nil`,
    /// because a whole decision has no one confidence to gate on: write
    /// `let triage: TicketTriage = ...` and read the confidence of the answer
    /// that matters. The answer to `let triage: TicketTriage? = ...` is the
    /// same decision, wrapped.
    public func decide<A: Askable>(
        _ type: A.Type = A.self,
        about state: some StateRepresentable,
        options: DecisionOptions? = nil
    ) async throws -> A where A.Projection: Decision {
        let response = try await answer(
            A.Projection.self, about: state.stateRepresentation, options: options
        )
        return A.read(response.decision)
    }

    /// Asks the same of a state the builder assembles. A plain `Decision`
    /// binds to the `Decision` call above, and an optional decision comes back
    /// wrapped, never `nil`.
    public func decide<A: Askable>(
        _ type: A.Type = A.self,
        options: DecisionOptions? = nil,
        @StateBuilder about state: () throws -> State
    ) async throws -> A where A.Projection: Decision {
        try await decide(type, about: state(), options: options)
    }

    /// Asks for such a type and returns its projection with the metadata of
    /// the call, so that the caller reads the confidence of every part.
    ///
    /// A `@Decision` enum answers with its `Answered` projection, which holds
    /// the chosen kind beside the command. A plain `Decision` binds to the
    /// `Decision` call above, and an optional decision answers as the decision
    /// it wraps, because `Optional<D>.Projection` is `D`.
    public func respond<A: Askable>(
        _ type: A.Type = A.self,
        about state: some StateRepresentable,
        options: DecisionOptions? = nil
    ) async throws -> DecisionResponse<A.Projection> where A.Projection: Decision {
        try await answer(A.Projection.self, about: state.stateRepresentation, options: options)
    }

    /// The one path a decision takes, whichever call asked for it. The
    /// overloads above name the type; this one runs it.
    private func answer<D: Decision>(
        _ type: D.Type,
        about state: State,
        options: DecisionOptions?
    ) async throws -> DecisionResponse<D> {
        let clock = ContinuousClock()
        let start = clock.now
        let response = try await send(D.questions, about: state, options: options ?? defaults)
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
