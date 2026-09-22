---
priority: p3
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T17:51:22-04:00
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

---

_📝 Noted on 2026-09-22 17:51:22-04:00 @ git:fadedf3+local_

Design record, 2026-09-22, for wip/sxu.

### 1. `DecisionSession.classify` (`Sources/DecisionModels/Hierarchy.swift:104`)
The body of the existing `classify(_:instructions:about:beamWidth:maxDepth:options:)` moves into a private `classify(_ roots:instructions:state: State?, beamWidth:maxDepth:options:)`. The existing public overload calls it with `state.stateRepresentation`. A new public overload with no `about:` calls it with `nil`:
`classify<Option: ChoiceOption>(_ roots: [OptionTree<Option>], instructions: State, beamWidth: Int = 1, maxDepth: Int = 8, options: DecisionOptions? = nil) async throws -> [HierarchicalChoice<Option>]`
Doc comment, verbatim: "Classifies with no state, for trees whose questions carry their own facts. The standing context, if any, is the whole state." followed by a reference to the overload above for the walk's rules.
Inside the walk, the one call `decide(questionnaire, about: state, options: options)` becomes: `if let state { try await decide(questionnaire, about: state, options: options) } else { try await decide(questionnaire, options: options) }`, or a two-line private helper if that reads better. The walk is otherwise unchanged.

### 2. Test (`Tests/DecisionModelsTests/HierarchyTests.swift`)
"A walk with no state sends no state", beside "A greedy walk returns the best leaf and the geometric mean": `treeModel(branchTable)`, `session.classify(supportAndSales, instructions: instructions)` with no `about:`; expect the same best path `["support", "refund"]`, `model.callCount == 2`, and `model.requests.map(\.state) == [nil, nil]`.

### Checks
`swift test -Xswiftc -warnings-as-errors --skip GuidedGenerationLiveTests --skip JevLive --skip OpenRouterLive`.
