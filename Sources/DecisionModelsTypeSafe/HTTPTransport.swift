import DecisionModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Sends one HTTP request and waits for the reply.
///
/// The provider reaches the network through this protocol only, so a test can
/// script replies without a server.
public protocol HTTPTransport: Sendable {
    /// Sends the request and gives back the body with the HTTP reply.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The transport the provider uses against the live service.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DecisionError.malformedResponse("The reply is not an HTTP response.")
        }
        return (data, http)
    }
}
