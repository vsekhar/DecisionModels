---
priority: p1
type: task
created: 2026-09-22T16:50:25-04:00
updated: 2026-09-22T16:50:52-04:00
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
