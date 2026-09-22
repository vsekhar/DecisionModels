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
