import DecisionModels
import Synchronization

/// A model that answers from a closure.
///
/// Nothing is sent anywhere. A test returns the answers it wants, either a
/// fixed set or one built from the request, and reads `callCount` to check
/// that the session did or did not reach the model.
public struct ScriptedModel: DecisionModel {
    public let identity: DecisionModelIdentity
    public let capabilities: DecisionModelCapabilities
    private let reported: DecisionModelAvailability
    private let script: @Sendable (DecisionRequest) async throws -> Answers
    private let counter = CallCounter()

    /// Builds a model that runs `answer` on every request.
    ///
    /// The defaults allow everything, so a test only states the limit it is
    /// about.
    public init(
        identity: DecisionModelIdentity = .init(provider: "test", name: "scripted"),
        capabilities: DecisionModelCapabilities = .init(
            probabilityQuality: .calibrated,
            structuredCriteria: true,
            structuredInstructions: true,
            supportsRepeatedSamples: true
        ),
        availability: DecisionModelAvailability = .available,
        _ answer: @escaping @Sendable (DecisionRequest) async throws -> Answers
    ) {
        self.identity = identity
        self.capabilities = capabilities
        self.reported = availability
        self.script = answer
    }

    /// Builds a model that gives the same answers every time.
    public init(
        answering answers: Answers,
        identity: DecisionModelIdentity = .init(provider: "test", name: "scripted"),
        capabilities: DecisionModelCapabilities = .init(
            probabilityQuality: .calibrated,
            structuredCriteria: true,
            structuredInstructions: true,
            supportsRepeatedSamples: true
        ),
        availability: DecisionModelAvailability = .available
    ) {
        self.init(identity: identity, capabilities: capabilities, availability: availability) { _ in
            answers
        }
    }

    public var availability: DecisionModelAvailability {
        get async { reported }
    }

    /// Runs the script. Usage is zero, because nothing was spent.
    public func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        counter.increment()
        return ModelResponse(answers: try await script(request), usage: .zero, requestID: nil)
    }

    /// How many requests reached the script, failures included.
    ///
    /// Every copy of one model shares the count.
    public var callCount: Int { counter.count }
}

/// A counter that a value type can share.
///
/// `Mutex` cannot be copied, so it lives behind a reference and every copy of
/// a `ScriptedModel` counts into the same box.
private final class CallCounter: Sendable {
    private let calls = Mutex<Int>(0)

    func increment() {
        calls.withLock { $0 += 1 }
    }

    var count: Int { calls.withLock { $0 } }
}
