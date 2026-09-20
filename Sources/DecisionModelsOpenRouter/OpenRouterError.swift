import DecisionModels
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A reply OpenRouter refused, for the statuses that have no case of their
/// own. It travels inside `DecisionError.transport`.
public struct OpenRouterServerError: Error, Sendable, CustomStringConvertible {
    /// The HTTP status.
    public let status: Int
    /// What OpenRouter said, when it said anything.
    public let message: String?
    /// OpenRouter's own code for the failure, when the body carries one.
    public let code: String?

    public init(status: Int, message: String? = nil, code: String? = nil) {
        self.status = status
        self.message = message
        self.code = code
    }

    public var description: String {
        var text = "OpenRouter answered \(status)"
        if let code { text += " (\(code))" }
        if let message { text += ": \(message)" }
        return text
    }
}

/// Turns HTTP into `DecisionError`. Application code never sees a status
/// number.
enum OpenRouterError {
    /// The statuses worth sending again: a rate limit, a failing upstream
    /// provider, an overload, a gateway timeout, and a provider error.
    static func isTransient(_ status: Int) -> Bool {
        [429, 502, 503, 524, 529].contains(status)
    }

    /// Maps a refused reply. The caller has already spent its retries.
    static func decisionError(
        status: Int,
        body: Data,
        response: HTTPURLResponse
    ) -> DecisionError {
        let said = message(in: body)
        switch status {
        case 400:
            return .invalidQuestion(id: "", reason: said ?? "OpenRouter refused the request.")
        case 401, 403:
            return .unauthorized
        case 402:
            return .unavailable(.other(said ?? "OpenRouter reports insufficient credits."))
        case 413:
            return .contextSizeExceeded(limit: nil, estimated: nil)
        case 429:
            return .rateLimited(retryAfter: HTTPClient.retryAfter(response))
        case 503:
            return .overloaded
        case 524:
            return .timeout
        default:
            return .transport(
                OpenRouterServerError(status: status, message: said, code: code(in: body))
            )
        }
    }

    /// What OpenRouter said went wrong.
    ///
    /// The documented shape is `error.message`. The other fields are the
    /// ones hosted services commonly use, and the body itself is the last
    /// resort.
    static func message(in body: Data) -> String? {
        if let fields = object(body) {
            if let error = fields["error"] as? [String: Any] {
                if let message = error["message"] as? String { return message }
                if let message = error["detail"] as? String { return message }
            }
            if let message = fields["message"] as? String { return message }
            if let message = fields["detail"] as? String { return message }
            if let error = fields["error"] as? String { return error }
        }
        let text = String(decoding: body, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(500))
    }

    /// OpenRouter's code for the failure: `error.code`, a number or a string.
    static func code(in body: Data) -> String? {
        guard let error = object(body)?["error"] as? [String: Any] else { return nil }
        if let code = error["code"] as? Int { return String(code) }
        if let code = error["code"] as? String { return code }
        return nil
    }

    /// The body as a JSON object, when it is one.
    private static func object(_ body: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }
}
