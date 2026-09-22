---
priority: p1
type: task
created: 2026-09-22T16:50:25-04:00
updated: 2026-09-22T17:40:11-04:00
may-unblock:
  - 8ei
  - kst
  - 169
  - sxu
---

# Optional state in DecisionRequest, session calls without about:, merge, and keys

## Objective
Make state optional at the core: `DecisionRequest.state` becomes `State?`, `DecisionSession` gains calls with no `about:`, the context merge treats "no state" as "context only", and the cache and replay keys carry the optional. The package builds and every existing test passes. Providers change only as much as compiling needs; their behaviour and tests belong to the sibling issues.

## Context
Child of the parent feature; read it first for the six design decisions. A caller wants to ask a question that carries its own facts, such as `Verify("capital", "Is Atlanta the capital of Georgia?")`, with no state. The TypeSafe API accepts a body with no `state` field: on 2026-09-22 the user observed on the Jev playground that a body with only `questions` answers that question strongly true.

Today every entry point requires `about:`, `DecisionRequest.state` is a non-optional `State`, and `DecisionSession.merged(_:)` (`DecisionSession.swift:221`) nests a non-object state under a `state` key beside the context. So the nearest idiom sends `{"state": null, ...}`.

Absence is the model, not a sentinel. Nothing in the core chooses between `""`, `{}`, and `null`.

## Location
- `Sources/DecisionModels/DecisionRequest.swift`: `state: State?`, default `nil` in the initializer, doc comment.
- `Sources/DecisionModels/DecisionSession.swift`: five new overloads; `answer(_:about:options:)` and `send(_:about:options:)` take `State?`; `merged(_:)` returns `State?`.
- `Sources/DecisionModels/Composition/DecisionCache.swift`: `CacheKey.state: State?`.
- `Sources/DecisionModels/Composition/CascadeModel.swift:122` and `ConsensusModel.swift:99` pass `request.state` through; the type change should need no edit there.
- `Sources/DecisionModelsTesting/DecisionRecord.swift`: `ReplayKey.state: State?` in both initializers. `ReplayModel.swift` looks records up by that key and needs no edit.
- `Sources/DecisionModelsTypeSafe/JevWire.swift` and `Sources/DecisionModelsOpenRouter/OpenRouterWire.swift`: `var state: State?`, encoded only when present, so a `nil` state sends no `state` key. `Jev.swift:120` and `OpenRouterAlpha.swift:138` then compile unchanged.
- `Sources/DecisionModelsApple/PromptBuilder.swift:55`: `prompt(state:questionnaire:fieldNames:)` takes `State?` and skips the `STATE` block and its JSON when `nil`. The standing instructions text is unchanged here; the Apple sibling owns it.
- Tests: `Tests/DecisionModelsTests` for the session, the request's `Codable`, and the cache key. Existing wire, parity, and prompt tests stay green unchanged.

## Approach
1. `DecisionRequest`: `public let state: State?` and `init(state: State? = nil, questionnaire:samples:timeout:metadata:)`. Synthesized `Codable` uses `encodeIfPresent`, so a request with no state encodes with no `state` key. One conflation follows: `.some(.null)` encodes as `null`, and decoding `null` gives `nil`, so a `.null` state and no state are the same once they pass through JSON. Say so on the property. Do not write a custom `Codable` to fight it.
2. Session overloads. Swift cannot default `about state: some StateRepresentable` to `nil`, because it cannot infer the type from `nil`. So add one overload per entry point with no `about:` label at all:
   - `decide<D: Decision>(_ type: D.Type = D.self, options: DecisionOptions? = nil) async throws -> D`
   - `respond<D: Decision>(_ type: D.Type = D.self, options: DecisionOptions? = nil) async throws -> DecisionResponse<D>`
   - `decide<A: Askable>(_ type: A.Type = A.self, options: DecisionOptions? = nil) async throws -> A where A.Projection: Decision`
   - `respond<A: Askable>(_ type: A.Type = A.self, options: DecisionOptions? = nil) async throws -> DecisionResponse<A.Projection> where A.Projection: Decision`
   - `decide(_ questionnaire: Questionnaire, options: DecisionOptions? = nil) async throws -> Answers`
   The builder overload takes a trailing closure, so `session.decide(Foo.self)` binds to the new overload and `session.decide(Foo.self) { Field("a", 1) }` to the builder. Mirror the existing doc comments; each new one says the questions must carry their own facts.
