#if canImport(FoundationModels)
import FoundationModels

// Backports of FoundationModels names that a newer SDK introduced.
//
// Apple renames an API between SDKs and back-deploys the new name. The new
// spelling then runs on every OS the package supports, but only the newer
// SDK declares it, and that SDK deprecates the old spelling, which fails
// `-warnings-as-errors`. The OS at run time is not the question, so
// `#available` cannot choose. The SDK is.
//
// Swift has one SDK-level condition: `canImport(Module, _version: X)`. It is
// true when the module's `user-module-version` stamp, read from its
// `.swiftinterface` inside the SDK, is greater than or equal to `X`,
// compared component by component. So a threshold of 2.0 holds for 2.0,
// 2.1, and 3.0 alike, and every later SDK keeps taking the new path.
//
// A `#if` cannot live inside a function, so this file cannot offer one
// check for callers to share. It does the next best thing. Each backport
// below sits behind `#if !canImport(FoundationModels, _version: <stamp>)`,
// where `<stamp>` is the first SDK that declares the new name, and defines
// that name in terms of the old one. The rest of the target then uses the
// new name with no condition and no comment. When CI's oldest SDK reaches
// the stamp, delete the backport; nothing else changes.
//
// To read a stamp:
//
//     grep -o 'user-module-version [0-9.]*' "$(xcrun --show-sdk-path)"\
//       /System/Library/Frameworks/FoundationModels.framework/Modules\
//       /FoundationModels.swiftmodule/arm64-apple-macos.swiftinterface
//
// The stamps are documented nowhere else. The newer SDK checks the modern
// path locally; the older SDK's path is checked only by CI, which pins the
// oldest Xcode the package supports. See TESTING.md.
//
// Known stamps:
//
// | SDK                   | FoundationModels |
// |-----------------------|------------------|
// | macOS 27.0, iOS 27.0  | 2.0.68.1.402     |

// MARK: - The 27 SDK renames `sampling` to `samplingMode`

#if !canImport(FoundationModels, _version: 2.0)
@available(macOS 26, iOS 26, *)
extension GenerationOptions {
    /// The 27 SDK's spelling of `init(sampling:temperature:maximumResponseTokens:)`.
    ///
    /// `samplingMode` takes no default here, unlike the SDK's own, so a bare
    /// `GenerationOptions()` stays unambiguous on the older SDK.
    init(samplingMode: SamplingMode?, temperature: Double? = nil, maximumResponseTokens: Int? = nil) {
        self.init(
            sampling: samplingMode,
            temperature: temperature,
            maximumResponseTokens: maximumResponseTokens
        )
    }

    /// The 27 SDK's name for `sampling`.
    var samplingMode: SamplingMode? {
        get { sampling }
        set { sampling = newValue }
    }
}
#endif
#endif
