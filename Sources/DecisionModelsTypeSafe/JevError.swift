import DecisionModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A reply the service refused, for the statuses that have no case of their
/// own. It travels inside `DecisionError.transport`.
public struct JevServerError: Error, Sendable, CustomStringConvertible {
    /// The HTTP status.
    public let status: Int
    /// What the service said, when it said anything.
    public let message: String?
    /// The `x-typesafe-request-id` header, for support.
    public let requestID: String?

    public init(status: Int, message: String? = nil, requestID: String? = nil) {
        self.status = status
        self.message = message
        self.requestID = requestID
    }

    public var description: String {
        var text = "TypeSafe answered \(status)"
        if let message { text += ": \(message)" }
        if let requestID { text += " (request \(requestID))" }
        return text
    }
}

/// Turns HTTP into `DecisionError`. Application code never sees a status
/// number.
enum JevError {
    /// The header the service answers a request id under.
    static let requestIDHeader = "x-typesafe-request-id"

    /// The statuses worth sending again.
    static func isTransient(_ status: Int) -> Bool {
        status == 429 || status == 529
    }

    /// Maps a refused reply. The caller has already spent its retries.
    static func decisionError(
        status: Int,
        body: Data,
        response: HTTPURLResponse
    ) -> DecisionError {
        let said = message(in: body)
        switch status {
        case 401:
            return .unauthorized
        case 422:
            return .invalidQuestion(id: "", reason: said ?? "The service refused the questions.")
        case 429:
            return .rateLimited(retryAfter: retryAfter(response))
        case 529:
            return .overloaded
        default:
            return .transport(
                JevServerError(status: status, message: said, requestID: requestID(response))
            )
        }
    }

    /// Maps a failure that never reached the service.
    static func decisionError(transport error: any Error) -> DecisionError {
        if let error = error as? DecisionError { return error }
        if let error = error as? URLError {
            return error.code == .timedOut ? .timeout : .transport(error)
        }
        return .transport(error)
    }

    /// The caller's own cancellation, when that is what went wrong.
    ///
    /// Cancellation is not a provider failure, so it travels as itself and
    /// `catch is CancellationError` works at the call site.
    static func cancellation(_ error: any Error) -> CancellationError? {
        if error is CancellationError { return CancellationError() }
        if let error = error as? URLError, error.code == .cancelled { return CancellationError() }
        return nil
    }

    /// The `Retry-After` header, read as a count of seconds.
    static func retryAfter(_ response: HTTPURLResponse) -> Duration? {
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        guard let seconds = Double(header.trimmingCharacters(in: .whitespaces)),
            seconds.isFinite, seconds >= 0
        else { return nil }
        return .seconds(seconds)
    }

    /// The provider's own id for the request.
    static func requestID(_ response: HTTPURLResponse) -> String? {
        guard let id = response.value(forHTTPHeaderField: requestIDHeader), !id.isEmpty else {
            return nil
        }
        return id
    }

    /// What the service said went wrong.
    ///
    /// The error bodies of hosted services differ, so this reads the common
    /// fields and falls back to the body itself.
    static func message(in body: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: body),
            let fields = object as? [String: Any]
        {
            if let message = fields["message"] as? String { return message }
            if let message = fields["detail"] as? String { return message }
            if let error = fields["error"] as? String { return error }
            if let error = fields["error"] as? [String: Any] {
                if let message = error["message"] as? String { return message }
                if let message = error["detail"] as? String { return message }
            }
        }
        let text = String(decoding: body, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(500))
    }
}
