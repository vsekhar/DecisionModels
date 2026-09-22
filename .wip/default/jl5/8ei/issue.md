---
priority: p2
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T16:50:52-04:00
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