3. `merged(_:)`: no context and no state gives `nil`; context and no state gives `.object(context)`; context and an object state merges as today, the state winning on a shared key; context and any other state nests it under `state` as today.
4. `CacheKey.state` and `ReplayKey.state` become `State?`. A request with no state and a request about `.object([:])` hash differently. That is right: they are different requests.
5. Providers and the Apple prompt: the minimum to compile and to keep the current wire shape when a state is present. The wire types already declare `CodingKeys`, and synthesis uses `encodeIfPresent` for an optional property, so `var state: State?` should be enough; confirm with the existing documented-shape tests, which must still match byte for byte.

## Related Issues
Parent feature, and the sibling children for Jev, OpenRouter, Apple, docs, and the hierarchy call. wip/session built the session, wip/compose the cache, wip/testing the replay key, wip/jev and wip/sxs the two wire modules.

## Acceptance Criteria
- [ ] `DecisionRequest(questionnaire: q)` compiles, has `state == nil`, encodes to JSON with no `state` key, and decodes back with `state == nil`.
- [ ] A test compiles every call form with no ambiguity: `session.decide(Foo.self)`, `let x: Foo = try await session.decide()`, `session.respond(Foo.self)`, `session.decide(Foo.self) { Field("a", 1) }`, `session.decide(about: "text")`, `session.decide(questionnaire)`, and the `Askable` pair.
- [ ] Session tests with the scripted model from `DecisionModelsTestSupport` check the request the model receives: no state and no context gives `state == nil`; no state with context `["policy": p]` gives `.object(["policy": p])`; a text state with context still nests under `state`; an object state with context still merges with the state winning.
- [ ] `CacheKey` and `ReplayKey` tests: no state and `.object([:])` are different keys; two no-state requests with the same questions and samples are the same key.
- [ ] The existing Jev and OpenRouter documented-shape wire tests, the parity test, and the Apple prompt tests pass unchanged.
- [ ] `swift test -Xswiftc -warnings-as-errors --skip GuidedGenerationLiveTests --skip JevLive --skip OpenRouterLive` passes locally, and CI is green on all three jobs.

---

_📝 Noted on 2026-09-22 17:09:44-04:00 @ git:2f0531d+local_

Design record, 2026-09-22. This is the shape wip/e7t implements. The worker brief quotes it and the verifier checks against it.

### 1. DecisionRequest (`Sources/DecisionModels/DecisionRequest.swift`)
`public let state: State?`. Doc comment, verbatim:
"The material to judge, or `nil` when the questions carry their own facts. Through JSON, `.null` and `nil` come out the same: both decode as `nil`."
Initializer: `init(state: State? = nil, questionnaire: Questionnaire, samples: Int = 1, timeout: Duration? = nil, metadata: [String: String] = [:])`. Synthesized `Codable` stays; it uses `encodeIfPresent` and `decodeIfPresent`, so a `nil` state writes no `state` key.

### 2. DecisionSession (`Sources/DecisionModels/DecisionSession.swift`)
The private `answer(_:about:options:)`, `send(_:about:options:)`, and `merged(_:)` take `State?`; `merged` returns `State?`. The existing public overloads keep their bodies. Five new public overloads, each placed right after the overload it mirrors:
- `decide<D: Decision>(_ type: D.Type = D.self, options: DecisionOptions? = nil) async throws -> D`
- `respond<D: Decision>(_ type: D.Type = D.self, options: DecisionOptions? = nil) async throws -> DecisionResponse<D>`
- `decide<A: Askable>(_ type: A.Type = A.self, options: DecisionOptions? = nil) async throws -> A where A.Projection: Decision`
- `respond<A: Askable>(_ type: A.Type = A.self, options: DecisionOptions? = nil) async throws -> DecisionResponse<A.Projection> where A.Projection: Decision`
- `decide(_ questionnaire: Questionnaire, options: DecisionOptions? = nil) async throws -> Answers`
Each passes `nil` as the state. Doc comment for each, verbatim: "Asks with no state, for questions that carry their own facts. The standing context, if any, is the whole state." The `Askable` pair appends: "A plain `Decision` binds to the `Decision` call above."
`merged(_:)`: an empty context returns the state unchanged, so `nil` stays `nil`. A non-empty context with no state gives `.object(context)`. A non-empty context with an object state merges as today, the state winning on a shared key. A non-empty context with any other state nests it under `state`, as today. Add one sentence to its doc comment: "No state with a context gives the context alone."

