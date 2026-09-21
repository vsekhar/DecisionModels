# DecisionModels: a Swift framework for decision models

Status: approved design, revision 3, 2026-09-19. Revision 2 fixed the
findings of an independent verification pass, which also confirmed the `$`
projection mechanism on Swift 6.3.3 by building the macro. Revision 3
records the approved decisions (section 17) and platform minimums (section
15.1).

## 1. Goal

Give Swift code a native way to ask a decision model typed questions about
some state and to use the answers directly. The application declares a
Swift type. The framework turns that type into questions, sends them to a
model, and returns an instance of the type. The model behind the session can
change (hosted Jev, another hosted provider, an on-device model, a test
double) without any change to application code.

Non-goals: text generation, chat, streaming, tool calling. Those belong to
language model frameworks. This framework covers fast, structured judgments
only.

## 2. What we take from Foundation Models

Apple's framework is Swifty because the Swift type system does the work that
other SDKs do with dictionaries and schema files.

| Foundation Models | Why it works | DecisionModels equivalent |
|---|---|---|
| `@Generable` on a struct or enum makes the type the output schema | No separate schema object. The compiler checks the shape. | `@Decision` on a struct makes the type the question set |
| `@Guide(description:...)` on a property adds meaning and constraints | Metadata sits next to the property it describes | `@Ask("question")` on a property |
| Enum cases become the allowed strings | The type is the constraint | `@Options` and `@Levels` enums become the answer space |
| `session.respond(to:generating: T.self)` returns `Response<T>` | One async call, one typed value | `session.decide(T.self, about: state)` returns `T` |
| `LanguageModel` protocol; `SystemLanguageModel`, `PrivateCloudComputeLanguageModel`, third-party MLX and Core AI conformances | The session takes any model. App code does not change. | `DecisionModel` protocol; `Jev`, `GuidedGenerationModel`, test doubles |
| `LanguageModelCapabilities` plus `unsupportedCapability` errors | The framework refuses early instead of failing late | `DecisionModelCapabilities` |
| `Availability` enum with `UnavailableReason` | The app can show the right fallback UI | `DecisionModelAvailability` |
| Non-exhaustive typed error enums | Callers switch on cases, not strings | `DecisionError` |
| `Transcript` is `Codable` and rebuilds a session | Observability and replay come free | `DecisionRecord`, `RecordingModel`, `ReplayModel` |
| `@PromptBuilder` result builder | Conditionals and loops inside a prompt | `@StateBuilder` for assembling state |
| `DynamicGenerationSchema` for shapes known only at run time | Macros for the static case, values for the dynamic case | `Questionnaire` with typed `Choose`, `Rate`, `Verify` values |
| `@Observable` rewrites a property over hidden `_name` storage | The plain value stays plain; the machinery is one prefix away | `@Ask` rewrites a property over `$name` storage |
| `$`-style projections in SwiftUI (`@State` to `Binding`) | The plain value for the common case, the rich value one keystroke away | `triage.team` is a `Team`; `triage.$team` is a `Choice<Team>` |

## 3. Where decision models differ from language models

The differences shape the design. They are not details.

1. **The output is a distribution, not a value.** Jev returns probabilities
   over the options and a confidence number. The framework keeps both
   verbatim. A plain value is a convenience, never the only view.
2. **One request carries many questions.** Jev evaluates all questions in a
   request in parallel against one state. Batching 13 questions was measured
   as 12x cheaper and 10x faster than 13 calls. So one Swift type equals one
   request, and the design must make it easy to put many questions in one
   type, including speculative ones.
3. **There is no conversation.** Each request is stateless. A session holds
   configuration, shared context, and accounting, not history. Concurrent
   calls on one session are safe.
4. **There is no streaming and no tool calling.** A decision is one forward
   pass.
5. **The answer space is closed.** Jev allows up to 255 options per choice
   and 2 to 10 ordered levels per score, and answers yes/no with a
   probability. Everything else, such as arithmetic, counting, and text,
   stays in code. The framework should make the code side pleasant, not hide
   it.
6. **Confidence is the control signal.** The docs recommend three bands: act,
   confirm, escalate, with thresholds that scale with risk and are tuned per
   question on your own data. Swift can express this with `Optional` and
   `switch`.

## 4. The design in one example

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

    // Plain Swift. The decision logic lives with the questions.
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

print(triage.$team.probabilities)          // [.returns: 0.91, .shipping: 0.06, .billing: 0.03]
print(triage.$severity.score)              // 1.3 (expected value over levels)
print(triage.$requestsRefund.probability)  // 0.87
```

Swap the model and nothing above the session line changes:

```swift
let session = DecisionSession(model: GuidedGenerationModel(SystemLanguageModel.default))

let session = DecisionSession(model: ScriptedModel { _ in
    TicketTriage(team: .billing, severity: .cosmetic, requestsRefund: false).answers
})
```

## 5. Declaring decisions

### 5.1 `@Decision`

Attach to a struct, or to an enum (see **Enums** below). On a struct the
macro:

- adds conformance to `Decision` and `Sendable` in an empty extension. A
  member that is not `Sendable` fails there with the compiler's own
  message; a macro sees syntax, not conformances, so it cannot say more;
- synthesizes `static var questions: Questionnaire` from the `@Ask`
  properties, in declaration order;
- synthesizes `init(answers: Answers) throws`, which the session calls;
- synthesizes `var answers: Answers`, the inverse, so a decision can be
  recorded or served from a test double;
- synthesizes a plain-value initializer, `init(team:severity:requestsRefund:)`,
  that builds certain answers (probability 1.0 on the given value). This is for
  unit tests of downstream logic and for previews. No model is needed;
- emits an error for a struct with no `@Ask` property, for a stored property
  that has neither `@Ask` nor a default value, and for a class or actor.

The four members are written into the struct itself, not into the
extension, so a decision declared inside a namespace enum can still name
its sibling types. Generated members carry the struct's own access level.

```swift
public protocol Decision: Askable, Sendable where Projection == Self {
    static var questions: Questionnaire { get }
    init(answers: Answers) throws
    var answers: Answers { get }
}
```

`Decision` refines `Askable` (section 5.2) so that a decision can nest in
another decision. Swift cannot add a protocol conformance to a protocol in
an extension, so the refinement sits on the declaration; an extension on
`Decision` supplies the three `Askable` members.

The property name is the question id. A nested `@Decision` type flattens
with a dotted prefix, so `bug.severity` is one question inside a larger
request. `Questionnaire.prefixed(_:)` and `Answers.scoped(to:)` do the
renaming in both directions. This is how a caller does speculative fan-out:
put the dependent questions in the same type and read them only when the
gating answer says to.

```swift
@Decision
struct BugReport {
    @Ask("How severe is the issue?") var severity: Severity
    @Ask("Can the issue be reproduced from the description?") var reproducible: Bool
}

@Decision
struct Intake {
    @Ask("What kind of message is this?") var kind: MessageKind
    @Ask() var bug: BugReport        // answered in the same request; read only if kind == .bug
}
```

**Enums.** `@Decision` on an enum asks which case applies and, in the
same request, every case's arguments; only the chosen case's arguments
are decoded. This is the Jev function-calling recipe in the shape Apple
gives `@Generable` enums with associated values.

```swift
@Decision("Which command does the user want?")
enum Command {
    @Criterion("Plot a chart of one symbol")  case plot(PlotArguments)   // a @Decision struct
    @Criterion("Set a price alert")           case alert(AlertArguments)
    @Criterion("Do nothing")                  case cancel
}

