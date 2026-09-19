import DecisionModels
import Foundation
import Synchronization

@testable import DecisionModelsTypeSafe

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// MARK: A transport with a script

/// One scripted reply: a status with a body, or a failure that never reaches
/// the service.
struct Reply: Sendable {
    var status: Int = 200
    var body: String = "{}"
    var headers: [String: String] = [:]
    var failure: URLError?

    static func ok(_ body: String, headers: [String: String] = [:]) -> Reply {
        Reply(status: 200, body: body, headers: headers)
    }

    static func status(
        _ status: Int,
        body: String = "{}",
        headers: [String: String] = [:]
    ) -> Reply {
        Reply(status: status, body: body, headers: headers)
    }

    static func failure(_ code: URLError.Code = .networkConnectionLost) -> Reply {
        Reply(failure: URLError(code))
    }
}

/// A transport that answers from a script and keeps what it was sent.
///
/// It runs off the end of the script with a failure, so a test that expects
/// too few tries fails loudly.
final class ScriptedTransport: HTTPTransport {
    private static let fallbackURL = URL(string: "https://api.typesafe.ai/v1/systemone")!

    private let replies: [Reply]
    private let clock: FakeClock?
    private let log = Mutex<[URLRequest]>([])

    init(_ replies: [Reply], clock: FakeClock? = nil) {
        self.replies = replies
        self.clock = clock
    }

    /// Every request the model sent, in order.
    var sent: [URLRequest] { log.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let index = log.withLock { log -> Int in
            log.append(request)
            return log.count - 1
        }
        guard index < replies.count else {
            throw URLError(.unknown)
        }
        let reply = replies[index]
        if let failure = reply.failure {
            // An attempt that times out spends every second it was given.
            if failure.code == .timedOut {
                clock?.advance(.seconds(request.timeoutInterval))
            }
            throw failure
        }
        guard
            let response = HTTPURLResponse(
                url: request.url ?? Self.fallbackURL,
                statusCode: reply.status,
                httpVersion: "HTTP/1.1",
                headerFields: reply.headers
            )
        else {
            throw URLError(.badServerResponse)
        }
        return (Data(reply.body.utf8), response)
    }
}

/// Stands in for the clock, so a test of waits and deadlines runs at full
/// speed. Waiting moves this clock and nothing else, and an attempt moves it
/// by what it spent.
final class FakeClock: Sendable {
    private struct Ticker: Sendable {
        var now: ContinuousClock.Instant
        var waits: [Duration] = []
    }

    private let start: ContinuousClock.Instant
    private let ticker: Mutex<Ticker>

    init() {
        let start = ContinuousClock().now
        self.start = start
        self.ticker = Mutex(Ticker(now: start))
    }

    /// Every wait the model asked for, in order.
    var waited: [Duration] { ticker.withLock { $0.waits } }

    /// How far the clock has moved: the waits and what the attempts spent.
    var elapsed: Duration { start.duration(to: ticker.withLock { $0.now }) }

    /// Moves the clock without recording a wait.
    func advance(_ duration: Duration) {
        ticker.withLock { $0.now = $0.now + duration }
    }

    /// The clock to hand the model.
    var reading: @Sendable () -> ContinuousClock.Instant {
        { self.ticker.withLock { $0.now } }
    }

    /// The wait to hand the model. It records the wait and moves the clock.
    var record: @Sendable (Duration) async -> Void {
        { duration in
            self.ticker.withLock { ticker in
                ticker.waits.append(duration)
                ticker.now = ticker.now + duration
            }
        }
    }
}

/// A model, its transport, and its clock, wired together.
struct Harness {
    var model: Jev
    var transport: ScriptedTransport
    var clock: FakeClock
}

/// Builds a model that talks to a script instead of the network.
func harness(
    _ replies: [Reply],
    retry: RetryPolicy = .default,
    apiKey: String? = "test-key",
    version: String = "jev-latest",
    sleep: (@Sendable (Duration) async -> Void)? = nil
) -> Harness {
    let clock = FakeClock()
    let transport = ScriptedTransport(replies, clock: clock)
    let model = Jev(
        version: version,
        apiKey: apiKey,
        retry: retry,
        transport: transport,
        environment: [:],
        sleep: sleep ?? clock.record,
        now: clock.reading
    )
    return Harness(model: model, transport: transport, clock: clock)
}

// MARK: Questions

/// The teams a ticket can go to.
enum Team: String, ChoiceOption, CaseIterable, Codable {
    case returns, shipping, billing

    var optionID: String { rawValue }

    var criterion: Criterion {
        switch self {
        case .returns:
            Criterion(
                "Exchanges and refunds",
                notFor: "Payment disputes",
                examples: ["wrong size", "arrived damaged"]
            )
        case .shipping: "Delivery issues"
        case .billing: "Payment problems"
        }
    }
}

/// How bad the problem is, low to high.
enum Severity: String, RatingLevel, CaseIterable, Codable {
    case cosmetic, degraded, blocking

    var optionID: String { rawValue }

    var criterion: Criterion {
        switch self {
        case .cosmetic: "Cosmetic; nothing stops working"
        case .degraded:
            Criterion(
                "A feature is broken, but a workaround exists",
                signals: ["reports an error"]
            )
        case .blocking: "Blocking; no workaround exists"
        }
    }

    static func < (left: Severity, right: Severity) -> Bool {
        let order = Array(allCases)
        return order.firstIndex(of: left)! < order.firstIndex(of: right)!
    }
}

/// The ticket the tests ask about.
let ticket: State = "Wrong size shoes arrived, I want my money back"

/// A questionnaire with one question of each kind.
func triage() -> Questionnaire {
    Questionnaire {
        Choose<Team>("team", "Which team should handle this ticket?")
        Rate<Severity>("severity", "How severe is the problem for the customer?")
        Verify("refund", "Does the customer ask for a refund?")
    }
}

func isClose(_ value: Double, _ expected: Double, within tolerance: Double = 0.01) -> Bool {
    abs(value - expected) <= tolerance
}
