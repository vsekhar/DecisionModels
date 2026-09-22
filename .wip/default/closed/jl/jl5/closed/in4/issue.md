---
priority: p3
type: task
created: 2026-09-22T18:03:30-04:00
updated: 2026-09-22T19:10:05-04:00
---

# Treat a .null state as no state in the context merge

## Objective
`DecisionSession.merged(_:)` treats a `.null` state the same as no state: with a standing context the request's state is the context alone, and with no context it is `nil`.

## Context
Child of the parent feature. Found by the wip/8ei and wip/kst verifier on 2026-09-22. Parent decision 6 says `.null` and no state are the same once they pass through JSON, and both providers now send an empty string for either. But the core merge from wip/e7t nests a `.null` state under a `state` key beside the context, so `session.decide(q, about: State.null)` on a session with context `["account": "gold"]` reaches the provider as `.object(["state": .null, "account": .text("gold")])`, an object with a null member. That is legal JSON and the APIs accept it, but it contradicts the rule the rest of the design follows.

## Location
- `Sources/DecisionModels/DecisionSession.swift`, `merged(_:)`, and its doc comment.
- `Tests/DecisionModelsTests/ContextTests.swift`.

## Approach
In `merged(_:)`, the `if let state` guard becomes `if let state, state != .null`, so `.null` falls through to the context-alone path. With no context, `.null` passes through unchanged as today (the provider maps it). Doc comment gains: "A `.null` state counts as no state." Two tests in `ContextTests.swift`: "A null state with a context sends the context alone" expects `.object(["policy": ...])`; "A null state with no context passes through" expects `.null`.

## Related Issues
Parent wip/jl5; wip/e7t wrote `merged(_:)`; wip/8ei and wip/kst map `.null` on the wire.

## Acceptance Criteria
- [ ] Both tests pass; the four existing merge tests are unchanged.
- [ ] Offline suite with warnings as errors passes; CI green.

---

_📝 Noted on 2026-09-22 18:48:24-04:00 @ git:6c76094+local_

Progress 2026-09-22: implemented by one worker with wip/169, wip/sxu, and wip/in4 together; the diff matches the records. Offline suite with warnings as errors: 477 tests pass, 5 new offline. Apple live suite on this Mac: 6 tests pass; the new stateless test observed capital 1.0 ('Is Paris the capital of France?') and control 0.0 ('Is the Moon made of cheese?'). Verifier next, then CI on a branch. Guard is 'if let state, state != .null'; two ContextTests added; the four existing merge tests unchanged.

---

_📝 Noted on 2026-09-22 18:57:24-04:00 @ git:6c76094+local_

Amendment 2026-09-22 from the verifier: with no context, merged() passes .null through, and the Apple adapter then treated it as a state (stateful instructions, a prompt opening 'STATE null'). Jev and OpenRouter already map .null like nil, so the Apple adapter does the same, here rather than in a new issue: DecisionPromptBuilder gains 'static func hasState(_ state: State?) -> Bool' returning false for nil and .null; prompt(state:) skips the STATE block for .null too; GuidedGenerationModel.decide passes hasState: DecisionPromptBuilder.hasState(request.state). Tests: 'A null state is no state for the prompt' (prompt(state: .null) starts at the first heading) and 'A null state is no state for the instructions' (hasState(.null) == false, hasState(nil) == false, hasState(.text("")) == true). The DecisionSession init doc comment also gains the merge rule for .null.

---

_📝 Noted on 2026-09-22 19:05:51-04:00 @ git:6c76094+local_

Apple side done 2026-09-22: DecisionPromptBuilder.hasState(_:), prompt(state:) skips STATE for .null, decide passes the flag; two PromptBuilderTests added; DecisionSession init doc updated.

---

_📝 Noted on 2026-09-22 19:10:05-04:00 @ git:6d17446+local_

Closed 2026-09-22. Commit 6d17446 on branch stateless-apple-hierarchy, merged to main. CI run 35795731059 green on macOS, Linux, and the iOS build. All acceptance criteria met. merged() and the Apple adapter both treat .null as no state; Jev and OpenRouter already did.
