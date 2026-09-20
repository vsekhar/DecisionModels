import DecisionModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// OpenRouter's Decisions endpoint, while it is in alpha.
///
/// `OpenRouterAlpha` maps a request one for one onto
/// `POST /api/alpha/decisions`: a choice, a score, and a noul per question,
/// with instructions and criteria as text or as JSON. OpenRouter forwards the
/// request to the model named in `model`, such as `typesafe/jev-1.13`, and
/// the provider keeps the named choice, the score, and the confidence that
/// come back.
///
/// The endpoint is alpha. OpenRouter may change it or remove it without
/// notice. When it leaves alpha, a plain `OpenRouter` type will replace this
/// one, so every call site re-acknowledges the change by changing the type
/// name.
///
/// The caller names the model. There is no default, and OpenRouter documents
/// no endpoint that lists decision models, so the name comes from
/// OpenRouter's docs.
///
/// ```swift
/// let session = DecisionSession(model: OpenRouterAlpha(model: "typesafe/jev-1.13"))
/// let triage = try await session.decide(Triage.self, about: ticket)
/// ```
public struct OpenRouterAlpha: DecisionModel {
    /// The variable the key comes from when the caller passes none.
    public static let apiKeyVariable = "OPENROUTER_API_KEY"

    /// The model this provider asks for, in OpenRouter's `vendor/model` form.
    public let model: String

    /// How often the provider sends again after a rate limit, an overload, a
    /// gateway failure, or a transport failure.
    public let retry: RetryPolicy

    private let key: String?
    private let baseURL: URL
    private let client: HTTPClient

    /// Builds a model.
    ///
    /// The key is the argument, or `OPENROUTER_API_KEY` from the environment.
    /// Without a key the model is unavailable and never sends anything.
    public init(
        model: String,
        apiKey: String? = nil,
        retry: RetryPolicy = .default,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.init(
            model: model,
            apiKey: apiKey,
            retry: retry,
            transport: transport,
            environment: ProcessInfo.processInfo.environment
        )
    }

    /// The initializer the tests use: the environment, the host, the wait, and
    /// the clock are all arguments, so no test depends on the shell or on how
    /// long it really runs.
    init(
        model: String,
        apiKey: String? = nil,
        retry: RetryPolicy = .default,
        transport: any HTTPTransport = URLSessionTransport(),
        environment: [String: String],
        baseURL: URL = OpenRouterAlpha.productionHost,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now }
    ) {
        let candidate = apiKey ?? environment[OpenRouterAlpha.apiKeyVariable]
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        self.key = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.retry = retry
        self.baseURL = baseURL
        self.client = HTTPClient(
            transport: transport,
            policy: retry,
            transient: OpenRouterError.isTransient,
            sleep: sleep,
            now: now
        )
    }

    /// The host the provider talks to.
    static let productionHost = URL(string: "https://openrouter.ai")!

    // MARK: The model

    public var identity: DecisionModelIdentity {
        DecisionModelIdentity(provider: "openrouter", name: model)
    }

    /// What the model can do.
    ///
    /// These are Jev's capabilities and Jev's calibrated probabilities,
    /// because `typesafe/jev-1.13` is the one decision model OpenRouter
    /// serves in the alpha. That is an assumption tied to the alpha, not a
    /// property of the endpoint. A model with other limits needs its own
    /// capabilities here.
    public var capabilities: DecisionModelCapabilities {
        DecisionModelCapabilities(
            probabilityQuality: .calibrated,
            structuredCriteria: true,
            structuredInstructions: true,
            maximumOptionsPerChoice: 255,
            maximumLevelsPerRating: 10,
            maximumQuestionsPerRequest: nil,
            contextTokens: 64_000,
            supportsRepeatedSamples: false
        )
    }

    public var availability: DecisionModelAvailability {
        get async {
            key == nil
                ? .unavailable(.notConfigured(OpenRouterAlpha.apiKeyVariable))
                : .available
        }
    }

    public func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        guard let key else {
            throw DecisionError.unavailable(.notConfigured(OpenRouterAlpha.apiKeyVariable))
        }
        guard request.samples <= 1 else {
            throw DecisionError.unsupported(.repeatedSamples)
        }
        let body = OpenRouterRequest(
            model: model,
            state: request.state,
            questions: OpenRouterMapping.questions(request.questionnaire)
        )
        var call = URLRequest(url: baseURL.appending(path: "api/alpha/decisions"))
        call.httpMethod = "POST"
        call.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            call.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw DecisionError.transport(error)
        }
        let (data, response) = try await client.send(call, timeout: request.timeout)
        guard (200..<300).contains(response.statusCode) else {
            throw OpenRouterError.decisionError(
                status: response.statusCode, body: data, response: response
            )
        }
        return try OpenRouterMapping.modelResponse(data)
    }
}
