---
priority: p3
type: task
created: 2026-09-22T16:50:52-04:00
updated: 2026-09-22T19:10:05-04:00
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

---

_📝 Noted on 2026-09-22 18:48:24-04:00 @ git:6c76094+local_

Progress 2026-09-22: implemented by one worker with wip/169, wip/sxu, and wip/in4 together; the diff matches the records. Offline suite with warnings as errors: 477 tests pass, 5 new offline. Apple live suite on this Mac: 6 tests pass; the new stateless test observed capital 1.0 ('Is Paris the capital of France?') and control 0.0 ('Is the Moon made of cheese?'). Verifier next, then CI on a branch. Worker's judgement calls kept: the private core carries the doc line 'The walk both overloads above run. Only the state differs.'; the per-depth call is an if/else on the optional state because an if expression cannot hold try await in both branches; the new overload's doc ends 'See the overload above for the walk's rules.'

---

_📝 Noted on 2026-09-22 19:10:05-04:00 @ git:6d17446+local_

Closed 2026-09-22. Commit 6d17446 on branch stateless-apple-hierarchy, merged to main. CI run 35795731059 green on macOS, Linux, and the iOS build. All acceptance criteria met. classify(_:instructions:beamWidth:maxDepth:options:) with no about: shares the walk with the existing overload; one test pins nil states on every level.
