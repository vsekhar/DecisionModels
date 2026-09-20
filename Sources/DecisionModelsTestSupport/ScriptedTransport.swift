import DecisionModels
import Foundation
import Synchronization

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One scripted reply: a status with a body, or a failure that never reaches
/// the service.
package struct Reply: Sendable {
    package var status: Int = 200
    package var body: String = "{}"
    package var headers: [String: String] = [:]
    package var failure: URLError?

    package init(
        status: Int = 200,
        body: String = "{}",
        headers: [String: String] = [:],
        failure: URLError? = nil
    ) {
        self.status = status
        self.body = body
        self.headers = headers
        self.failure = failure
    }

    package static func ok(_ body: String, headers: [String: String] = [:]) -> Reply {
        Reply(status: 200, body: body, headers: headers)
    }

    package static func status(
        _ status: Int,
        body: String = "{}",
        headers: [String: String] = [:]
    ) -> Reply {
        Reply(status: status, body: body, headers: headers)
    }

    package static func failure(_ code: URLError.Code = .networkConnectionLost) -> Reply {
        Reply(failure: URLError(code))
    }
}

/// A transport that answers from a script and keeps what it was sent.
///
/// It runs off the end of the script with a failure, so a test that expects
/// too few tries fails loudly.
package final class ScriptedTransport: HTTPTransport {
    private static let fallbackURL = URL(string: "https://example.invalid/")!

    private let replies: [Reply]
    private let clock: FakeClock?
    private let log = Mutex<[URLRequest]>([])

    package init(_ replies: [Reply], clock: FakeClock? = nil) {
        self.replies = replies
        self.clock = clock
    }

    /// Every request the model sent, in order.
    package var sent: [URLRequest] { log.withLock { $0 } }

    package func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
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
