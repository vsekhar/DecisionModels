---
priority: p2
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T18:36:22-04:00
blocked-on:
  - e7t
may-unblock:
  - n96
---

# Jev sends no state field for a request with no state, with wire and live tests

## Objective
The Jev provider sends a body with no `state` key when the request has no state, which is what the TypeSafe playground sends, with a wire test that pins the shape and a live test that asks a question carrying its own facts.

## Context
Child of the parent feature; blocked on the core child, which makes `JevRequest.state` optional and encodes it only when present. On 2026-09-22 the user observed on the Jev playground that a body with only `questions`, holding one noul with instructions "Is Atlanta the capital of Georgia?", answers strongly true. This issue proves the shape offline and the behaviour live.

## Location
- `Sources/DecisionModelsTypeSafe/Jev.swift` and `JevWire.swift`: doc comments say a request may carry no state and that nothing goes on the wire for it.
- `Tests/DecisionModelsTypeSafeTests/WireTests.swift`: one test in the style of "A noul with no sides sends no criteria" (`WireTests.swift:159`).
- `Tests/DecisionModelsTypeSafeTests/JevLiveTests.swift`: one live test in the style of "Jev triages a support ticket".
- `TESTING.md`: the Jev suite's paragraph counts its requests ("two requests"); update the count.

## Approach
- Wire test: build `DecisionRequest(questionnaire:)` with a single `Verify("capital", "Is Atlanta the capital of Georgia?")`, send it through `Jev` with the scripted transport from `DecisionModelsTestSupport`, decode the body as a JSON object, and assert its keys are exactly `model` and `questions`.
- Live test: `Jev(version: "jev-latest", apiKey: key).decide(DecisionRequest(questionnaire:timeout:))`, then expect `answers.records["capital"]` to be `.verdict(probability: p)` with `p` at or above a threshold. The user reports "strongly true"; read the value off one real run and leave a margin, and record the run in a note on this issue. The test fails, not skips, without `TYPESAFE_API_KEY`, like the others in the file.
- The same live test also runs the request through `DecisionSession(model:).decide(questionnaire)` with no `about:`, which checks the no-state path end to end.

## Related Issues
Parent feature; the core child; the OpenRouter sibling, whose parity test compares this provider's body with OpenRouter's.

## Acceptance Criteria
- [ ] The wire test passes with no network.
- [ ] The live test passes against the service with `TYPESAFE_API_KEY`, and CI's macOS and Linux jobs run it on push.
- [ ] Doc comments on `Jev` and `JevRequest` state the behaviour.
- [ ] A note on this issue records the probability the live service returned.

---

_📝 Noted on 2026-09-22 17:48:26-04:00 @ git:fadedf3+local_

Correction 2026-09-22 from a live probe: TypeSafe's API rejects a body with no state field (422, body.state 'Field required') and a null state (422). It accepts "" (Atlanta noul 0.97, control 'Is Paris the capital of Germany?' 0.01), {} (0.97), and [] (0.97). So Jev sends an empty string for a nil state and for a State.null state; the Objective's 'no state key' is wrong and the wire test asserts "state": "" instead. Live threshold: Atlanta >= 0.9 and the control <= 0.1, both in one request. Implemented together with wip/kst by one worker.

---

_📝 Noted on 2026-09-22 17:49:38-04:00 @ git:fadedf3+local_

Design record, 2026-09-22, for wip/8ei and wip/kst together: one worker, one diff, two issues. It supersedes the "no state key" wording in both issues' Objective and in wip/e7t's section 5.

### Facts from the live probe
TypeSafe `POST /v1/systemone` and OpenRouter `POST /api/alpha/decisions` both require a state. No field: 422 and 400. `null`: 422 and 400. `""`, `{}`, and `[]`: 200 on both; the stateless noul "Is Atlanta the capital of Georgia?" scores 0.96 to 0.97 and the control "Is Paris the capital of Germany?" scores 0.01 in every accepted form.

### 1. Wire types (`Sources/DecisionModelsTypeSafe/JevWire.swift`, `Sources/DecisionModelsOpenRouter/OpenRouterWire.swift`)
The wire struct describes the wire, so its `state` is a non-optional `State` again: `var state: State`. Each struct gains an explicit initializer with the same labels the provider already uses, `init(state: State?, model: String, questions: [String: Question])` for Jev and `init(model: String, state: State?, questions: [String: Question])` for OpenRouter, that maps `nil` and `.null` to `.text("")` and keeps any other value as it is. Synthesized `Encodable` and the existing `CodingKeys` stay. `Jev.decide` and `OpenRouterAlpha.decide` keep their `state: request.state` argument and need no edit.
Doc comment on both `state` properties, verbatim:
"The material to judge: a text, an object, or an array. The service requires one and rejects a bare `null`, so a request with no state, or with a `.null` state, sends an empty string. The model then answers from the questions alone."

