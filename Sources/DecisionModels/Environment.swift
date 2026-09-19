#if canImport(SwiftUI)
import SwiftUI

extension EnvironmentValues {
    /// The session views decide with. Inject one at the root, and the whole app
    /// changes model in one place.
    @Entry public var decisionSession: DecisionSession?
}
#endif
