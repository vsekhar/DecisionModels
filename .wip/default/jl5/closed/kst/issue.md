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

# OpenRouterAlpha: settle what the endpoint needs for a request with no state

## Objective
Find out whether OpenRouter's alpha Decisions endpoint accepts a body with no `state` field, make `OpenRouterAlpha` do the right thing either way, and pin it with wire, parity, and live tests.

## Context
Child of the parent feature; blocked on the core child. OpenRouter's docs, as read on 2026-09-20 for wip/sxs, call `state` one of three required fields. The endpoint proxies to TypeSafe, whose own API accepts a missing state. The parent's rule is that the core never invents a value and a provider fills one in only if its API requires it. This is the one provider where that is unknown, so the first step is a live probe.

## Location
- `Sources/DecisionModelsOpenRouter/OpenRouterWire.swift` and `OpenRouterAlpha.swift`.
- `Tests/DecisionModelsOpenRouterTests/WireTests.swift`, `ParityTests.swift`, and `OpenRouterLiveTests.swift`.
- `TESTING.md`: the OpenRouter suite's request count.

## Approach
1. Probe: with `OPENROUTER_API_KEY`, send the Atlanta noul with no `state` key to `POST /api/alpha/decisions`, from a scratch script or a temporary live test. Record the request, the status, and the response body in a note on this issue.
2. If it answers 200: the provider omits the field, the same as Jev. The parity test gains a no-state case in which both providers produce the same JSON with no `state` key.
3. If it rejects the body with 400 or 422: the provider sends a documented fallback for a `nil` state. Prefer the empty string, the smallest value inside the documented set of string, object, or array. Say so in the `OpenRouterAlpha` doc comment and on the wire type. The parity test then expects exactly that one difference for a no-state request and no difference otherwise.
4. A wire test pins the no-state body in whichever shape step 2 or 3 settles. A live test in `OpenRouterLiveTests.swift` asks the Atlanta question with the same threshold rule as the Jev sibling.

## Related Issues
Parent feature; the core child; the Jev sibling.

## Acceptance Criteria
- [ ] A note on this issue records the probe's request, status, and response.
- [ ] Wire, parity, and live tests pass, and CI is green.
- [ ] Doc comments say what the provider sends for a request with no state and why.

---

_📝 Noted on 2026-09-22 17:48:26-04:00 @ git:fadedf3+local_

Probe done in the main context 2026-09-22 (step 1 of the Approach). Request: POST /api/alpha/decisions, model typesafe/jev-1.13, no state field, one noul 'Is Atlanta the capital of Georgia?'. Status 400, body: invalid_union, 'expected string, received undefined' / 'expected record' / 'expected array'. With state "": 200, noul 0.97 (control 'Is Paris the capital of Germany?' 0.01). With {}: 200, 0.96. With []: 200, 0.97. With null: 400. Step 3 applies: send the empty string for nil and for .null. TypeSafe behaves the same (422 without the field), so wip/8ei takes the same shape and one worker implements both; the parity test gains a no-state case expecting identical bodies with "state": "".

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
