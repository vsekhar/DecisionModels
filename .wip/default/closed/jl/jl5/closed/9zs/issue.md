---
priority: p3
type: task
created: 2026-09-22T19:21:14-04:00
updated: 2026-09-22T19:33:01-04:00
---

# Drop a .null state at the session so it equals no state everywhere

## Objective
`DecisionSession` drops a `.null` state before the request exists, so `.null` and no state are the same everywhere downstream: the merge, the request, the cache and replay keys, and every provider.

## Context
Child of the parent feature. Found by the wip/n96 verifier on 2026-09-22: after wip/in4 the merge collapses `.null` only when a context exists, so with no context `request.state` is `.some(.null)`; `CacheKey` and `ReplayKey` then differ from the no-state request although both send the identical body. A `CachedModel` asked once with `about: State.null` and once with no `about:` makes two paid calls. Normalising once, at the session's pipeline entry, removes the special cases below it.

## Location
- `Sources/DecisionModels/DecisionSession.swift`: `send(_:about:options:)` and `merged(_:)`.
- `Tests/DecisionModelsTests/ContextTests.swift`.

## Approach
In `send`, `let state = state == .null ? nil : state` before `merged`. `merged` no longer needs its `.null` check; keep its doc accurate. The in4 test "A null state with no context passes through" becomes "A null state with no context sends no state" and expects `nil`. The provider-level and Apple-level `.null` mapping stays for callers that build a `DecisionRequest` themselves.

## Related Issues
Parent wip/jl5; wip/in4 (merge); wip/n96 (docs describe the rule).

## Acceptance Criteria
- [ ] A session asked with `about: State.null` and no context sends a request with `state == nil`; with a context, the context alone.
- [ ] Offline suite with warnings as errors passes; CI green.

---

_📝 Noted on 2026-09-22 19:22:32-04:00 @ git:11623e1+local_

Implemented 2026-09-22 in the main context: send() maps a .null state to nil before merged(); merged() lost its .null check; the in4 test now expects nil with no context. 479 offline tests pass with warnings as errors.

---

_📝 Noted on 2026-09-22 19:33:01-04:00 @ git:69bf22d+local_

Closed 2026-09-22. Commit on branch docs-requests-without-state, merged to main; CI run 35797105773 green. A session with about: State.null and no context now sends state nil; with a context, the context alone.