### 3. CacheKey (`Sources/DecisionModels/Composition/DecisionCache.swift`)
`public let state: State?`. Doc comment: "The material the model judged, or `nil`." The initializer body is unchanged.

### 4. ReplayKey (`Sources/DecisionModelsTesting/DecisionRecord.swift`)
`public var state: State?`. `init(state: State? = nil, questionnaire: Questionnaire, samples: Int = 1)`. `init(_ request:)` body unchanged.

### 5. Wire types
`JevRequest.state` and `OpenRouterRequest.state` become `var state: State?`. Doc comment on both, verbatim: "The material to judge: a text, an object, or an array. Absent when the request has none; the field is then left out." The existing `CodingKeys` stay and synthesis encodes an optional with `encodeIfPresent`, so no `state` key goes out for `nil`. `Jev.swift:120` and `OpenRouterAlpha.swift:138` need no edit. The documented-shape wire tests and the parity test must pass unchanged.

### 6. Apple prompt (`Sources/DecisionModelsApple/PromptBuilder.swift`)
`prompt(state: State?, questionnaire:fieldNames:)`. With a state the output is byte for byte what it is today. With `nil` there is no `STATE` line and no JSON: the output starts at the first question heading. `GuidedGenerationModel.swift:108` passes `request.state` through unchanged. The standing instructions are not touched here; wip/169 owns them.

### 7. Composition
`CascadeModel` and `ConsensusModel` forward `request.state`; the type change needs no edit there.

### Tests
Idioms: `FakeModel(answers:)` plus `model.requests.first`, as in `Tests/DecisionModelsTests/ContextTests.swift` and `SessionTests.swift`. Test names in the house style: a sentence that states the behaviour.
- `ContextTests.swift`, two tests: "No state with a context sends the context alone" expects `.object(["policy": .text("Refunds within 30 days")])`; "No state and no context sends no state" expects `request.state == nil`. Both call `session.decide(Questionnaire { question })` with no `about:`.
- `SessionTests.swift`: "A decision asks with no state": `let triage: TicketTriage = try await session.decide()` against `FakeModel(answers: triageAnswers)`, expect the request's state is `nil` and `triage.team == .returns`. "Every call form binds without ambiguity": one test that calls, in turn, `session.decide(TicketTriage.self)`, `let _: TicketTriage = try await session.decide()`, `session.respond(TicketTriage.self)`, `session.decide(TicketTriage.self) { Field("a", 1) }`, `session.decide(TicketTriage.self, about: "text")`, `session.decide(TicketTriage.questions)`, and the `Askable` pair `session.decide(Team.self)` and `session.respond(Team.self)` with answers built the way `AskableTests.swift` builds them; it checks the state of each request: `nil`, `nil`, `nil`, `.object(["a": .number(1)])`, `.text("text")`, `nil`, `nil`, `nil`.
- `CodableRoundTripTests.swift`: "A request with no state encodes with no state field": encode `DecisionRequest(questionnaire:)`, assert the JSON object has no `state` key, decode, assert `state == nil`. "A null state decodes as no state": encode `DecisionRequest(state: .null, questionnaire:)`, decode, assert `state == nil`.
- Cache key tests, in the Composition test file that covers `CachedModel`: "No state and an empty object are different keys"; "Two requests with no state share a key".
- `Tests/DecisionModelsTestingTests/RecordReplayTests.swift`: "A replay matches a request with no state": record a response for a request with no state, replay it through `ReplayModel`, and check that the same questions about `.object([:])` miss.