let command: Command = try await session.decide(about: request)
let answered = try await session.respond(Command.self, about: request).decision
answered.$kind.confidence
```

A case has no payload or exactly one unlabeled payload whose type is a
`Decision`. The macro generates a nested `Kind`, an options enum over the
case names with the `@Criterion` texts, and a nested `Answered: Decision`
that holds `$kind: Choice<Kind>` and the built `command`. The enum itself
conforms to `Askable` with `Projection == Answered`, so it nests in other
decisions like any leaf and `session.decide` returns the plain enum value
through two overloads that accept any `Askable` whose projection is a
`Decision`. Question ids are `kind` and `<case>.<argument>`. An enum can
hold no stored projection, so the `Answered` struct is where the
probabilities live; `respond` returns it. A raw-value enum, a labeled or
multiple payload, an enum with no cases, and `@Decision` on an enum
without its question text are errors; so is question text on a struct.

### 5.2 `@Ask`

One marker. The declared type selects the question kind, in the same way
that `@Guide` on an `Int` or an enum yields a different schema.

| Declared type | Question kind | Projection `$name` |
|---|---|---|
| `T` where `T: ChoiceOption & CaseIterable` | choice among the cases | `Choice<T>` |
| `T` where `T: RatingLevel` | score over ordered levels | `Rating<T>` |
| `Bool` | yes/no | `Verdict` |
| `T?` for any of the above | same kind, gated on confidence | same as above |
| `Set<T>` where `T: ChoiceOption & CaseIterable` | one yes/no per case (fan-out) | `FanOut<T>` |
| `D` where `D: Decision` | nested question set | none; use `name.$field` |
| `E` where `E` is a `@Decision` enum | a choice over the cases plus every case's arguments | `E.Answered` |

Forms:

```swift
@Ask("Which team handles this ticket?")
var team: Team

@Ask("Which team handles this ticket?", minimumConfidence: 0.7)
var team: Team?              // nil when $team.confidence < 0.7

@Ask("Does the customer ask for a refund?",
     ifTrue: "The customer wants money back or a chargeback",
     ifFalse: "The customer wants a fix, a replacement, or information")
var requestsRefund: Bool

@Ask(instructions: ["question": "Is the amount in `invoice.total` consistent with `invoice.lines`?",
                    "focus": "arithmetic consistency only"])
var totalsMatch: Bool        // structured instructions, as Jev accepts

@Ask()
var bug: BugReport           // nested decision; no question text of its own

@Ask("Does the request mention {option}?", minimumProbability: 0.7)
var symbols: Set<Symbol>     // one yes/no per case; {option} names each case's criterion
```

An `Optional` property must give `minimumConfidence`. A threshold is a
decision. It must be visible. Because confidence is kind-specific (section
6), the threshold is per question by construction.

**How the kind is selected.** A macro sees syntax, not conformances. It
cannot tell an `@Options` enum from an `@Levels` enum by looking at
`var severity: Severity`. So `@Ask` expands to the same code for every
property and lets the type system resolve the kind through a protocol:

```swift
public protocol Askable {
    associatedtype Projection: Sendable
    static func questions(id: String, _ inquiry: Inquiry) -> [QuestionSpec]
    static func projection(in answers: Answers, id: String) throws -> Projection
    static func read(_ projection: Projection) -> Self
    static func answers(from projection: Projection, id: String) -> Answers
}
```

`answers(from:id:)` is what lets the macro write one line per property
without knowing whether the property is a leaf or a nested decision: a leaf
returns its one record under `id`; a nested decision returns its own
answers with `id` as the prefix. `Answers(merging:)` joins the parts and
takes the lowest quality. Each kind also has a static `certain(_:)` that
turns a plain value into a sure projection, and `Optional` adds
`certain(_:)` overloads that store the kind's `uncertain` value for `nil`;
the plain-value initializer calls these.

```swift

public struct Inquiry: Sendable {        // what @Ask's arguments become
    public var instructions: State       // string or structured
    public var ifTrue: Criterion?
    public var ifFalse: Criterion?
    public init(_ instructions: State = .null, ifTrue: Criterion? = nil, ifFalse: Criterion? = nil)
}
```

| Type | `Projection` | Provided by |
|---|---|---|
| an `@Options` enum | `Choice<Self>` | the `@Options` macro emits the `typealias` on the concrete type |
| an `@Levels` enum | `Rating<Self>` | the `@Levels` macro emits the `typealias` on the concrete type |
| `Bool` | `Verdict` | the framework |
| `Optional<W>` where `W: Askable` | `W.Projection`; adds `read(_:minimumConfidence:)` | the framework |
| `Set<T>` where `T: ChoiceOption & CaseIterable` | `FanOut<T>`, one `Verdict` per case under `id.optionID`; adds `read(_:minimumProbability:)`; the plain `Set` holds the cases at or above 0.5 | the framework |
| a `@Decision` enum | its nested `Answered` struct, a `Decision` that holds the `Choice` over the cases and the chosen case's arguments | the `@Decision` macro |
| a `Decision` | `Self`; `questions` returns `Self.questions.prefixed(id)`, `projection` returns `try Self(answers: answers.scoped(to: id))`, `answers` returns `value.answers.prefixed(id)` | the framework: `Decision` refines `Askable`, and an extension on `Decision` supplies the members |

The `typealias` must sit on the concrete enum. A default in a protocol
extension cannot be overridden by a refining protocol; the verification pass
confirmed the compiler rejects that form. A `minimumConfidence` argument on a
non-optional property fails to type-check because only `Optional` has the
two-argument `read`, which is the diagnostic we want.

`@Ask` is an accessor macro plus a peer macro. It rewrites the property into
a computed getter over a stored `$name` peer, in the same way `@Observable`
rewrites tracked properties over `_name` storage. Section 12 shows the
expansion.

### 5.3 `@Options`, `@Levels`, `@Criterion`

The answer space is a type, so one enum serves many questions and the
compiler checks every `switch`.

```swift
@Options
enum Team { ... }
// adds: ChoiceOption, CaseIterable, Hashable, Sendable, Codable, Askable
// optionID = case name; criterion from @Criterion or a humanized case name

@Levels
enum Severity { ... }
// adds: RatingLevel (which implies ChoiceOption, CaseIterable), Comparable by case order, Askable, Codable
// the macro emits an error when there are fewer than 2 cases;
// the upper limit is a provider capability, checked per request

// Both macros write optionID as a switch that returns the case name, so a
// CustomStringConvertible conformance cannot change wire ids.
```

`@Criterion` carries the structured forms Jev accepts. Jev's structured
criteria are free-form JSON objects; the `what`, `not_for`, `examples`,
`summary`, and `signals` keys in its docs are conventions. So one flat
struct serves choice and score alike, and nothing is dropped on the wire.

```swift
@Criterion("Exchanges and refunds",
           notFor: "Payment disputes",
           examples: ["wrong size", "arrived damaged"])
case returns

@Criterion("Broken or degraded feature, but a workaround exists",
           signals: ["reports an error", "mentions a manual step that works"])
case degraded
```

```swift
public struct Criterion: Sendable, Hashable, Codable, ExpressibleByStringLiteral {
    public var summary: String
    public var notFor: String?
    public var examples: [String]
    public var signals: [String]
    public init(_ summary: String, notFor: String? = nil, examples: [String] = [], signals: [String] = [])
}

