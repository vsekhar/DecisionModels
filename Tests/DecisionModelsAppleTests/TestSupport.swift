import DecisionModels
import Testing

/// Helpers the Apple test suites share.
///
/// Swift Testing in this toolchain refuses `@available` on a `@Test` or a
/// `@Suite`, so a test that needs macOS 26 guards its body with
/// `guard #available(...) else { return needsMacOS26() }` instead. The OS is
/// a failure, never a skip: a test that quietly passes on macOS 15 proves
/// nothing.
func needsMacOS26(sourceLocation: SourceLocation = #_sourceLocation) {
    Issue.record(
        "These tests need macOS 26 or iOS 26 for FoundationModels.",
        sourceLocation: sourceLocation
    )
}

/// The same, for the token counting that arrived in 26.4.
func needsMacOS264(sourceLocation: SourceLocation = #_sourceLocation) {
    Issue.record(
        "This test needs macOS 26.4 or iOS 26.4 for tokenCount(for:).",
        sourceLocation: sourceLocation
    )
}

/// Fails unless the body throws `DecisionError.malformedResponse`.
func expectMalformed(
    _ what: String,
    _ body: () throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    do {
        try body()
        Issue.record("The mapping accepted \(what).", sourceLocation: sourceLocation)
    } catch DecisionError.malformedResponse {
        // Expected.
    } catch {
        Issue.record(
            "\(what) threw \(error) instead of a malformed response.",
            sourceLocation: sourceLocation
        )
    }
}

func isClose(_ value: Double, _ expected: Double, within tolerance: Double = 1e-9) -> Bool {
    abs(value - expected) <= tolerance
}
