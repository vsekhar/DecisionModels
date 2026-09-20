# DecisionModels

[![CI](https://github.com/vsekhar/DecisionModels/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/vsekhar/DecisionModels/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vsekhar/DecisionModels/branch/main/graph/badge.svg)](https://codecov.io/gh/vsekhar/DecisionModels)

Typed questions for decision models, in Swift.

A decision model does not write text. It reads some state, answers a fixed
set of questions, and returns a probability for each possible answer.
DecisionModels lets you declare those questions as a Swift type, ask them
in one call, and read the answers as plain Swift values with the full
probabilities one prefix away. The model behind the call can be a hosted
service, the on-device model on Apple platforms, or a test double, and the
application code does not change.

The design and its reasons are in [DESIGN.md](DESIGN.md).

## One example

```swift
import DecisionModels

@Options
enum Team {
    @Criterion("Exchanges and refunds")  case returns
    @Criterion("Delivery issues")        case shipping
    @Criterion("Payment problems")       case billing
}

@Levels   // declaration order is low to high
enum Severity {
    @Criterion("Cosmetic; no impact to functionality")               case cosmetic
    @Criterion("Broken or degraded feature, but a workaround exists") case degraded
    @Criterion("Blocking issue; no workaround exists")               case blocking
}

@Decision
struct TicketTriage {
    @Ask("Which team handles this ticket?")
    var team: Team

    @Ask("How severe is the reported issue?")
    var severity: Severity

    @Ask("Does the customer ask for a refund?")
    var requestsRefund: Bool

    var needsHuman: Bool {
        $team.confidence < 0.5 || (severity == .blocking && $severity.confidence < 0.8)
    }
}

let session = DecisionSession(model: Jev(version: "jev-latest"))
let triage: TicketTriage = try await session.decide(about: ticket.body)

if triage.needsHuman {
    routeToHuman(ticket)
} else if triage.requestsRefund, triage.severity >= .degraded {
    openRefundCase(ticket, team: triage.team)
} else {
    route(ticket, to: triage.team)
}

triage.$team.probabilities          // [.returns: 0.91, .shipping: 0.06, .billing: 0.03]
triage.$severity.score              // 1.3, the expected level
triage.$requestsRefund.probability  // 0.87
```

The struct is the question set. An `@Options` enum is a choice, an
`@Levels` enum is an ordered score, and a `Bool` is a yes or no question.
One struct is one request, so every question travels together. `triage.team`
is a `Team`; `triage.$team` is the `Choice<Team>` behind it, with the
probabilities, the model's confidence, and the value the model named.

## Adding the package

```swift
.package(url: "<this repository>", from: "0.1.0")
```

| Product | Import it for |
|---|---|
| `DecisionModels` | the types, the macros, the session, the composition wrappers, HTTP transport and retry |
| `DecisionModelsTypeSafe` | `Jev`, the hosted TypeSafe model |
| `DecisionModelsOpenRouter` | `OpenRouterAlpha`, OpenRouter's Decisions endpoint while it is in alpha |
| `DecisionModelsApple` | `GuidedGenerationModel`, the on-device model (iOS 26, macOS 26) |
| `DecisionModelsTesting` | scripted, recording, and replay models, and `Evaluation` |

The core and the hosted providers need iOS 18 or macOS 15. The Apple
adapter needs iOS 26 or macOS 26 and Apple Intelligence.

## Providers

**Jev**, TypeSafe's hosted model, returns calibrated probabilities and a
confidence for every answer. It reads `TYPESAFE_API_KEY` from the
environment when no key is passed. The caller names the version.
`jev-latest` floats: the model behind it can change at any time. A pinned
version stays fixed until the service retires it.

```swift
let session = DecisionSession(model: Jev(version: "jev-latest"))
let pinned = Jev(version: "jev-1.13.0", apiKey: key, retry: .default)
```

`RetryPolicy`, `HTTPTransport`, and `URLSessionTransport` are core types. A
file that names them imports `DecisionModels` next to `DecisionModelsTypeSafe`.

**OpenRouter** serves the same model through its Decisions endpoint, which
is in alpha. The type is `OpenRouterAlpha`, so every call site says so. It
reads `OPENROUTER_API_KEY` from the environment when no key is passed. The
caller names the model in OpenRouter's `vendor/model` form. There is no
default and no model list. When the endpoint leaves alpha, a plain
`OpenRouter` type will replace `OpenRouterAlpha`.

```swift
let session = DecisionSession(model: OpenRouterAlpha(model: "typesafe/jev-1.13"))
```

**The on-device model** answers a whole questionnaire in one guided
generation. One draw gives a point estimate. Several draws give an
empirical distribution, which is not calibrated but is a usable signal.

```swift
let session = DecisionSession(
    model: GuidedGenerationModel(.default),
    options: DecisionOptions(samples: 3)
)
```

**Test doubles** answer from a closure or from recorded traffic.

```swift
let session = DecisionSession(model: ScriptedModel { _ in
    TicketTriage(team: .billing, severity: .cosmetic, requestsRefund: false).answers
})
```

**Wrappers** are models too, so policy composes at the session line:

```swift
let jev = Jev(version: "jev-latest")
CascadeModel(first: GuidedGenerationModel(.default), then: jev, escalateBelow: 0.7)
ConsensusModel(jev, samples: 5)
CachedModel(jev, storage: InMemoryDecisionCache(capacity: 1_000))
RecordingModel(jev, into: recorder)
```

Every model reports its availability and its capabilities. The session
checks both before it sends, so a missing key, a device without Apple
Intelligence, or a question a model cannot take fails at once with a
`DecisionError` case, never with a provider's own error.

## Confidence and thresholds

Every answer keeps its distribution. `confidence` is one number in `0...1`
per answer: the provider's own number when it reports one, else a fixed
formula per kind (see DESIGN.md section 6.1). Thresholds are per question
and belong in your code:

```swift
switch triage.$team.band(escalateBelow: 0.5, confirmBelow: 0.9) {
case .act:      route(ticket, to: triage.team)
case .confirm:  confirmWithUser(triage.team)
case .escalate: routeToHuman(ticket)
}
```

An optional property makes the threshold part of the type. The value is
`nil` when the model is not sure enough:

```swift
@Ask("Which team handles this ticket?", minimumConfidence: 0.7)
var team: Team?
```

`Evaluation` in `DecisionModelsTesting` runs a labeled set through one or
more models and reports accuracy, Brier score, and calibration error per
question, which is how to pick thresholds on your own data.

## More shapes

- **Nested decisions.** `@Ask() var bug: BugReport` puts another decision's
  questions in the same request under a dotted prefix. Read them only when
  a gating answer says to.
- **Run-time questions.** When the answer space exists only at run time,
  build a `Questionnaire` from `Choose`, `Rate`, and `Verify` values and
  read typed answers back through `answers[question]`.
- **Set fan-out.** `@Ask("Does the request mention {option}?") var symbols: Set<Symbol>`
  asks one yes or no question per case and returns the members the model
  affirmed.
- **Commands.** `@Decision("Which command does the user want?") enum Command`
  with one `@Decision` struct per case asks for the command and every
  case's arguments in one request, and decodes only the chosen case.
- **Hierarchies.** `session.classify(tree, instructions:about:beamWidth:)`
  walks a tree of options with beam search, one request per depth.
- **Composite scores.** `CompositeScore { Weighted(0.4, "reach", reach); ... }`
  sums ratings with the weights visible and the weakest confidence exposed.

## Tests

See [TESTING.md](TESTING.md). The live suites against Jev, against
OpenRouter, and against the on-device model fail, rather than skip, when
their backend is missing.