public protocol ChoiceOption: Hashable, Sendable {
    var optionID: String { get }
    var criterion: Criterion { get }
}

public protocol RatingLevel: ChoiceOption, CaseIterable, Comparable {}
```

A provider that accepts structured criteria sends them as JSON. A provider
that does not gets a rendered string. The application does not know which.

Types that are not enums can conform to `ChoiceOption` by hand. A `Product`
with an `id` and a summary is a valid option for a run-time question (section
9). No reverse mapping is required of them: the static path maps ids back
through `CaseIterable`, and the dynamic path maps them back through the
option list the question was built with.

## 6. Reading answers

Every answer keeps the full distribution and the model's own reported
values. The plain value is what the model named. Nothing is rounded away.

```swift
public enum ProbabilityQuality: Sendable, Codable, Hashable, Comparable {
    case pointEstimate            // one-hot from an argmax-only model
    case sampled(count: Int)      // empirical, from repeated draws
    case calibrated               // trained and reported by the provider
}

public struct Distribution<Value: Hashable & Sendable>: Sendable {
    public let probabilities: [Value: Double]   // sums to 1
    public let quality: ProbabilityQuality
    public var mostLikely: Value                // argmax
    public var ranked: [(Value, Double)]        // descending
    public var entropy: Double                  // nats
}
extension Distribution: Hashable {}
extension Distribution: Codable where Value: Codable {}

public enum ConfidenceBand: Sendable { case act, confirm, escalate }

public protocol Answer: Sendable {
    associatedtype Value
    var value: Value { get }
    var confidence: Double { get }
    var quality: ProbabilityQuality { get }
    var record: AnswerRecord { get }     // the wire-level form (section 9)
}
extension Answer {
    public func band(escalateBelow low: Double, confirmBelow high: Double) -> ConfidenceBand
}

public struct Choice<Option: ChoiceOption>: Answer {
    public let distribution: Distribution<Option>
    public let reported: Option?                        // the option the model named
    public let reportedConfidence: Double?              // the provider's number, verbatim
    public var value: Option                            // reported ?? distribution.mostLikely
    public var probabilities: [Option: Double]          // forwards to distribution
    public var confidence: Double                       // reportedConfidence ?? 1 - entropy / ln(count)
    public var quality: ProbabilityQuality
    public subscript(option: Option) -> Double          // probability of one option
    public func value(ifAtLeast confidence: Double) -> Option?
    public init(certain: Option)
    public static var uncertain: Choice where Option: CaseIterable   // uniform, confidence 0
}
extension Choice: Codable where Option: Codable {}

public struct Rating<Level: RatingLevel>: Answer {
    public let distribution: Distribution<Level>
    public let score: Double                            // reported expected value, 0...(count - 1)
    public let reportedConfidence: Double?
    public var value: Level                             // distribution.mostLikely
    public var normalized: Double                       // score / (count - 1), 0...1
    public var probabilities: [Level: Double]
    public var confidence: Double                       // reportedConfidence ?? 1 - stddev / ((count - 1) / 2)
    public var quality: ProbabilityQuality
    public var legend: [Level: Criterion]
    public func value(ifAtLeast confidence: Double) -> Level?
    public init(certain: Level)
    public static var uncertain: Rating                 // uniform, confidence 0
}
extension Rating: Codable where Level: Codable {}

