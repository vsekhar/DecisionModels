---
priority: p2
type: task
created: 2026-09-19T01:01:39-04:00
updated: 2026-09-19T04:52:06-04:00
blocked-on:
  - session
may-unblock:
  - docs
---

# Hierarchical choice helper

## Objective
Add a hierarchical choice helper: walk a tree of options with beam search, one request per depth, as in the Jev hierarchical classification recipe.

## Context
Child of wip/dmv1. `DESIGN.md` section 16, third bullet.

## Location
`Sources/DecisionModels/Hierarchy.swift`, tests in `Tests/DecisionModelsTests/`.

## Approach
- `struct OptionTree<Option: ChoiceOption>: Sendable { let option: Option; let children: [OptionTree] }` with a result-builder initializer.
- `extension DecisionSession { func classify<O>(_ tree: [OptionTree<O>], instructions: State, about state: some StateRepresentable, beamWidth: Int = 1, maxDepth: Int = 8) async throws -> HierarchicalChoice<O> }` returning the path of options, the per-step `Choice` values, and a path score equal to the geometric mean of edge probabilities. Each depth is one `Questionnaire` with one `Choose` per surviving beam candidate (siblings of that candidate), so beams share a request.
- Leaf reached when a candidate has no children.

## Related Issues
wip/session (blocker).

## Acceptance Criteria
- [ ] With a fake model scripted per depth, greedy search returns the expected leaf path and score.
- [ ] Beam width 2 keeps two paths after depth 1 and asks both sibling sets in one request at depth 2 (assert the questionnaire the fake receives).
- [ ] `maxDepth` stops the walk.

---

_📝 Noted on 2026-09-19 04:52:06-04:00 @ git:580dc35+local_

Done in the compose worktree, merged by copy. OptionTree with a builder, HierarchicalChoice with path, steps, score and reachedLeaf, DecisionSession.classify with beam search and one request per depth. Verifier: all criteria hold. Its notes fixed: a single-child frontier advances without a request and contributes nothing to the score; reachedLeaf tells a maxDepth cut from a finished walk. DESIGN.md 16 updated.
