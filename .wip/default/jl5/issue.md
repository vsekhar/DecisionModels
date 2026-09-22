---
priority: p2
type: feature
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T18:03:30-04:00
---

# Requests without state

## Summary
A caller can ask a decision with no state when the questions carry their own facts:

```swift
let capital = Verify("capital", "Is Atlanta the capital of Georgia?")
let answers = try await session.decide(Questionnaire { capital })
```

Today every entry point requires `about:`, and `DecisionRequest.state` is a non-optional `State`. The nearest workaround sends a sentinel, and with session context it sends `{"state": null, ...}`. The TypeSafe API needs no `state` field at all: on 2026-09-22 the user observed on the Jev playground that a body with only `questions` answers the Atlanta question strongly true.

## User Story
A developer asks factual or self-contained questions, or runs a questionnaire whose instructions embed the material, without inventing a state. The request that goes out has no `state` field, so the API sees the body the playground sends.

## Design Decisions
Agreed with the user on 2026-09-22:

1. **Absence, not a sentinel.** `DecisionRequest.state` is `State?`. The core never picks `""`, `{}`, or `null`.
2. **A provider fills a value only if its API requires one.** TypeSafe does not, so Jev omits the field. OpenRouter's docs call `state` required, so that provider probes the live endpoint and then either omits the field or sends a documented fallback. Apple has no wire; it drops the `STATE` block and switches to instructions that allow the model's own knowledge.
3. **Session calls without `about:`.** Swift cannot default `about state: some StateRepresentable` to `nil`, so each entry point gains an overload with no `about:`. The builder overload is unchanged.
4. **Context alone is state.** With no state and a non-empty context, the request's state is the context object. With neither, it is `nil`. A non-object state with context still nests under `state`, as today.
5. **Keys carry the optional.** `CacheKey` and `ReplayKey` hold `State?`, so a stateless request and one about an empty object are different requests.
6. **`.null` and absence are the same once they pass through JSON.** Synthesized `Codable` encodes `.some(.null)` as `null` and decodes `null` as `nil`. Documented, not fought.

## Out of Scope
- Changing `StateBuilder`: a builder with no fields still yields an empty object.
- `Evaluation.run(on:)` in the testing module keeps a required state per labelled example.
- Any change to what a provider sends when a state is present.
- New question kinds, or any change to `Questionnaire`.

## Testing Strategy
- Session tests with the scripted model check the request each call form produces, including every context merge case.
- Wire tests for Jev and OpenRouter pin the no-state body, and the parity test covers both providers at once.
- One live test per provider with the Atlanta question: Jev and OpenRouter in CI, Apple local only.
- Prompt and instruction tests for the Apple provider in both modes.
- CI's exact command with warnings as errors passes locally on Xcode 27 and on CI's Xcode 26.6 and Linux.

---

_📝 Noted on 2026-09-22 16:50:53-04:00 @ git:e5a964d+local_

Children: wip/e7t is the core change and blocks the rest. wip/8ei (Jev), wip/kst (OpenRouter), wip/169 (Apple), and wip/sxu (hierarchy, P3) are blocked on it and can run in parallel. wip/n96 (docs) is blocked on the Jev, OpenRouter, and Apple children so it documents settled behaviour.

---

_📝 Noted on 2026-09-22 17:48:26-04:00 @ git:fadedf3+local_

Design decision 2 amended, 2026-09-22, after a live probe of both APIs with a stateless noul 'Is Atlanta the capital of Georgia?' plus a control 'Is Paris the capital of Germany?': a body with no state field is rejected by TypeSafe (422, body.state 'Field required') and by OpenRouter (400, expected string, record, or array). So the playground must add a state of its own. With state "" both answer 200, Atlanta noul 0.97, control 0.01; with {} 0.97 and 0.96; with [] 0.97; with null both reject (422, 400). Decision: Jev and OpenRouterAlpha send an empty string for a nil state, and also for a State.null state, which the APIs reject as a bare null. The core stays sentinel-free (decision 1 holds); the sentinel lives in the two wire types, documented there. Decision 6 holds. wip/8ei and wip/kst implement it together; the parity test pins that both send the same body.

---

_📝 Noted on 2026-09-22 18:03:30-04:00 @ git:5171280+local_

2026-09-22: wip/in4 added after the wip/8ei and wip/kst verifier: the context merge should treat a .null state as no state, to match decision 6 and the providers' mapping. Implemented together with wip/sxu.