### 2. Type docs
`Jev` (`Jev.swift`, the type's doc comment) and `OpenRouterAlpha` (its type doc comment) each gain one paragraph, placed after the paragraph about the version or the model name and before the code example, verbatim:
"A request with no state, or with a `.null` state, sends an empty string as the state, because the service requires one and rejects a bare `null`. The model then answers from the questions alone."

### 3. Tests
Idioms: `harness(...)` from each module's `Fixtures.swift` returns a model and its scripted transport; read the sent body with the file's `object(_:)` helper. Test names state the behaviour.
- `Tests/DecisionModelsTypeSafeTests/WireTests.swift`: "A request with no state sends an empty string as the state": decide `DecisionRequest(questionnaire: Questionnaire { Verify("capital", "Is Atlanta the capital of Georgia?") })` through `harness([.ok(sampleResponse)])`, assert the body's `state` is the string `""` and `questions` has one entry. "A null state sends an empty string too": the same with `DecisionRequest(state: .null, ...)`.
- `Tests/DecisionModelsOpenRouterTests/WireTests.swift`: the same two tests against `harness([.ok(documentedResponse)])`.
- `Tests/DecisionModelsOpenRouterTests/ParityTests.swift`: "Both providers send an empty string for no state": a request with no state through both providers, as the existing parity test does; assert both bodies carry `state == ""` and equal `questions`.
- `Tests/DecisionModelsTypeSafeTests/JevLiveTests.swift`: "Jev answers questions that carry their own facts": `guard let key = liveKey()`; a questionnaire of `Verify("capital", "Is Atlanta the capital of Georgia?")` and `Verify("control", "Is Paris the capital of Germany?")`; `DecisionSession(model: Jev(version: "jev-latest", apiKey: key), options: DecisionOptions(timeout: .seconds(60)))` if `DecisionOptions` takes a timeout, otherwise the default options; `let answers = try await session.decide(questionnaire)` with no `about:`; expect `answers.records["capital"]` is `.verdict(probability: p)` with `p >= 0.9` and `answers.records["control"]` is `.verdict(probability: q)` with `q <= 0.1`. One request.
- `Tests/DecisionModelsOpenRouterTests/OpenRouterLiveTests.swift`: the same test for `OpenRouterAlpha(model: "typesafe/jev-1.13", apiKey: key)`.
- `TESTING.md`: the Jev suite makes three requests, the OpenRouter suite two.

### Checks
1. `swift test -Xswiftc -warnings-as-errors --skip GuidedGenerationLiveTests --skip JevLive --skip OpenRouterLive`
2. `set -a; . ./.env; set +a; swift test --filter JevLive` and the same with `--filter OpenRouterLive`. Never print the keys or `.env`.
CI on a branch afterwards checks the 26.6 SDK and Linux from the main context.

---

_📝 Noted on 2026-09-22 17:55:40-04:00 @ git:fadedf3+local_

Progress 2026-09-22: implemented by one worker for wip/8ei and wip/kst from the shared design record; the diff matches it. Wire types hold a non-optional State again with an initializer that maps nil and .null to an empty string; the providers' decide calls needed no edit. Live, through the session with no about:: Jev jev-latest capital 0.97, control 0.0; OpenRouter typesafe/jev-1.13 capital 0.97, control 0.01. Offline suite with warnings as errors: 472 tests pass, 7 new (2+2 wire, 1 parity, 2 live). Worker's judgement calls, all kept: a private capital questionnaire and sentBody helper in each wire test file; a short doc comment on each new initializer; one print line per live test in the idiom of GuidedGenerationLiveTests; the live suite doc comments' request counts updated with TESTING.md. Dead code checked by hand: the new initializers are the ones the providers call; helpers have two callers each; nothing removed. Verifier next, then CI on a branch.

---

_📝 Noted on 2026-09-22 18:03:30-04:00 @ git:5171280+local_

Verifier 2026-09-22: no blocker, no should-fix. Conformance, the mapping for eleven state shapes through both providers in a scratch package (nil and .null give an empty string, everything else passes through untouched, no body ever omits state or carries a bare null), parity, live-test shape, request counts, dead code, and prose all clean. 472 offline tests pass with warnings as errors. Two notes: (1) a .null state on a session with a standing context reaches the provider as an object with a null member, because the core merge nests it; filed as a small core issue under wip/jl5 so the merge treats .null like no state. (2) A caller's genuine empty-string state and no state are the same on the wire; the core keys keep them apart; noted on wip/n96 for the docs.

---

_📝 Noted on 2026-09-22 18:36:22-04:00 @ git:5171280+local_

Closed 2026-09-22. Commit 5171280 on branch providers-empty-state, merged to main. Both wire types hold a non-optional State; their initializers map nil and .null to an empty string; the core is untouched. CI run 35790215719 green on macOS with the Jev and OpenRouter live suites, Linux with both live suites, and the iOS build. Live: Jev capital 0.97 control 0.0; OpenRouter capital 0.97 control 0.01. All acceptance criteria met.
