import DecisionModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The TypeSafe hosted model.
///
/// `Jev` maps a request one for one onto `POST /v1/systemone`: a choice, a
/// score, and a noul per question, with instructions and criteria as text or
/// as JSON. It reports calibrated probabilities and keeps the named choice,
/// the score, and the confidence the service returns.
///
/// ```swift
/// let session = DecisionSession(model: Jev.latest)
/// let triage = try await session.decide(Triage.self, about: ticket)
/// ```
public struct Jev: DecisionModel {
    /// The variable the key comes from when the caller passes none.
    public static let apiKeyVariable = "TYPESAFE_API_KEY"

    /// The newest released model.
    public static let latest = Jev()

    /// The model under test at the vendor.
    public static let preview = Jev(version: "jev-preview")

    /// The alias or pinned version this model asks for.
    public let version: String

    /// How often the provider sends again after a rate limit, an overload, or
    /// a transport failure.
    public let retry: RetryPolicy

    private let key: String?
    private let transport: any HTTPTransport
    private let baseURL: URL
    private let sleep: @Sendable (Duration) async -> Void
    private let now: @Sendable () -> ContinuousClock.Instant

    /// Builds a model.
    ///
    /// The key is the argument, or `TYPESAFE_API_KEY` from the environment.
    /// Without a key the model is unavailable and never sends anything.
    public init(
        version: String = "jev-latest",
        apiKey: String? = nil,
        retry: RetryPolicy = .default,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.init(
            version: version,
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
        version: String = "jev-latest",
        apiKey: String? = nil,
        retry: RetryPolicy = .default,
        transport: any HTTPTransport = URLSessionTransport(),
        environment: [String: String],
        baseURL: URL = Jev.productionHost,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now }
    ) {
        let candidate = apiKey ?? environment[Jev.apiKeyVariable]
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.version = version
        self.key = (trimmed?.isEmpty ?? true) ? nil : trimmed
        self.retry = retry
        self.transport = transport
        self.baseURL = baseURL
        self.sleep = sleep
        self.now = now
    }

    /// The host the provider talks to.
    static let productionHost = URL(string: "https://api.typesafe.ai")!

    // MARK: The model

    public var identity: DecisionModelIdentity {
        DecisionModelIdentity(provider: "typesafe", name: version)
    }

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
            key == nil ? .unavailable(.notConfigured(Jev.apiKeyVariable)) : .available
        }
    }

    public func decide(_ request: DecisionRequest) async throws -> ModelResponse {
        let key = try apiKey()
        guard request.samples <= 1 else {
            throw DecisionError.unsupported(.repeatedSamples)
        }
        let body = JevRequest(
            state: request.state,
            model: version,
            questions: JevMapping.questions(request.questionnaire)
        )
        var call = URLRequest(url: baseURL.appending(path: "v1/systemone"))
        call.httpMethod = "POST"
        call.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        call.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            call.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw DecisionError.transport(error)
        }
        let (data, response) = try await send(call, timeout: request.timeout)
        return try JevMapping.modelResponse(data: data, response: response)
    }

    /// Lists the models the account can call.
    public func models() async throws -> [ModelCard] {
        let key = try apiKey()
        var call = URLRequest(url: baseURL.appending(path: "v1/models"))
        call.httpMethod = "GET"
        call.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await send(call)
        return try JevMapping.modelCards(data)
    }

    // MARK: Sending

    private func apiKey() throws -> String {
        guard let key else {
            throw DecisionError.unavailable(.notConfigured(Jev.apiKeyVariable))
        }
        return key
    }

    /// Sends, and sends again while the failure says that helps.
    ///
    /// The timeout is what the caller waits for the answer, tries and waits
    /// counted in, so it becomes a deadline for the whole call and bounds
    /// every attempt and every pause under it.
    private func send(
        _ request: URLRequest,
        timeout: Duration? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        let deadline = timeout.map { now() + $0 }
        var retries = 0
        while true {
            var attempt = request
            if let timeout, let deadline {
                attempt.timeoutInterval = min(timeout, try left(until: deadline)).timeInterval
            }
            do {
                let (data, response) = try await transport.send(attempt)
                guard !(200..<300).contains(response.statusCode) else { return (data, response) }
                guard JevError.isTransient(response.statusCode), retries < retry.maxRetries else {
                    throw JevError.decisionError(
                        status: response.statusCode, body: data, response: response
                    )
                }
                retries += 1
                // A service that asks for a long wait still waits no longer
                // than the policy allows.
                let asked = JevError.retryAfter(response) ?? retry.backoff(retry: retries)
                try await pause(min(asked, retry.maximumBackoff), until: deadline)
            } catch let error as DecisionError {
                throw error
            } catch {
                // The caller's own cancellation travels as itself.
                if let cancellation = JevError.cancellation(error) { throw cancellation }
                guard retries < retry.maxRetries else {
                    throw JevError.decisionError(transport: error)
                }
                retries += 1
                try await pause(retry.backoff(retry: retries), until: deadline)
            }
        }
    }

    /// Waits between two tries, and gives up when the caller has.
    private func pause(
        _ duration: Duration,
        until deadline: ContinuousClock.Instant?
    ) async throws {
        try Task.checkCancellation()
        var wait = duration
        if let deadline { wait = min(wait, try left(until: deadline)) }
        await sleep(wait)
        try Task.checkCancellation()
    }

    /// How much of the caller's time is left. None left is a timeout.
    private func left(until deadline: ContinuousClock.Instant) throws -> Duration {
        let remaining = now().duration(to: deadline)
        guard remaining > .zero else { throw DecisionError.timeout }
        return remaining
    }
}

/// One model the account can call.
public struct ModelCard: Sendable, Hashable, Codable {
    /// The name to pass as `version`, such as `jev-1.13.0`.
    public var name: String
    /// What the vendor says about it.
    public var description: String?
    /// When it shipped, as the service writes it.
    public var releaseDate: String?

    public init(name: String, description: String? = nil, releaseDate: String? = nil) {
        self.name = name
        self.description = description
        self.releaseDate = releaseDate
    }
}

extension Duration {
    /// The duration as a count of seconds, for `URLRequest`.
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
