---
priority: p1
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T01:01:39-04:00
blocked-on:
  - types
may-unblock:
  - macros
  - jev
  - testing
  - apple
  - compose
  - hier
---

# Model protocol, session, Decision and Askable

## Objective
Implement the model and session layer of `DecisionModels`: the `DecisionModel` protocol with capabilities and availability, `DecisionSession`, the `Decision` protocol, and the `Askable` protocol with its framework conformances. After this issue a caller can hand-write a `Decision` conformance and run it against a fake model.

## Context
Child of wip/dmv1. `DESIGN.md` sections 5.1 (`Decision`), 5.2 (`Askable`, `Inquiry`, the conformance table), 6.2 (`uncertain` values), 8 (session, options, response, `Usage`), 10 (model protocol, request, response, identity, capabilities, availability), 11 (errors, already defined in wip/types), and 12 (what the macro will call: `Team.questions(id:_:)`, `Team.projection(in:id:)`, `Team.read(_:)`, `Team?.read(_:minimumConfidence:)`, `$team.record`).

## Location
`Sources/DecisionModels/`: `DecisionModel.swift`, `Capabilities.swift`, `Availability.swift`, `DecisionRequest.swift`, `ModelResponse.swift`, `Usage.swift`, `DecisionSession.swift`, `DecisionOptions.swift`, `DecisionResponse.swift`, `Decision.swift`, `Askable.swift`, `Inquiry.swift`, `Environment.swift` (SwiftUI key under `#if canImport(SwiftUI)`). Tests in `Tests/DecisionModelsTests/`.

## Approach
- `DecisionSession` is `final class: Sendable`; usage lives in a `Mutex<Usage>` from `Synchronization`. Not `@Observable`.
- Pre-flight in `decide`/`respond`: `availability` first (throw `.unavailable`), then capability checks against the questionnaire (`tooManyOptions`, `tooManyLevels`, `tooManyQuestions`, `structuredCriteria`, `structuredInstructions`, `repeatedSamples`), then send, then `minimumProbabilityQuality` check on the response. Merge `context` into the state: if the state is an object, add the context fields; otherwise wrap as `["state": state] + context`. Document this rule in a doc comment.
- `respond` measures `duration` with `ContinuousClock`; `decide` calls `respond` and returns `.decision`.
- `Askable` conformances: `Bool` (`Projection == Verdict`), `Optional where Wrapped: Askable` (adds `read(_:minimumConfidence:)`; single-argument `read` wraps `.some`), extension on `Decision` (`Projection == Self`; questions prefixed; answers scoped). Provide the generic implementations for `ChoiceOption where Projection == Choice<Self>, Self: CaseIterable` and `RatingLevel where Projection == Rating<Self>` in extensions so the macros only need to emit the `typealias`.
- `Answer` gains `record: AnswerRecord`. Add `Choice.uncertain` (`where Option: CaseIterable`), `Rating.uncertain`, `Verdict.uncertain`.
- `DecisionModel.prewarm()` has a default no-op via protocol extension.
- SwiftUI: `EnvironmentValues.decisionSession: DecisionSession?` with an `@Entry`.

## Related Issues
wip/types (blocker), wip/macros, wip/jev, wip/testing, wip/apple, wip/compose (all build on this).

## Acceptance Criteria
- [ ] A hand-written `Decision` conformance (the section 4 `TicketTriage`, written without macros, using `Askable` static calls exactly as section 12 shows) round-trips through `DecisionSession` against an in-test fake `DecisionModel`.
- [ ] Pre-flight tests: unavailable model throws `.unavailable`; a choice with more options than `maximumOptionsPerChoice` throws `.unsupported(.tooManyOptions)` before the fake model is called; `minimumProbabilityQuality: .calibrated` against a `.pointEstimate` response throws `.insufficientProbabilityQuality`.
- [ ] `context` merges into object states and wraps text states.
- [ ] `usage` accumulates across concurrent `decide` calls (test with a task group).
- [ ] `Optional` gating: `Team?.read(choice, minimumConfidence: 0.7)` is `nil` below and the value at or above.
- [ ] `Decision` nested through `Askable`: a struct containing another hand-written `Decision` produces prefixed ids and decodes from scoped answers.
- [ ] `decision.answers` round-trips through `init(answers:)`.
