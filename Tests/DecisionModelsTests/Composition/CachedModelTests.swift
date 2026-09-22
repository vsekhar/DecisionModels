import Testing

@testable import DecisionModels

/// The one answer every request in this suite gets.
private let stored = Answers(
    records: [
        "team": .choice(
            reported: "returns",
            probabilities: ["returns": 0.9, "shipping": 0.05, "billing": 0.05],
            confidence: 0.9
        )
    ],
    quality: .calibrated
)

private let teamQuestionnaire = Questionnaire([
    Choose("team", "Which team handles this ticket?", among: Array(Team.allCases)).spec
])

/// A request about one message, with tags that a cache must ignore.
private func ask(
    _ message: String,
    samples: Int = 1,
    timeout: Duration? = nil,
    metadata: [String: String] = [:]
) -> DecisionRequest {
    DecisionRequest(
        state: .text(message),
        questionnaire: teamQuestionnaire,
        samples: samples,
        timeout: timeout,
        metadata: metadata
    )
}

private func model() -> FakeModel {
    FakeModel(
        answers: stored,
        usage: Usage(inputTokens: 5, outputTokens: 2, requests: 1),
        requestID: "call-1"
    )
}

@Suite("Cached")
struct CachedModelTests {
    @Test("A hit skips the model and reports no usage")
    func hitSkipsTheModel() async throws {
        let inner = model()
        let cached = CachedModel(inner, storage: InMemoryDecisionCache())

        let miss = try await cached.decide(ask("The blender arrived broken."))
        let hit = try await cached.decide(ask("The blender arrived broken."))

        #expect(inner.callCount == 1)
        #expect(miss.usage == Usage(inputTokens: 5, outputTokens: 2, requests: 1))
        #expect(hit.usage == .zero)
        #expect(hit.requestID == "call-1")
        #expect(hit.answers.records == stored.records)
        #expect(hit.answers.quality == .calibrated)
    }

    @Test("A miss stores the answer under the request and the model")
    func missStores() async throws {
        let inner = model()
        let cache = InMemoryDecisionCache()
        let request = ask("The blender arrived broken.")

        _ = try await CachedModel(inner, storage: cache).decide(request)

        let key = CacheKey(request, model: inner.identity)
        #expect(await cache.response(for: key)?.requestID == "call-1")
        #expect(await cache.count == 1)
    }

    @Test("Metadata and timeout do not change the key")
    func tagsDoNotMiss() async throws {
        let inner = model()
        let cached = CachedModel(inner, storage: InMemoryDecisionCache())

        _ = try await cached.decide(ask("broken", metadata: ["tenant": "acme"]))
        _ = try await cached.decide(ask("broken", timeout: .seconds(30)))
        _ = try await cached.decide(ask("broken", metadata: ["tenant": "other"]))

        #expect(inner.callCount == 1)
    }

    @Test("A different state or a different number of draws misses")
    func differentRequestsMiss() async throws {
        let inner = model()
        let cached = CachedModel(inner, storage: InMemoryDecisionCache())

        _ = try await cached.decide(ask("broken"))
        _ = try await cached.decide(ask("late"))
        _ = try await cached.decide(ask("broken", samples: 3))

        #expect(inner.callCount == 3)
    }

    @Test("No state and an empty object are different keys")
    func noStateIsNotAnEmptyObject() async throws {
        let inner = model()
        let cache = InMemoryDecisionCache()
        let cached = CachedModel(inner, storage: cache)

        _ = try await cached.decide(DecisionRequest(questionnaire: teamQuestionnaire))
        _ = try await cached.decide(
            DecisionRequest(state: .object([:]), questionnaire: teamQuestionnaire)
        )

        #expect(inner.callCount == 2)
        #expect(await cache.count == 2)
    }

    @Test("Two requests with no state share a key")
    func noStateHits() async throws {
        let inner = model()
        let cached = CachedModel(inner, storage: InMemoryDecisionCache())

        _ = try await cached.decide(DecisionRequest(questionnaire: teamQuestionnaire))
        _ = try await cached.decide(
            DecisionRequest(questionnaire: teamQuestionnaire, metadata: ["trace": "t-2"])
        )

        #expect(inner.callCount == 1)
    }

    @Test("The same state asked of a different model misses")
    func modelIsPartOfTheKey() async throws {
        let cache = InMemoryDecisionCache()
        let apple = FakeModel(identity: DecisionModelIdentity(provider: "apple", name: "on-device")) {
            _ in ModelResponse(answers: stored)
        }
        let jev = FakeModel(identity: DecisionModelIdentity(provider: "typesafe", name: "jev")) {
            _ in ModelResponse(answers: stored)
        }

        _ = try await CachedModel(apple, storage: cache).decide(ask("broken"))
        _ = try await CachedModel(jev, storage: cache).decide(ask("broken"))

        #expect(apple.callCount == 1)
        #expect(jev.callCount == 1)
        #expect(await cache.count == 2)
    }

    @Test("A full cache drops the oldest answer")
    func capacityEvicts() async throws {
        let inner = model()
        let cache = InMemoryDecisionCache(capacity: 1)
        let cached = CachedModel(inner, storage: cache)

        _ = try await cached.decide(ask("broken"))
        _ = try await cached.decide(ask("late"))
        _ = try await cached.decide(ask("broken"))

        #expect(inner.callCount == 3)
        #expect(await cache.count == 1)
    }

    @Test("The identity and the capabilities are the model's own")
    func forwardsIdentityAndCapabilities() {
        let inner = FakeModel(
            answers: stored,
            capabilities: DecisionModelCapabilities(
                probabilityQuality: .calibrated,
                maximumOptionsPerChoice: 42
            )
        )
        let cached = CachedModel(inner, storage: InMemoryDecisionCache())

        #expect(cached.identity == inner.identity)
        #expect(cached.capabilities.maximumOptionsPerChoice == 42)
        #expect(cached.capabilities.probabilityQuality == .calibrated)
    }

    @Test("prewarm and availability reach the model")
    func forwards() async {
        let spy = PrewarmSpy()
        let cached = CachedModel(spy, storage: InMemoryDecisionCache())

        await cached.prewarm()

        #expect(spy.prewarmCount == 1)
        guard case .available = await cached.availability else {
            Issue.record("The model is available, so the cache is.")
            return
        }
    }
}
