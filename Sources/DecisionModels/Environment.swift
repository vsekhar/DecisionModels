#if canImport(SwiftUI)
import SwiftUI

/// Written by hand rather than with `@Entry`, because that macro's plugin ships
/// only inside Xcode. A toolchain with the Command Line Tools alone cannot
/// expand it.
private struct DecisionSessionKey: EnvironmentKey {
    static let defaultValue: DecisionSession? = nil
}

extension EnvironmentValues {
    /// The session views decide with. Inject one at the root, and the whole app
    /// changes model in one place.
    public var decisionSession: DecisionSession? {
        get { self[DecisionSessionKey.self] }
        set { self[DecisionSessionKey.self] = newValue }
    }
}
#endif
