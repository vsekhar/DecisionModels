---
priority: p3
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T16:50:52-04:00
blocked-on:
  - e7t
---

# Hierarchy.classify without state

## Objective
Let `DecisionSession.classify(_:instructions:about:beamWidth:maxDepth:options:)` run with no state, for trees whose questions carry their own facts.

## Context
Child of the parent feature; blocked on the core child. The user deferred this on 2026-09-22 so the other entry points come first. `classify` (`Hierarchy.swift:104`) calls `decide(questionnaire, about: state, options:)` once per level (`Hierarchy.swift:132`).

## Location
- `Sources/DecisionModels/Hierarchy.swift`.
- `Tests/DecisionModelsTests`, beside the existing hierarchy tests from wip/hier.

## Approach
Add an overload with no `about:` that calls the no-state questionnaire path from the core child, and keep the walk unchanged. One test with the scripted model checks that every request the walk sends has `state == nil`.

## Related Issues
Parent feature; the core child; wip/hier, which built the helper.

## Acceptance Criteria
- [ ] The overload compiles beside the existing one with no ambiguity.
- [ ] The test passes and CI is green.