public struct Verdict: Answer, Codable, Hashable {
    public let probability: Double                      // P(yes)
    public var value: Bool                              // probability >= 0.5
    public var confidence: Double                       // abs(2 * probability - 1)
    public let quality: ProbabilityQuality
    public func isTrue(atLeast probability: Double) -> Bool
    public init(certain: Bool)
    public static var uncertain: Verdict                // probability 0.5
}
```

### 6.1 Confidence, stated precisely

Confidence is one number in 0...1 per answer. Every threshold in this
document (`minimumConfidence`, `value(ifAtLeast:)`, `band`, `escalateBelow`)
compares against this number and no other.

1. If the provider reports a confidence, that value is used verbatim and is
   also kept in `reportedConfidence`. Jev reports one for choice and score.
2. Otherwise the framework computes it with a formula fixed per kind:
   - Choice (nominal): `1 - H(p) / ln(n)`, the complement of normalized
     entropy.
   - Rating (ordinal): `1 - σ(p) / ((n - 1) / 2)`, the complement of
     normalized standard deviation over level indices. This reproduces the
     value in Jev's published score example (levels 0/1/2 with
     probabilities 0/0.7/0.3 give 0.54), so on-device fallbacks and Jev agree
     on scale for ratings.
   - Verdict (binary): `abs(2p - 1)`. Jev reports no confidence for yes/no
     because the probability is the signal; this formula exists so that
     `Bool?` gating and bands work the same way for all three kinds.

The formulas need `n`, the size of the answer space. A typed answer knows
it from its options or levels. A wire record does not carry it, so
`AnswerRecord.confidence` on a bare record guesses `n` from the keys it
holds, and a provider that leaves out an option or level it gave zero
weight makes that guess low. The session fills it in: it resolves every
record against its question before it returns (section 8), so every option
and level is present, absent ones at zero, and the record's number equals
the typed answer's. Only a record from elsewhere, such as one built by
hand, is an estimate.

Confidence means different things for different kinds and for different
question counts, which is also true of the provider's own numbers. That is
why thresholds are per question, why `Optional` properties must state
theirs, and why section 13 ships a calibration report.

### 6.2 Notes

- `Rating.value` is the most likely level, for symmetry with `Choice`.
  `Rating.score` is the expected value the model reported. The two can
  differ when the distribution is bimodal. Composite scoring uses
  `normalized`.
- `quality` tells the code whether it holds calibrated probabilities (Jev),
  an empirical distribution from repeated samples, or a one-hot point
  estimate from a model that only returns an argmax. `ProbabilityQuality`
  is ordered (`pointEstimate < sampled < calibrated`), so a session option can
  demand a floor.
- `uncertain` values exist so the plain-value initializer can build the
  below-threshold branch: `TicketTriage(team: nil, ...)` on an optional
  `team` stores `Choice.uncertain`, which gates to `nil`. A uniform
  distribution gives a choice or a verdict confidence 0 by formula, but not
  a rating (the ordinal formula gives about 0.18 for three levels), so
  `Rating.uncertain` carries a `reportedConfidence` of 0.
- The value types have public memberwise initializers so providers and
  tests can build them. `Distribution` requires at least one entry.
- The reader that turns records into typed answers throws `DecisionError`
  on anything a provider must never send: probabilities that are empty,
  negative, not finite, or sum to zero; a reported confidence or verdict
  probability outside `0...1`; a rating score off the scale; option ids
  the question does not know; two options that share an id. Probabilities
  that do not sum to one are scaled. Ties in a choice's `mostLikely` resolve by the option's description
  text, so the order is stable. Ties in a rating's `value` go to the lower
  level, because the scale is ordered. The same probability, id, index,
  score, and confidence checks run on the wire level when the session
  resolves a response against its questionnaire (section 8), so the two
  paths cannot drift apart. That step adds the absent options and levels
  at zero and does not rescale.

The three-band pattern from the Jev docs, at the call site:

```swift
switch triage.$team.band(escalateBelow: 0.5, confirmBelow: 0.9) {
case .act:      route(ticket, to: triage.team)
case .confirm:  confirmWithUser(triage.team)
case .escalate: routeToHuman(ticket)
}
```

## 7. State

State is the material the model judges. Jev accepts a string, a JSON object,
or an array. The framework models it as a JSON-like value and lets Swift
types render themselves into it, in the same way `PromptRepresentable` lets
types render into a prompt.

```swift
public enum State: Sendable, Hashable, Codable,
                   ExpressibleByStringInterpolation, ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral {
    case text(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([State])
    case object([String: State])

    public init(encoding value: some Encodable) throws   // via JSONEncoder
}

public protocol StateRepresentable: Sendable {
    var stateRepresentation: State { get }
}
// String, Bool, Int, Double and State conform. Array and Dictionary<String, _>
// conform when their element type conforms. The existential
// [any StateRepresentable] cannot conform (a Swift limit); mixed values use
// State literals, and the session renders its context element-wise.

@resultBuilder public enum StateBuilder { ... }   // builds State.object; supports if, if let, for

public struct Field {
    public init(_ name: String, _ value: some StateRepresentable)
    public init(_ name: String, encoding value: some Encodable) throws
}
```

A result builder assembles named fields with conditionals:

```swift
let triage = try await session.decide(TicketTriage.self) {
    Field("message", ticket.body)
    try Field("customer", encoding: customer)
    if let order { try Field("order", encoding: order) }
    Field("policy", refundPolicy)
}
```

Question text can name fields with backtick dot paths, such as
`` `order.items[0]` ``, following the Jev convention. Providers that render
state as text keep the same field names, so the references stay valid.

A session can hold standing context, the decision-model analogue of Apple's
`instructions`. It merges into every request's state object:

```swift
let session = DecisionSession(model: Jev(version: "jev-latest"), context: ["policy": refundPolicy])
```

## 8. Sessions

```swift
public final class DecisionSession: Sendable {
    public init(model: some DecisionModel,
                context: [String: any StateRepresentable] = [:],
                options: DecisionOptions = .init())

    // The common path. Returns the decision itself.
    public func decide<D: Decision>(_ type: D.Type = D.self,
                                    about state: some StateRepresentable,
                                    options: DecisionOptions? = nil) async throws -> D

    public func decide<D: Decision>(_ type: D.Type = D.self,
                                    options: DecisionOptions? = nil,
                                    @StateBuilder about state: () throws -> State) async throws -> D

    // The detailed path. Same call, plus metadata.
    public func respond<D: Decision>(_ type: D.Type = D.self,
                                     about state: some StateRepresentable,
                                     options: DecisionOptions? = nil) async throws -> DecisionResponse<D>

    // Any Askable whose projection is a Decision, such as a @Decision enum:
    // the same two calls, returning the plain value or its projection.
    public func decide<A: Askable>(_ type: A.Type = A.self, about state: some StateRepresentable,
                                   options: DecisionOptions? = nil) async throws -> A where A.Projection: Decision
    public func respond<A: Askable>(_ type: A.Type = A.self, about state: some StateRepresentable,
                                    options: DecisionOptions? = nil) async throws -> DecisionResponse<A.Projection> where A.Projection: Decision

    // Run-time questions (section 9).
    public func decide(_ questionnaire: Questionnaire,
                       about state: some StateRepresentable,
                       options: DecisionOptions? = nil) async throws -> Answers

    public var model: any DecisionModel { get }
    public var options: DecisionOptions { get }   // the defaults every call starts from
    public var usage: Usage { get }               // cumulative; Mutex-backed
    public func prewarm() async                   // forwards to the model
}

public struct DecisionResponse<D: Decision>: Sendable {
    public let decision: D
    public let answers: Answers          // wire-level, by id
    public let usage: Usage
    public let model: DecisionModelIdentity
    public let requestID: String?
    public let duration: Duration
}

public struct Usage: Sendable, Codable, Hashable, AdditiveArithmetic {
    public var inputTokens: Int
    public var outputTokens: Int
    public var requests: Int
}

public struct DecisionOptions: Sendable {
    public var timeout: Duration? = nil
    public var samples: Int = 1                                 // > 1 asks for repeated draws where supported; < 1 is a precondition failure
    public var minimumProbabilityQuality: ProbabilityQuality? = nil   // throw if the response is below this
    public var metadata: [String: String] = [:]                 // travels on the request into records and logs
}
```

A per-call `options` value replaces the session's options entirely, as
`GenerationOptions` does in Foundation Models. `session.options` exposes the
defaults so a call site can copy them and change one field; a fresh value
carries no session-level floor, and that is visible at the call site.

The session is a plain `Sendable` class. Its only mutable state is the
usage counter behind a `Mutex`, so concurrent `decide` calls are safe and
strict concurrency holds. It is not `@Observable`; a view model that wants
to observe usage reads it after each call.

Before it sends, the session checks `model.availability`, then checks the
questionnaire for sanity (`invalidQuestion`: an empty questionnaire,
duplicate question ids, a choice with no options or duplicate option ids, a
rating with fewer than two levels, a question with no instructions) and then
against `model.capabilities`
(option counts, level counts, structured criteria and instructions, question
count, repeated samples). Failures throw before any network call. After the
response it adds the usage, then checks `minimumProbabilityQuality`; tokens
spent on a rejected response still count. Then it resolves every record
against the question that asked for it: an option or level the provider left
out comes in at zero, and an unknown option id, a level index off the scale,
a negative probability, a verdict probability or reported confidence outside
`0...1`, a kind that does not match the question, or a record with no
question throws `malformedResponse`. A question with no record stays absent:
a `@Decision` enum decodes only the chosen case's arguments (section 5.1),
so a response may leave the others out, and a read that needs the missing
answer throws `invalidQuestion` as before. Every record the session returns
is complete, whether it comes back from the run-time call or inside a
`DecisionResponse`.

Type inference makes `.self` optional at the call site:

```swift
let triage: TicketTriage = try await session.decide(about: state)
let triage = try await session.decide(TicketTriage.self, about: state)
```

For SwiftUI, an `EnvironmentValues.decisionSession` key lets the app inject one
session at the root and swap the model in one place.

## 9. Run-time questions and the wire level

Some answer spaces exist only at run time: a product catalog, a skill list,
450 candidate pairs. The static macros cannot help. The dynamic path uses
question values whose generic parameter types the answer, which is what the
TypeScript SDK does with `ResultFor` and what Apple does with
`DynamicGenerationSchema`.

Underneath both paths sit concrete, `Codable` wire types. Typed question
values and typed answers are views over them. This is what makes recording,
replay, and provider-neutral wrappers possible.

```swift
// Wire level. Everything here is Codable and Hashable.

public struct QuestionSpec: Sendable, Codable, Hashable {
    public var id: String
    public var instructions: State
    public var kind: Kind
    public enum Kind: Sendable, Codable, Hashable {
        case choice(options: [OptionSpec])
        case rating(levels: [Criterion])
        case verdict(ifTrue: Criterion?, ifFalse: Criterion?)
    }
    public struct OptionSpec: Sendable, Codable, Hashable {
        public var id: String
        public var criterion: Criterion
    }
}

public struct Questionnaire: Sendable, Codable, Hashable {
    public var specs: [QuestionSpec]
    public init(_ specs: [QuestionSpec])
    public init(@QuestionnaireBuilder _ questions: () -> [any Question])
    public mutating func add(_ question: some Question)
    public func prefixed(_ prefix: String) -> Questionnaire       // "severity" -> "bug.severity"
}

public enum AnswerRecord: Sendable, Codable, Hashable {
    case choice(reported: String, probabilities: [String: Double], confidence: Double?)
    case rating(score: Double, probabilities: [Int: Double], confidence: Double?)
    case verdict(probability: Double)
    public var confidence: Double         // reported, or the section 6.1 formula; exact once the session has resolved the record
}

public struct Answers: Sendable, Codable, Hashable {
    public var records: [String: AnswerRecord]
    public var quality: ProbabilityQuality
    public subscript<Q: Question>(_ question: Q) -> Q.Answer { get throws }
    public func choice<O: ChoiceOption & CaseIterable>(_ id: String, as: O.Type) throws -> Choice<O>
    public func rating<L: RatingLevel>(_ id: String, as: L.Type) throws -> Rating<L>
    public func verdict(_ id: String) throws -> Verdict
    public func scoped(to prefix: String) -> Answers              // "bug.severity" -> "severity"
    public func prefixed(_ prefix: String) -> Answers             // the inverse, for nested `answers`
}

// Typed question values.

public protocol Question: Sendable {
    associatedtype Answer: DecisionModels.Answer
    var spec: QuestionSpec { get }
    func answer(from record: AnswerRecord, quality: ProbabilityQuality) throws -> Answer
    // answer(from:) is a default that assumes .pointEstimate
}

public struct Choose<Option: ChoiceOption>: Question {   // Answer == Choice<Option>
    public init(_ id: String, _ instructions: State, among options: [Option])
    public init(_ id: String, _ instructions: State) where Option: CaseIterable
}

public struct Rate<Level: RatingLevel>: Question {       // Answer == Rating<Level>
    public init(_ id: String, _ instructions: State, levels: Level.Type = Level.self)
}

public struct Verify: Question {                         // Answer == Verdict
    public init(_ id: String, _ instructions: State, ifTrue: Criterion? = nil, ifFalse: Criterion? = nil)
}

@resultBuilder public enum QuestionnaireBuilder { ... }  // collects [any Question]; supports if, for
```

`Choose` keeps its option list, so `answers[skill]` maps option ids back to
`Skill` values without any requirement on `Skill` beyond `ChoiceOption`.
`instructions` is a `State`, so a string literal works and so does a
structured object.

Use:

```swift
let skill = Choose("skill", "Which skill best fits the request?", among: catalog)   // catalog: [Skill]
let effort = Rate<Effort>("effort", "How much work is the request?")
let unsafe = Verify("unsafe", "Does the request ask for something the policy forbids?")

let answers = try await session.decide(Questionnaire { skill; effort; unsafe }, about: request)

let chosen: Skill = try answers[skill].value
if try answers[unsafe].isTrue(atLeast: 0.3) { refuse() }
```

The macros generate exactly this. `@Decision` is sugar over `Questionnaire`
and `Answers`, so the two paths cannot drift apart.

## 10. Models

One protocol, one method. Apple splits `LanguageModel` from
`LanguageModelExecutor` to support streaming channels and key-value caches.
Decision models need neither, so the split would add weight without value.

```swift
public protocol DecisionModel: Sendable {
    var identity: DecisionModelIdentity { get }          // name, version
    var capabilities: DecisionModelCapabilities { get }
    var availability: DecisionModelAvailability { get async }
    func decide(_ request: DecisionRequest) async throws -> ModelResponse
    func prewarm() async                                 // default: no-op
}

public struct DecisionRequest: Sendable, Codable, Hashable {
    public let state: State
    public let questionnaire: Questionnaire
    public let samples: Int
    public let timeout: Duration?
    public let metadata: [String: String]   // tags for records; caches and replays key on the other fields
}

public struct ModelResponse: Sendable, Codable {
    public let answers: Answers
    public let usage: Usage
    public let requestID: String?
}

public struct DecisionModelIdentity: Sendable, Codable, Hashable {
    public var provider: String      // "typesafe", "apple", "test"
    public var name: String          // "jev-1.13.0", "system-language-model"
}

public struct DecisionModelCapabilities: Sendable {
    public var probabilityQuality: ProbabilityQuality    // the best the model can deliver
    public var structuredCriteria: Bool
    public var structuredInstructions: Bool
    public var maximumOptionsPerChoice: Int
    public var maximumLevelsPerRating: Int
    public var maximumQuestionsPerRequest: Int?
    public var contextTokens: Int?
    public var supportsRepeatedSamples: Bool
    // The memberwise initializer defaults to .pointEstimate, no structured
    // input, Jev's limits of 255 options and 10 levels, no question limit,
    // no context size, and no repeated samples.
}

public enum DecisionModelAvailability: Sendable {
    case available
    case unavailable(Reason)

    public enum Reason: Sendable {
        case notConfigured(String)     // missing API key, missing entitlement
        case offline
        case deviceNotEligible
        case modelNotReady             // downloading, warming
        case other(String)
    }
}
```

### 10.1 Providers

**`Jev`** (module `DecisionModelsTypeSafe`). Maps a request one-to-one onto
`POST /v1/systemone`: choice, score, and noul; instructions and criteria as
strings or JSON (a criterion with only a summary goes as a string; a
richer one as an object with `what` or `summary`, `not_for`, `examples`,
`signals`); `jev-latest`, `jev-preview`, or a pinned version. Reads
`TYPESAFE_API_KEY` when no key is passed; a missing or blank key makes the
model unavailable with `.notConfigured`. Reports `.calibrated`, 255
options, 10 levels, 64k context, no repeated samples. Keeps the returned
`choice`, `score`, and `confidence` fields verbatim in the answer records.

```swift
Jev(version: "jev-latest")
Jev(version: "jev-preview")
Jev(version: "jev-1.13.0", apiKey: key, retry: .default, transport: URLSessionTransport())
```

The framework ships no default model or version. The caller names one and
so accepts its contract. A floating alias such as `jev-latest` can change
underneath the caller at any time. A pinned version can stop being
available when the service retires it. `models()` returns a `ModelCard`
for each version the account can call.

Transport and waiting: `HTTPTransport`, `URLSessionTransport`,
`RetryPolicy`, and the retry loop live in the core `DecisionModels` module,
and every HTTP provider uses them. `HTTPTransport` is a one-method protocol
over `URLRequest`, with `URLSessionTransport` as the default, so tests
script responses without a network. `RetryPolicy` (`maxRetries`,
`initialBackoff`, `maximumBackoff`, `multiplier`, `attemptTimeout`;
`.default`, `.none`) says how often to send again, how long to wait, and
how long one try may take. `HTTPClient`, visible inside the package only,
runs the loop. It retries the statuses the provider names (429 and 529 for
Jev) and transport failures with capped doubling backoff; it honors a
`Retry-After` header but never waits past `maximumBackoff`.
`DecisionRequest.timeout` is a deadline
for the whole call, attempts and waits included, not for one attempt.
`attemptTimeout` (ten seconds by default; `nil` for none) bounds each
attempt on its own: an attempt gets that or the time left before the
deadline, whichever is less, so one hung connection costs one attempt and
a backoff, not the whole deadline. The client retries a timed-out attempt
like any transport failure; when the retries run out, or the deadline
passes, the call ends in `.timeout`. Cancellation is never retried and
surfaces as `CancellationError`, not as a `DecisionError`. The client hands
the provider the final reply, and the provider maps its status to
`DecisionError`. For Jev: 401 `.unauthorized`, 422 `.invalidQuestion` with
the server's message, 429 `.rateLimited(retryAfter:)` and 529
`.overloaded` after retries; anything else travels as
`.transport(JevServerError)`.

**`OpenRouterAlpha`** (module `DecisionModelsOpenRouter`). Maps a request
one-to-one onto OpenRouter's `POST /api/alpha/decisions`. Its request and
answer shapes match `POST /v1/systemone` field for field: the same
question kinds, the same criteria rendering, the same answer records. The
differences are the host, the path, the `vendor/model` name, a request id
and a provider name in the body, a `cost` in usage, and a wider set of
statuses. Reads `OPENROUTER_API_KEY` when no key is passed. The caller
names the model; there is no default and no model list, because
OpenRouter documents none. Declares Jev's capabilities and `.calibrated`,
an assumption tied to `typesafe/jev-1.13`, the one decision model the
alpha serves. Sends `model`, `state`, and `questions` only, and never
`provider`, `session_id`, `user`, or `trace`. Drops `cost`. Requires
`probabilities` in every choice and score answer, although the docs mark
them optional, because a calibrated answer needs a distribution; a reply
without one is malformed. Retries 429, 502, 503, 524, and 529 through the
shared client. Status codes map to `DecisionError`: 400 `.invalidQuestion`
with OpenRouter's message; 401 and 403 `.unauthorized`; 402
`.unavailable(.other)`; 413 `.contextSizeExceeded`; 429
`.rateLimited(retryAfter:)`; 503 `.overloaded`; 524 `.timeout`; anything
else, 404, 500, 502, and 529 included, `.transport(OpenRouterServerError)`
with the status, the message, and `error.code`. The type name carries
"alpha", so no call site builds one without saying so. A plain
`OpenRouter` type replaces it when the endpoint leaves alpha.

```swift
OpenRouterAlpha(model: "typesafe/jev-1.13")
OpenRouterAlpha(model: "typesafe/jev-1.13", apiKey: key, retry: .default)
```

**`GuidedGenerationModel`** (module `DecisionModelsApple`). On iOS 26 and
macOS 26 it wraps `SystemLanguageModel`. On iOS 27 and macOS 27 it will
also accept any Apple `LanguageModel`, which brings in
`PrivateCloudComputeLanguageModel` and third-party MLX and Core AI models;
that initializer waits for an Xcode 27 SDK (section 15.1).

```swift
@available(iOS 26, macOS 26, *)
public init(_ model: SystemLanguageModel, instructions: String? = nil)

@available(iOS 27, macOS 27, *)   // not yet built; see 15.1
public init(_ model: some LanguageModel)
```

`instructions` are standing rules the adapter appends to its own task
instructions in every session. Its identity is `apple` /
`system-language-model`. The caller passes the model. `.default` is
Apple's shared on-device model, and the model behind it changes with the
OS.

Per request it builds one `DynamicGenerationSchema` object with a property
per question: a string constrained with `anyOf` over option ids for choice,
an integer with `range(0...n-1)` for rating, a `Bool` for yes/no. Dotted
question ids map to safe property names and back. State, instructions, and
criteria go into the prompt as text and JSON, so the adapter declares
`structuredCriteria` and `structuredInstructions` true: it renders what
Jev takes natively, and the caller never knows the difference. One
`respond(schema:)` call answers the whole batch, so batching survives the
change of provider. Before it sends, it estimates tokens with
`tokenCount(for:)` and throws `contextSizeExceeded` when the instructions,
prompt, and schema would not leave room for the answer (256 tokens or 8
per question, whichever is larger). `Usage.inputTokens` is that estimate
times the number of draws; the SDK reports no output tokens.

It declares `probabilityQuality = .sampled(count: .max)` as its ceiling.
With `samples == 1` a response carries `.pointEstimate` and one-hot
probabilities over every option and level. With `samples = k` it runs k
greedy-free generations in sequence, one fresh session each, and returns
an empirical distribution marked `.sampled(count: k)`. This costs k passes
and is not calibrated, but it gives on-device code a usable uncertainty
signal. Draws take no seed: the device rejects most of the declared seed
range. `DecisionRequest.timeout` is a deadline for the whole call across
all draws.

Errors map as: guardrail hit `.guardrailViolation`; refusal `.refused`;
context overflow `.contextSizeExceeded`; rate limit `.rateLimited`; a
schema the device will not take `.invalidQuestion`; assets not on the
device `.unavailable(.modelNotReady)`; a busy device `.overloaded`; an
unusable answer or language `.malformedResponse`; anything else
`.transport`. Availability maps one-to-one from
`SystemLanguageModel.Availability`; Apple Intelligence turned off is
`.notConfigured("Apple Intelligence")`.

**Custom models.** Conform to `DecisionModel` directly. A Core ML classifier
trained for fixed questions, an in-house server, or another vendor's API each
fit the one-method protocol.

### 10.2 Composition

Wrappers are also models, so policy composes without touching call sites.
They work on `AnswerRecord` values, which expose confidence and
probabilities without knowing the application's Swift types.

```swift
CascadeModel(first: onDevice, then: jev, escalateBelow: 0.7)   // resolves each answer, re-asks only the ids below the bar; merges only those
ConsensusModel(jev, samples: 5)                  // repeats, averages normalized distributions, marks .sampled, lists disagreements
CachedModel(jev, storage: cache)                 // keyed on state, questionnaire, samples, and model identity
RecordingModel(jev, into: recorder)              // writes DecisionRecord values
ReplayModel(records: fixtures)                   // serves recorded answers; throws on miss
ScriptedModel { request in Answers }             // closure-based test double; zero usage
```

Details that matter when wrappers nest. `CascadeModel` and
`ConsensusModel` each have a `decideWithReport(_:)` that returns a
`CascadeReport` (the escalated ids) or a `ConsensusReport` (the ids whose
answer changed across runs) beside the response. A cascade resolves each
answer the questionnaire asked for against its question (section 8): a
first answer before it meets the bar, so the bar sees an exact confidence,
and a second answer on merge, so the merged response is complete. A
malformed first answer throws before the cascade asks the second model. A
cascade's identity names both providers and the threshold, so two cascades
that differ only
in the bar do not share a cache entry; a consensus identity carries its
sample count. `ConsensusModel` runs the inner model once per draw with
`samples: 1`, uses a per-call `samples` above one in place of its default,
normalizes each run before averaging, drops reported confidence so the
section 6.1 formula applies, and keeps `.calibrated` only when every
calibrated run agreed; with one draw it reports the inner quality
unchanged. Put a cache outside a consensus, never inside: a cache inside
serves every draw the same answer. `CacheKey` ignores metadata and timeout.
`DecisionCache` is a protocol with an in-memory actor implementation that
evicts oldest first when given a capacity.

## 11. Errors

```swift
public enum DecisionError: Error, Sendable {   // non-frozen
    case unavailable(DecisionModelAvailability.Reason)
    case unsupported(Unsupported)
    case invalidQuestion(id: String, reason: String)
    case contextSizeExceeded(limit: Int?, estimated: Int?)
    case rateLimited(retryAfter: Duration?)
    case overloaded
    case unauthorized
    case timeout
    case refused                                 // the model declined to answer
    case guardrailViolation                      // input or output tripped a safety filter
    case insufficientProbabilityQuality(got: ProbabilityQuality, required: ProbabilityQuality)
    case malformedResponse(String)
    case transport(any Error)

    public enum Unsupported: Sendable {
        case structuredCriteria
        case structuredInstructions
        case tooManyOptions(id: String, count: Int, limit: Int)
        case tooManyLevels(id: String, count: Int, limit: Int)
        case tooManyQuestions(count: Int, limit: Int)
        case repeatedSamples
    }
}
```

Providers translate their own failures into these cases. Application code
switches on cases and never sees HTTP status numbers or Apple error types.

## 12. Macro expansion

What `@Decision`, `@Ask`, `@Options`, and `@Levels` generate for the example
in section 4. Generated members carry the declaring type's access level;
the example's types are internal, so nothing below says `public`.

```swift
extension Team: ChoiceOption, CaseIterable, Askable, Codable {
    typealias Projection = Choice<Team>
    var optionID: String {
        switch self {
        case .returns: "returns"
        case .shipping: "shipping"
        case .billing: "billing"
        }
    }
    var criterion: Criterion {
        switch self {
        case .returns:  Criterion("Exchanges and refunds")
        case .shipping: Criterion("Delivery issues")
        case .billing:  Criterion("Payment problems")
        }
    }
    // questions(id:_:), projection(in:id:), read(_:), answers(from:id:) and
    // certain(_:) come from a framework extension on Askable where
    // Self: ChoiceOption & CaseIterable, Projection == Choice<Self>
}

extension Severity: RatingLevel, Askable, Codable {
    typealias Projection = Rating<Severity>
    static func < (low: Self, high: Self) -> Bool {
        allCases.firstIndex(of: low)! < allCases.firstIndex(of: high)!
    }
    // optionID and criterion as above
}

struct TicketTriage {
    // From @Ask, per property: a peer and a getter.
    var $team: Team.Projection                       // Choice<Team>
    var team: Team { Team.read($team) }

    var $severity: Severity.Projection               // Rating<Severity>
    var severity: Severity { Severity.read($severity) }

    var $requestsRefund: Bool.Projection             // Verdict
    var requestsRefund: Bool { Bool.read($requestsRefund) }

    // From @Decision: four members, written into the struct.
    static var questions: Questionnaire {
        Questionnaire(
            Team.questions(id: "team", Inquiry("Which team handles this ticket?"))
                + Severity.questions(id: "severity", Inquiry("How severe is the reported issue?"))
                + Bool.questions(id: "requestsRefund", Inquiry("Does the customer ask for a refund?"))
        )
    }

    init(answers: Answers) throws {
        $team = try Team.projection(in: answers, id: "team")
        $severity = try Severity.projection(in: answers, id: "severity")
        $requestsRefund = try Bool.projection(in: answers, id: "requestsRefund")
    }

    var answers: Answers {
        Answers(merging: [
            Team.answers(from: $team, id: "team"),
            Severity.answers(from: $severity, id: "severity"),
            Bool.answers(from: $requestsRefund, id: "requestsRefund"),
        ])
    }

    init(team: Team, severity: Severity, requestsRefund: Bool) {
        $team = Team.certain(team)
        $severity = Severity.certain(severity)
        $requestsRefund = Bool.certain(requestsRefund)
    }
}

extension TicketTriage: Decision, Sendable, Askable {}
```

The extension names `Askable` as well as `Decision`, although `Decision`
refines it: the `@Decision` attribute declares `Askable` among its
conformances for the enum form, and once an attribute names a protocol
the compiler expects the macro to supply it.

Every line the macro writes for a property has the same shape. The property
kind is never inspected: `Team.questions`, `Team.answers(from:id:)`, and
`Team.certain` resolve through `Askable` at type-check time (section 5.2),
so a nested decision, an optional, and a leaf all expand the same way.

An optional property, `@Ask("...", minimumConfidence: 0.7) var team: Team?`,
expands to `var team: Team? { Team?.read($team, minimumConfidence: 0.7) }`
with the peer typed `Team?.Projection`, which is `Choice<Team>`; the `T?`
sugar parses in every position the expansion needs, so the macro emits the
declared type verbatim. The plain-value initializer takes `team: Team?` and
`Team?.certain(nil)` stores `Choice.uncertain`. An implicitly unwrapped
optional is rejected with a message that says to write `Team?`. Only
`Optional` has the two-argument `read`, so a threshold on a plain property
fails to type-check, and only leaf projections conform to `Answer`, so an
optional nested decision fails to type-check too.

A nested decision property, `@Ask() var bug: BugReport`, has
`BugReport.Projection == BugReport`, so `$bug` is the nested value itself.
`BugReport.answers(from: $bug, id: "bug")` returns the nested answers with
the `bug.` prefix, and `BugReport.projection(in:id:)` scopes the unscoped
answers it is given.

The `$name` peers are declared through the macro name specifier
``prefixed(`$`)``. Hand-written code cannot declare a `$` name, which is the
intended asymmetry.

`@Ask` takes `State` for its instructions and `Criterion` for `ifTrue` and
`ifFalse`, so a string literal works and so does a value; `minimumConfidence`
is a plain `Double` on its own overload, so it cannot be written as `nil`.

## 13. Testing and evaluation

Module `DecisionModelsTesting`.

- **Plain-value initializers** from `@Decision` let unit tests exercise
  routing logic with no model: `TicketTriage(team: .billing, severity: .blocking, requestsRefund: true)`.
  Optional properties take `nil` to exercise the below-threshold branch.
- **`ScriptedModel`** answers from a closure that returns `Answers`. A test
  can return `decision.answers` for a certain case or hand-built records with
  skewed distributions to exercise the low-confidence branches.
- **`RecordingModel` and `ReplayModel`** turn real traffic into fixtures.
  `DecisionRecord` is `Codable` and holds the `DecisionRequest` (which
  carries the options metadata), the `ModelResponse`, the model identity,
  the duration, and the time of recording. Replay keys on the state, the
  questionnaire, and the sample count; metadata and timeout do not affect
  the key. Record fixtures from reads, not from plain-value decisions: a
  certain choice record lists one option, a read lists them all.
- **`Evaluation`** runs a labeled set through one or more models and
  reports, per question, accuracy, Brier score, and expected calibration
  error, plus per-band counts for a candidate threshold. Accuracy compares
  the answer the model named. Calibration bins each answer on the
  probability of the value it named, in ten equal-width bins with the last
  closed at 1.0. The evaluation scores the typed decision's round-tripped
  records, so its confidences equal what a call site thresholds on. Models
  in one evaluation must have distinct identities. Because probabilities
  are first-class, calibration checks are one function call. This is how a
  team picks thresholds on its own data and how it compares Jev, a preview
  version, and an on-device fallback on equal terms.

```swift
let latest = Jev(version: "jev-latest")
let report = try await Evaluation(models: [latest, Jev(version: "jev-preview"), onDevice])
    .run(TicketTriage.self, on: labeled)   // [(state: State, expected: TicketTriage)]
print(report[latest.identity]?.question("team")?.brierScore ?? .nan)
```

## 14. Provider mapping

| Concept | Jev | OpenRouter `OpenRouterAlpha` | Apple `LanguageModel` via guided generation | Custom conformance |
|---|---|---|---|---|
| Choice | `type: choice`, criteria map | as Jev | string property, `anyOf(optionIDs)`; criteria in prompt | any |
| Rating | `type: score`, ordered criteria array | as Jev | integer property, `range(0...n-1)`; legend in prompt | any |
| Verdict | `type: noul`, optional true/false criteria | as Jev | `Bool` property | any |
| Batch | one request, parallel evaluation | as Jev | one schema object, one generation | model decides |
| Probabilities | calibrated; reported confidence | as Jev | one-hot, or empirical from k samples; computed confidence | declared in capabilities |
| Structured criteria and instructions | native JSON | as Jev | rendered to text; declared as accepted | declared in capabilities |
| State | string, object, array | as Jev | JSON in the prompt | any |
| Limits | 255 options, 2 to 10 levels, 64k tokens | as Jev | 64 options, 2 to 10 levels, the device's context (4096 tokens); refused before sending | declared in capabilities |
| Unavailable | no key, offline, 401 | no key, offline, 401 and 403; 402 for credits | device not eligible, Apple Intelligence off, model not ready | declared |

## 15. Package layout

```
DecisionModels/
  Package.swift                      swift-tools-version 6.2, strict concurrency
  Sources/
    DecisionModels/                  core: protocols, State, wire types, Session, errors,
                                     HTTP transport and retry
    DecisionModelsMacros/            swift-syntax compiler plugin
    DecisionModelsTypeSafe/          Jev
    DecisionModelsOpenRouter/        OpenRouterAlpha
    DecisionModelsApple/             GuidedGenerationModel (FoundationModels, iOS 26+)
    DecisionModelsTesting/           Scripted, Recording, Replay, Evaluation
    DecisionModelsTestSupport/       scripted transport and fake clock for HTTP
                                     provider tests; not a product
  Tests/
    DecisionModelsTests/             macro expansion tests, answer math, session checks,
                                     HTTP client
    DecisionModelsTypeSafeTests/     wire format against recorded responses, retries
    DecisionModelsOpenRouterTests/   wire format against the documented example,
                                     status mapping
```

The core and the two hosted providers have no Apple-only dependencies and
build on Linux for server-side Swift. Only `DecisionModelsApple` needs
FoundationModels.

### 15.1 Platform minimums

| Target | Minimum | Reason |
|---|---|---|
| `DecisionModels`, `DecisionModelsTypeSafe`, `DecisionModelsOpenRouter`, `DecisionModelsTesting`, `DecisionModelsTestSupport` | iOS 18, macOS 15, Linux | `Mutex` from the Synchronization module; macros need Swift 5.9 |
| `DecisionModelsApple` | iOS 26, macOS 26 | FoundationModels: `SystemLanguageModel`, `DynamicGenerationSchema`, `respond(to:schema:)`, `GenerationOptions(temperature:)`, `Availability` are all iOS 26 |
| `GuidedGenerationModel.init(_: some LanguageModel)` | iOS 27, macOS 27 | the `LanguageModel` protocol, `PrivateCloudComputeLanguageModel`, and third-party MLX and Core AI models arrived in iOS 27 |

`Package.swift` declares iOS 18 and macOS 15. The public types in
`DecisionModelsApple` carry `@available(iOS 26, macOS 26, *)`, and the
generic initializer carries `@available(iOS 27, macOS 27, *)`. An app that
only uses Jev can ship on iOS 18. An app that wants the on-device fallback
needs iOS 26 and Apple Intelligence hardware. Nothing in the design needs
iOS 27 as a floor.

Two version-specific details for the adapter, checked against the Xcode
26.6 SDK (FoundationModels module 1.5.2) on 2026-09-19:

- That SDK has none of the iOS 27 surface: no `LanguageModel` protocol, no
  `PrivateCloudComputeLanguageModel`, no `LanguageModelError`. The generic
  initializer waits for an Xcode 27 SDK. Until then the adapter has the
  `SystemLanguageModel` initializer only, and errors arrive as
  `LanguageModelSession.GenerationError`.
- No token-usage API exists on `LanguageModelSession` or its `Response`.
  The adapter estimates `inputTokens` with `tokenCount(for:)` (26.4 and
  later) and reports `outputTokens` as 0. `contextSize` is back-deployed
  and returns 4096 before 26.4; the on-device model reports 4096.

## 16. Extensions

All four are built.

- **Set fan-out.** `@Ask("Does the request mention {option}?") var symbols: Set<Symbol>`
  expands to one yes/no question per case under `symbols.<optionID>`, with
  `{option}` replaced by the case's criterion summary in every string leaf
  of the instructions. The projection is `FanOut<Symbol>`, a
  `[Symbol: Verdict]` with a subscript, `members(atLeast:)`, and a
  `quality`; the plain `Set` holds the cases at or above 0.5, or above a
  `minimumProbability:` argument, which only a set accepts. A `Set<T>?`
  does not compile.
- **Commands as enums.** `@Decision("…") enum Command` with one `Decision`
  payload per case, as section 5.1 describes: one choice over the cases
  plus every case's arguments in one request, only the chosen case
  decoded, the probabilities on the nested `Answered` projection.
- **Hierarchical choice.** `DecisionSession.classify(_:instructions:about:beamWidth:maxDepth:options:)`
  walks a tree of `OptionTree` nodes over any `ChoiceOption` with beam
  search, one request per depth, as in the Jev hierarchical classification
  recipe. Every candidate that can still go deeper asks one `Choose` over
  its children, and all the questions of one depth travel in one request.
  A node with a single child is taken without a request and without
  weight. The result is up to `beamWidth` `HierarchicalChoice` values, best
  first, each with its `path`, its per-step `Choice` values, a `score`
  that is the geometric mean of the chosen probabilities over the steps
  that had a real choice, and `reachedLeaf`, which tells a walk cut by
  `maxDepth` from a finished one.
- **Composite scores.** `CompositeScore` is a weighted sum over
  `Rating.normalized` values and `Verdict` probabilities, built with
  `Weighted(weight, name, answer)` terms in a result builder. Weights
  normalize to sum to one and each term reports its contribution.
  `minimumConfidence` is the lowest confidence among the terms, following
  the Jev function-calling recipe: the weakest judgment sets the
  composite's reliability. A zero weight silences a term's value but not
  its doubt; drop the term with an `if` in the builder instead.

## 17. Resolved decisions

Approved 2026-09-19.

1. `Rating.value` is the most likely level. `Rating.score` is the reported
   expected value. They can differ on bimodal distributions, and both are
   visible.
2. When a model reports no confidence, the framework computes it with the
   fixed per-kind formulas in section 6.1. The rating formula matches Jev's
   published example. The formulas are not configurable.
3. One `@Ask` marker. The question kind is resolved at type-check time
   through `Askable`, not in the macro.
4. `decide` returns the decision. `respond` returns the envelope with usage,
   identity, request id, and duration.
5. The hosted provider type is named `Jev`.
6. The `$` projection mechanism is confirmed to compile (section 12).
7. Platform minimums are as given in section 15. The Apple adapter targets
   iOS 26; only the generic `LanguageModel` initializer needs iOS 27.
8. The framework ships no default model or version. Every provider
   initializer takes the model or the version as a required argument. The
   caller accepts the floating or the pinned contract by naming it.

## 18. Plan

1. Core types, wire level, `Questionnaire` and `Answers`, `DecisionSession`,
   `Jev`. No macros. Usable end to end.
2. Macros: `@Decision`, `@Ask`, `@Options`, `@Levels`, `@Criterion`, the
   `Askable` conformances, and the plain-value initializer. Macro expansion
   tests.
3. `DecisionModelsTesting`: scripted, recording, replay, evaluation.
4. `GuidedGenerationModel`, then the composition wrappers, nested decisions,
   and the section 16 extensions.
