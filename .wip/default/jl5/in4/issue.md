---
priority: p3
type: task
created: 2026-09-22T18:03:30-04:00
updated: 2026-09-22T18:03:30-04:00
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
