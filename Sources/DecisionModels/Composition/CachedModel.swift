/// Serves a stored answer when the same request comes again.
///
/// A hit costs nothing, so it reports no usage. It keeps the provider's own
/// request id, which says which call the answer came from. DESIGN.md section
/// 10.2.
public struct CachedModel: DecisionModel {
    /// The model that answers a miss.
    public let model: any DecisionModel
    /// Where the answers live.
    public let storage: any DecisionCache

    public init(_ model: some DecisionModel, storage: some DecisionCache) {
        self.model = model
        self.storage = storage
    }

    public var identity: DecisionModelIdentity { model.identity }

    public var capabilities: DecisionModelCapabilities { model.capabilities }

    public var availability: DecisionModelAvailability {
        get async { await model.availability }
    }

    public func prewarm() async {
        await model.prewarm()
    }

    public func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        let key = CacheKey(request, model: model.identity)
        if let stored = await storage.response(for: key) {
            return ModelResponse(
                answers: stored.answers,
                usage: .zero,
                requestID: stored.requestID
            )
        }
        let response = try await model.decide(request)
        await storage.store(response, for: key)
        return response
    }
}