### Checks
`swift test -Xswiftc -warnings-as-errors --skip GuidedGenerationLiveTests --skip JevLive --skip OpenRouterLive` from the package root on this Mac. No live suite. CI on a pushed branch then checks the Xcode 26.6 SDK and Linux; the main context does that, not the worker.

### Dead code
Every new overload has a caller in the tests above. Nothing is removed.

---

_📝 Noted on 2026-09-22 17:10:11-04:00 @ git:2f0531d+local_

Design record amendment: the call-form test 'Every call form binds without ambiguity' lives in Tests/DecisionModelsTests/CommandSessionTests.swift, beside the existing overload-resolution tests, and uses that file's fixtures: DeskTriage for the Decision forms and HandCommand with commandAnswers for the Askable pair (session.decide(HandCommand.self) and session.respond(HandCommand.self)). The SessionTests.swift test 'A decision asks with no state' stays as written.

---

_📝 Noted on 2026-09-22 17:18:48-04:00 @ git:2f0531d+local_

Progress 2026-09-22: implementation done by a worker from the design record; the source diff matches it line for line. Two sites the record did not list needed a change because they index a dictionary by request.state: Tests/DecisionModelsTestingTests/Fixtures.swift:155 and EvaluationTests.swift:41 now unwrap the optional first and throw the same malformedResponse for a nil state as for an unscripted one. Judgement calls the worker made, all consistent with the record: merged() wraps the two old branches in 'if let state' so nil falls through to .object(context); ContextTests.state(of:) returns State?; the call-form test compares [State?] arrays against model.requests.map(\.state), using a second FakeModel for the Askable pair; the cache hit test varies metadata so a hit proves the key. Local run: swift test -Xswiftc -warnings-as-errors with the three live suites skipped, 466 tests passed, 9 new, no warnings. Dead code checked by hand: every new overload has a caller in the call-form test; nothing removed; no unused field, parameter, or import. Verifier dispatched next; CI on a branch after that.

---

_📝 Noted on 2026-09-22 17:28:04-04:00 @ git:2f0531d+local_

Verifier 2026-09-22: no blocker, no should-fix, five notes. Acted on three in the main context: (1) DecisionRequest's type doc now reads 'asked about one state or about none'; (2) the wire doc sentence on JevRequest.state and OpenRouterRequest.state is active: 'Absent when the request has none; the encoder then omits the field.' (the design record's wording was passive; this supersedes it); (3) the stateless Apple prompt had a leading newline because the question loop always prefixed '\n## '; the record says the output starts at the first heading, so the prefix is now '## ' when nothing precedes it, and PromptBuilderTests gained 'A prompt with no state starts at the first question', which failed on the old bytes (hasPrefix false) and passes after the fix. The stateful prompt is byte for byte unchanged. Two notes went to siblings: DESIGN.md line 818 drift and the replay consequence of the .null conflation to wip/n96; the prompt shape to wip/169. Verifier also proved outside the suite that a nil state sends no state key on both providers and that a plain Decision binds to the Decision overload.

---

_📝 Noted on 2026-09-22 17:40:11-04:00 @ git:4f4c724+local_

Closed 2026-09-22. Commit 4f4c724 on branch e7t-optional-state. DecisionRequest.state is State?; DecisionSession has five overloads with no about: (decide and respond for Decision, decide and respond for Askable, decide for a Questionnaire); merged() gives the context alone for no state and nil for neither; CacheKey and ReplayKey hold State?; JevRequest and OpenRouterRequest omit the state field for nil; the Apple prompt drops its STATE block and starts at the first heading. 10 new tests (9 from the record plus the stateless prompt shape test), 467 offline tests pass with warnings as errors on Xcode 27 locally. CI run 35787675189 green on macOS (Xcode 26.6, warnings as errors), Linux, and the iOS build. All six acceptance criteria met. Left for siblings: Apple instructions (wip/169), provider wire and live tests (wip/8ei, wip/kst), hierarchy (wip/sxu), docs including the DESIGN.md line 818 drift and the .null replay note (wip/n96).
