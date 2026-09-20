import DecisionModels
import DecisionModelsTestSupport
import Foundation
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The client's own contract, apart from any provider: which statuses it
/// sends again, what it hands back when it stops, and how it reads
/// `Retry-After`. The Jev retry tests cover the deadline and the waits.
@Suite("HTTP client")
struct HTTPClientTests {
    private static let url = URL(string: "https://example.com/decide")!

    /// A client over a script and a fake clock that sends again on the
    /// statuses `transient` names.
    private func client(
        _ replies: [Reply],
        retry: RetryPolicy = .default,
        transient: @escaping @Sendable (Int) -> Bool
    ) -> (client: HTTPClient, transport: ScriptedTransport, clock: FakeClock) {
        let clock = FakeClock()
        let transport = ScriptedTransport(replies, clock: clock)
        let client = HTTPClient(
            transport: transport,
            policy: retry,
            transient: transient,
            sleep: clock.record,
            now: clock.reading
        )
        return (client, transport, clock)
    }

    @Test("The predicate decides which statuses are worth sending again")
    func predicateRetries() async throws {
        let fake = client([.status(503), .ok("{}")], transient: { $0 == 503 })
        let (_, response) = try await fake.client.send(URLRequest(url: Self.url))
        #expect(response.statusCode == 200)
        #expect(fake.transport.sent.count == 2)
        #expect(fake.clock.waited == [.milliseconds(500)])
    }

    @Test("A 2xx comes back at once, whatever the predicate says")
    func successReturnsAtOnce() async throws {
        let fake = client([.status(204), .ok("{}")], transient: { _ in true })
        let (_, response) = try await fake.client.send(URLRequest(url: Self.url))
        #expect(response.statusCode == 204)
        #expect(fake.transport.sent.count == 1)
        #expect(fake.clock.waited.isEmpty)
    }

    @Test("A status the predicate rejects comes back as a reply, not an error")
    func rejectedStatusReturns() async throws {
        let fake = client([.status(503, body: "down"), .ok("{}")], transient: { $0 == 429 })
        let (data, response) = try await fake.client.send(URLRequest(url: Self.url))
        #expect(response.statusCode == 503)
        #expect(String(decoding: data, as: UTF8.self) == "down")
        #expect(fake.transport.sent.count == 1)
        #expect(fake.clock.waited.isEmpty)
    }

    @Test("A transient status that never lets up comes back as the last reply")
    func exhaustedRetriesReturnTheLastReply() async throws {
        let fake = client(
            Array(repeating: .status(429, headers: ["Retry-After": "1"]), count: 4),
            transient: { $0 == 429 }
        )
        let (_, response) = try await fake.client.send(URLRequest(url: Self.url))
        #expect(response.statusCode == 429)
        #expect(response.value(forHTTPHeaderField: "Retry-After") == "1")
        #expect(fake.transport.sent.count == 4)
        #expect(fake.clock.waited == [.seconds(1), .seconds(1), .seconds(1)])
    }

    @Test("Retry-After reads a count of seconds and nothing else")
    func retryAfterParsing() throws {
        func reply(_ header: String?) -> HTTPURLResponse {
            HTTPURLResponse(
                url: Self.url,
                statusCode: 429,
                httpVersion: "HTTP/1.1",
                headerFields: header.map { ["Retry-After": $0] } ?? [:]
            )!
        }
        #expect(HTTPClient.retryAfter(reply("2")) == .seconds(2))
        #expect(HTTPClient.retryAfter(reply(" 1.5 ")) == .seconds(1.5))
        #expect(HTTPClient.retryAfter(reply("0")) == .zero)
        #expect(HTTPClient.retryAfter(reply("")) == nil)
        #expect(HTTPClient.retryAfter(reply("-1")) == nil)
        #expect(HTTPClient.retryAfter(reply("inf")) == nil)
        #expect(HTTPClient.retryAfter(reply("Wed, 21 Oct 2026 07:28:00 GMT")) == nil)
        #expect(HTTPClient.retryAfter(reply(nil)) == nil)
    }
}
