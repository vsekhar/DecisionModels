/// Where a `CachedModel` keeps answers.
public protocol DecisionCache: Sendable {
    /// The stored response for a key, or `nil`.
    func response(for key: CacheKey) async -> ModelResponse?
    /// Keeps a response under a key.
    func store(_ response: ModelResponse, for key: CacheKey) async
}

/// What makes two requests the same request.
///
/// The key holds the state, the questions, the number of draws, and the model.
/// It holds neither the metadata nor the timeout: those tag a call, they do not
/// change the answer. DESIGN.md section 10.
public struct CacheKey: Hashable, Sendable {
    /// The material the model judged.
    public let state: State
    /// The questions it answered.
    public let questionnaire: Questionnaire
    /// How many draws the caller asked for.
    public let samples: Int
    /// Which model answered.
    public let model: DecisionModelIdentity

    public init(_ request: DecisionRequest, model: DecisionModelIdentity) {
        self.state = request.state
        self.questionnaire = request.questionnaire
        self.samples = request.samples
        self.model = model
    }
}

/// A cache in memory, for one run of a program.
///
/// A capacity bounds it: the oldest entry goes when a new one does not fit.
/// Storing a key again refreshes its response but keeps its place in the queue.
public actor InMemoryDecisionCache: DecisionCache {
    /// How many responses the cache holds at most. `nil` means no bound.
    public let capacity: Int?
    private var entries: [CacheKey: ModelResponse] = [:]
    private var order: [CacheKey] = []

    public init(capacity: Int? = nil) {
        if let capacity { precondition(capacity >= 1, "A cache holds at least one response.") }
        self.capacity = capacity
    }

    /// How many responses the cache holds now.
    public var count: Int { entries.count }

    public func response(for key: CacheKey) -> ModelResponse? {
        entries[key]
    }

    public func store(_ response: ModelResponse, for key: CacheKey) {
        if entries[key] == nil { order.append(key) }
        entries[key] = response
        guard let capacity else { return }
        while order.count > capacity {
            entries[order.removeFirst()] = nil
        }
    }

    /// Empties the cache.
    public func removeAll() {
        entries.removeAll()
        order.removeAll()
    }
}
